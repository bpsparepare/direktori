-- Bug di migration 20260701170000: kode_wilayah generated column
-- meng-concat kode_kec + kode_desa, padahal kode_desa sudah memuat kode_kec
-- di dalamnya (kode_desa = 10 digit: kec(7)+desa(3)). Hasilnya kode_wilayah
-- jadi 23 digit dengan kec dobel, bukan 16 digit standar level SLS
-- (kode_desa 10 + kode_sls 4 + sub_sls 2), sehingga semua scoping yang pakai
-- left(kode_wilayah, 16) (get_anomali_pusat_v2, get_anomali_gabungan) tidak
-- pernah match ke se2026_wilayah_tugas.
--
-- Drop + re-create generated column: Postgres otomatis hitung ulang nilainya
-- untuk semua baris existing, tidak perlu re-import excel.

drop index if exists public.idx_anomali_pusat_temuan_wilayah;

alter table public.anomali_pusat_temuan
  drop column kode_wilayah;

alter table public.anomali_pusat_temuan
  add column kode_wilayah text generated always as (
    coalesce(kode_desa, '') || coalesce(kode_sls, '') || coalesce(sub_sls, '')
  ) stored;

create index idx_anomali_pusat_temuan_wilayah
  on public.anomali_pusat_temuan (kode_wilayah);
