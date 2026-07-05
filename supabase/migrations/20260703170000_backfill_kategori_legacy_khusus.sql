-- Tindak lanjut audit backfill: 3 varian teks nama_anomali lama yang tidak
-- ke-backfill otomatis, dikonfirmasi manual oleh pemilik data:
--   - "Kegiatan tidak memproduksi barang sendiri, namun komposisi
--      pengeluaran pada biaya produksi dominan (>50%)" = UP1 (Biaya Produksi
--      Dominan, usaha) -- teks lama beda format, tidak match regex standar.
--   - "Selisih pendapatan dan pengeluaran negatif" = UP2 (Keuntungan Usaha,
--      usaha) -- teks lama tanpa prefix "Jumlah Anomali Data N (...)".
--   - "Jumlah Anomali 7 (Pengeluaran listrik sebulan < Rp100.000 atau daya
--      listrik < 900 watt tetapi memiliki lemari es/kulkas, AC,
--      komputer/laptop/tablet) belum ditindaklanjuti" = KP7 (keluarga) --
--      kategori baru, belum ada di re-import excel terbaru sama sekali.
--
-- nama_subjek diambil dari baris anomali_pusat_temuan LAIN milik
-- assignment_id yang sama (scope sama) -- 1 assignment = 1 subjek utk
-- keluarga (aman), tapi utk usaha bisa ambigu kalau >1 usaha per assignment
-- (best-effort, sama seperti catatan backfill sebelumnya). Kalau assignment
-- itu sendiri sudah tidak ada sama sekali di anomali_pusat_temuan (rumah
-- tangga/usaha sudah tidak muncul di re-import), nama_subjek jatuh ke ''.

-- ============================================================
-- 1. Daftarkan kategori baru KP7
-- ============================================================
insert into public.anomali_pusat_kategori (anomali_id, scope, kategori, deskripsi_rule)
values (
  'KP7',
  'keluarga',
  'Pengeluaran Listrik vs Kepemilikan Elektronik',
  'Pengeluaran listrik sebulan < Rp100.000 atau daya listrik < 900 watt tetapi memiliki lemari es/kulkas, AC, komputer/laptop/tablet'
)
on conflict (anomali_id) do nothing;

-- ============================================================
-- 2. Backfill 3 varian teks khusus ke anomali_pusat_respons
-- ============================================================
with mapping (pola, kategori_kode, scope) as (
  values
    ('Kegiatan tidak memproduksi barang sendiri, namun komposisi pengeluaran pada biaya produksi dominan (>50%)', 'UP1', 'usaha'),
    ('Selisih pendapatan dan pengeluaran negatif', 'UP2', 'usaha'),
    ('Jumlah Anomali 7 (Pengeluaran listrik sebulan < Rp100.000 atau daya listrik < 900 watt tetapi memiliki lemari es/kulkas, AC, komputer/laptop/tablet) belum ditindaklanjuti', 'KP7', 'keluarga')
),
subjek_per_assignment as (
  select distinct on (t.assignment_id, t.scope)
    t.assignment_id, t.scope, t.nama_subjek
  from public.anomali_pusat_temuan t
  order by t.assignment_id, t.scope, t.imported_at desc
)
insert into public.anomali_pusat_respons (
  sumber, scope, assignment_id, nama_subjek, kategori_kode,
  petugas_id, jenis_respons, keterangan, created_at, updated_at
)
select
  'pusat_baru',
  m.scope,
  k.assignment_id,
  coalesce(s.nama_subjek, ''),
  m.kategori_kode,
  k.petugas_id,
  'konfirmasi_valid',
  k.keterangan,
  k.updated_at,
  k.updated_at
from public.se2026_anomali_pusat_keterangan k
join mapping m on m.pola = k.nama_anomali
left join subjek_per_assignment s
  on s.assignment_id = k.assignment_id and s.scope = m.scope
where length(trim(k.keterangan)) > 0
on conflict do nothing;
