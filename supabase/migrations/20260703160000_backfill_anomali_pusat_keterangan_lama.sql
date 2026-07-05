-- Backfill respons dari se2026_anomali_pusat_keterangan (legacy, terikat ke
-- se2026_anomali_pusat / data pusat versi lama) ke anomali_pusat_respons
-- (skema baru, terikat ke anomali_pusat_temuan hasil re-import excel Fasih).
--
-- Data lama & baru merepresentasikan anomali yang SAMA (versi lama "kotor",
-- versi baru sudah di-fix), jadi dicocokkan via assignment_id + kategori
-- (nama_anomali di-parse dgn regex yang sama seperti import_anomali_pusat_batch
-- utk dapat nomor kategori, lalu dicocokkan ke kategori_kode di
-- anomali_pusat_temuan berdasarkan scope-nya).
--
-- se2026_anomali_pusat_keterangan tidak punya kolom jenis_respons (migration
-- 20260701160000 yang menambahkannya ternyata belum ke-apply ke production)
-- -- semua baris lama dianggap 'konfirmasi_valid', karena fitur lama memang
-- cuma "isi keterangan/penjelasan".
--
-- CATATAN: kalau 1 assignment_id punya >1 subjek dgn kategori yg sama
-- (kasus yg jadi alasan nama_subjek ada di kunci baru), respons lama akan
-- ter-"siarkan" ke semua subjek yg cocok itu -- data lama tidak menyimpan
-- nama subjek spesifik jadi ini best-effort, bukan hilang tapi bisa dobel.

insert into public.anomali_pusat_respons (
  sumber, scope, assignment_id, nama_subjek, kategori_kode,
  petugas_id, jenis_respons, keterangan, created_at, updated_at
)
select distinct
  'pusat_baru',
  t.scope,
  t.assignment_id,
  t.nama_subjek,
  t.kategori_kode,
  p.petugas_id,
  p.jenis_respons,
  p.keterangan,
  p.updated_at,
  p.updated_at
from (
  select
    k.assignment_id,
    k.petugas_id,
    'konfirmasi_valid'::text as jenis_respons,
    k.keterangan,
    k.updated_at,
    mm[1] as no_str
  from public.se2026_anomali_pusat_keterangan k
  cross join lateral regexp_matches(
    k.nama_anomali, 'Anomali\s+(?:Data\s+)?(\d+)\s*\(([^)]*)\)'
  ) as mm
  where length(trim(k.keterangan)) > 0
) p
join public.anomali_pusat_temuan t
  on t.assignment_id = p.assignment_id
 and t.kategori_kode = (case when t.scope = 'usaha' then 'UP' else 'KP' end) || p.no_str
on conflict do nothing;
