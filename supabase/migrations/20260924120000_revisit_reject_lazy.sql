-- Tab Reject: muat bertahap supaya ringan.
--   1. get_revisit_reject_sls        -> ringkasan per SLS saja (1 baris/SLS)
--   2. get_revisit_reject_detail(kode) -> isi assignment satu SLS saja
-- Menggantikan pemakaian get_revisit_reject (yang menarik SEMUA assignment
-- sekaligus); fungsi lama dibiarkan agar versi aplikasi lama tetap jalan.

-- ── Ringkasan per SLS ───────────────────────────────────────────────────────
create or replace function public.get_revisit_reject_sls()
returns table (
  kode_sls           text,
  level_6_name       text,
  nm_kec             text,
  nm_desa            text,
  nm_sls             text,
  revisit_petugas_id uuid,
  revisit_nama       text,
  revisit_tim        text,
  hari_ke            integer,
  jumlah_assignment  integer,
  jumlah_ditandai    integer
)
language sql
stable
security definer
set search_path = public
as $$
  -- Daftar SLS digerakkan dari se2026_revisit_alokasi (tabel kecil, sudah
  -- memuat petugas & hari ke-), bukan dari agregasi tabel sumber yang besar.
  -- Admin juga melihat SLS di tabel sumber yang belum dialokasikan.
  with kode as (
    select a.kode_sls, a.petugas_id, a.hari_ke
    from public._revisit_me() me
    join public.se2026_revisit_alokasi a
      on me.role = 'admin' or a.petugas_id = me.petugas_id
    where me.petugas_id is not null
    union all
    select distinct t.level_6_full_code, null::uuid, null::integer
    from public._revisit_me() me
    join public.se2026_revisit_reject_sumber t on me.role = 'admin'
    where me.petugas_id is not null
      and not exists (
        select 1 from public.se2026_revisit_alokasi a
        where a.kode_sls = t.level_6_full_code
      )
  ),
  hitung as (
    select
      k.kode_sls,
      k.petugas_id,
      k.hari_ke,
      (
        select count(*)::integer
        from public.se2026_revisit_reject_sumber t
        where t.level_6_full_code = k.kode_sls
      ) as jumlah_assignment,
      (
        select count(*)::integer
        from public.se2026_revisit_reject_sumber t
        join public.se2026_revisit_reject r
          on r.assignment_id = t.assignment_id
        where t.level_6_full_code = k.kode_sls
      ) as jumlah_ditandai,
      (
        select t.level_6_name
        from public.se2026_revisit_reject_sumber t
        where t.level_6_full_code = k.kode_sls
        limit 1
      ) as level_6_name
    from kode k
  )
  select
    h.kode_sls::text,
    h.level_6_name::text,
    sw.nm_kec::text,
    sw.nm_desa::text,
    sw.nm_sls::text,
    h.petugas_id,
    n.nama::text,
    rp.tim::text,
    h.hari_ke,
    h.jumlah_assignment,
    h.jumlah_ditandai
  from hitung h
  left join public.vw_fasih_wilayah_scope_base sw on sw.kode_wilayah = h.kode_sls
  left join public.vw_revisit_petugas_nama n on n.petugas_id = h.petugas_id
  left join public.se2026_revisit_petugas rp on rp.petugas_id = h.petugas_id
  -- SLS tanpa assignment pada daftar sumber tidak perlu ditampilkan.
  where h.jumlah_assignment > 0
  order by sw.nm_kec nulls last, sw.nm_desa nulls last, h.kode_sls;
$$;

grant execute on function public.get_revisit_reject_sls() to authenticated;

-- ── Isi satu SLS ────────────────────────────────────────────────────────────
create or replace function public.get_revisit_reject_detail(p_kode_sls text)
returns table (
  assignment_id           text,
  assignment_status_alias text,
  assignment_status_id    integer,
  level_6_full_code       text,
  level_6_name            text,
  nama                    text,
  alamat                  text,
  no_bang                 text,
  nm_kec                  text,
  nm_desa                 text,
  nm_sls                  text,
  revisit_petugas_id      uuid,
  revisit_nama            text,
  revisit_tim             text,
  hari_ke                 integer,
  updated_at              timestamptz,
  perlu_reject            boolean,
  alasan_reject           text,
  reject_oleh             text,
  reject_at               timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    t.assignment_id,
    t.assignment_status_alias::text,
    t.assignment_status_id,
    t.level_6_full_code::text,
    t.level_6_name::text,
    t.nama::text,
    t.alamat::text,
    t.no_bang::text,
    sw.nm_kec::text,
    sw.nm_desa::text,
    sw.nm_sls::text,
    a.petugas_id,
    n.nama::text,
    rp.tim::text,
    a.hari_ke,
    t.updated_at,
    (r.assignment_id is not null),
    r.alasan,
    coalesce(nullif(trim(ru.name), ''), ru.email)::text,
    r.updated_at
  from public._revisit_me() me
  join public.se2026_revisit_reject_sumber t
    on t.level_6_full_code = p_kode_sls
  left join public.se2026_revisit_alokasi a on a.kode_sls = t.level_6_full_code
  left join public.vw_fasih_wilayah_scope_base sw
    on sw.kode_wilayah = t.level_6_full_code
  left join public.vw_revisit_petugas_nama n on n.petugas_id = a.petugas_id
  left join public.se2026_revisit_petugas rp on rp.petugas_id = a.petugas_id
  left join public.se2026_revisit_reject r on r.assignment_id = t.assignment_id
  left join public.se2026_petugas rpg on rpg.id = r.flagged_by
  left join public.users ru on ru.id = rpg.user_id
  where me.petugas_id is not null
    and (me.role = 'admin' or a.petugas_id = me.petugas_id)
  order by t.nama, t.assignment_id;
$$;

grant execute on function public.get_revisit_reject_detail(text) to authenticated;
