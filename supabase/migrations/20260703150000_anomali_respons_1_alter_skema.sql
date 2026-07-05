-- Satukan respons petugas utk sumber 'kualitas' (wilayah) dan 'pusat_baru'
-- ke satu tabel multi-petugas (anomali_pusat_respons, sekarang jadi tabel
-- respons umum -- nama tabel dipertahankan supaya tidak perlu ubah semua
-- referensi). se2026_anomali_temuan TIDAK dihapus/diubah tulisannya, tetap
-- ada sbg riwayat lama read-only; upsert_anomali_tindak_lanjut &
-- upsert_anomali_pusat_respons (versi lama, single-arg) TIDAK di-drop supaya
-- pemakai lain (kalau ada) tidak rusak.
--
-- Kunci respons gabungan: (sumber, scope, assignment_id, nama_subjek,
-- kategori_kode, petugas_id) -- nama_subjek dipakai '' utk wilayah (1
-- subjek/assignment via mv_anomali), diisi asli utk pusat_baru (krn 1
-- assignment bisa >1 usaha/keluarga).

-- ============================================================
-- 1. Perluas skema anomali_pusat_respons (idempotent -- aman dijalankan
--    ulang meski sebagian sudah ter-apply sebelumnya)
-- ============================================================
do $$
begin
    if not exists (
        select 1 from information_schema.columns
        where table_schema = 'public'
          and table_name = 'anomali_pusat_respons'
          and column_name = 'sumber'
    ) then
        alter table public.anomali_pusat_respons
          add column sumber text not null default 'pusat_baru';
    end if;
end $$;

do $$
begin
    if not exists (
        select 1 from pg_constraint
        where conrelid = 'public.anomali_pusat_respons'::regclass
          and conname = 'anomali_pusat_respons_sumber_check'
    ) then
        alter table public.anomali_pusat_respons
          add constraint anomali_pusat_respons_sumber_check
          check (sumber in ('kualitas', 'pusat_baru'));
    end if;
end $$;

-- Nama constraint auto-generate Postgres bisa berbeda/terpotong -- cari lalu
-- drop programatis, jangan tebak nama persisnya.
do $$
declare
    v_conname text;
begin
    select conname into v_conname
    from pg_constraint
    where conrelid = 'public.anomali_pusat_respons'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%scope = ANY%'
      and pg_get_constraintdef(oid) not ilike '%anggota%';
    if v_conname is not null then
        execute format('alter table public.anomali_pusat_respons drop constraint %I', v_conname);
        execute 'alter table public.anomali_pusat_respons add constraint anomali_pusat_respons_scope_check check (scope in (''usaha'', ''keluarga'', ''anggota''))';
    end if;
end $$;

do $$
declare
    v_conname text;
begin
    select conname into v_conname
    from pg_constraint
    where conrelid = 'public.anomali_pusat_respons'::regclass
      and contype = 'u'
      and conname <> 'anomali_pusat_respons_unique_key';
    if v_conname is not null then
        execute format('alter table public.anomali_pusat_respons drop constraint %I', v_conname);
    end if;
end $$;

do $$
begin
    if not exists (
        select 1 from pg_constraint
        where conrelid = 'public.anomali_pusat_respons'::regclass
          and conname = 'anomali_pusat_respons_unique_key'
    ) then
        alter table public.anomali_pusat_respons
          add constraint anomali_pusat_respons_unique_key
          unique (sumber, scope, assignment_id, nama_subjek, kategori_kode, petugas_id);
    end if;
end $$;
