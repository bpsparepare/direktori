-- Gabungkan se2026_anomali_kategori (kategori sisi Temuan/wilayah, scope
-- keluarga/anggota, kode "ANOM-xxx") ke dalam anomali_pusat_kategori (kategori
-- sisi Pusat, scope usaha/keluarga, kode "KP#"/"UP#"). Format anomali_id
-- kedua sisi tidak tumpang tindih, jadi bisa langsung disatukan tanpa rename.
--
-- se2026_anomali_kategori TIDAK di-drop -- datanya sudah dicopy, tapi
-- tabelnya dibiarkan sampai dipastikan tidak ada pemakai lain (mengikuti pola
-- yang sama dengan se2026_anomali_pusat).

-- 1. Perluas constraint scope supaya menerima 'anggota' juga.
alter table public.anomali_pusat_kategori
  drop constraint anomali_pusat_kategori_scope_check;

alter table public.anomali_pusat_kategori
  add constraint anomali_pusat_kategori_scope_check
  check (scope = any (array['usaha', 'keluarga', 'anggota']));

-- 2. Copy semua kategori Temuan yang ada ke tabel gabungan.
insert into public.anomali_pusat_kategori (
  anomali_id, scope, kategori, deskripsi_rule, created_at
)
select anomali_id, scope, kategori, deskripsi_rule, created_at
from public.se2026_anomali_kategori
on conflict (anomali_id) do update set
  scope          = excluded.scope,
  kategori       = excluded.kategori,
  deskripsi_rule = excluded.deskripsi_rule;
