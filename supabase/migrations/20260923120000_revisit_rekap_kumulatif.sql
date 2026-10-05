-- Rekap Revisit (admin): ringkasan KUMULATIF, bukan per tanggal upload.
--   1. get_revisit_progres_hari_ke  -> progres per "hari ke-" alokasi
--      (se2026_revisit_alokasi.hari_ke), untuk grafik.
--   2. get_revisit_rekap_petugas    -> total per petugas sejak awal
--      (berapa dari berapa SLS, didata, submit, sisa potensi).
-- Keduanya: admin = semua petugas; selain admin = miliknya sendiri.

-- ── Progres per hari ke- ────────────────────────────────────────────────────
create or replace function public.get_revisit_progres_hari_ke()
returns table (
  hari_ke            integer,
  jumlah_sls         integer,
  sls_dilapor        integer,
  sls_selesai        integer,
  total_didata       integer,
  total_submit       integer,
  sisa_belum_didata  integer
)
language sql
stable
security definer
set search_path = public
as $$
  with alok as (
    select a.kode_sls, a.hari_ke
    from public._revisit_me() me
    join public.se2026_revisit_alokasi a
      on me.role = 'admin' or a.petugas_id = me.petugas_id
    where me.petugas_id is not null
  ),
  per_sls as (
    select
      al.hari_ke,
      al.kode_sls,
      coalesce(sum(l.jumlah_dicek), 0)::integer  as didata,
      coalesce(sum(l.jumlah_submit), 0)::integer as submitted,
      count(l.id)::integer                       as n_lap,
      last.jumlah_belum_didata                   as sisa,
      last.status                                as status_terakhir
    from alok al
    left join public.se2026_revisit_laporan l on l.kode_sls = al.kode_sls
    left join lateral (
      select l2.status, l2.jumlah_belum_didata
      from public.se2026_revisit_laporan l2
      where l2.kode_sls = al.kode_sls
      order by l2.tanggal desc, l2.updated_at desc
      limit 1
    ) last on true
    group by al.hari_ke, al.kode_sls, last.jumlah_belum_didata, last.status
  )
  select
    per_sls.hari_ke,
    count(*)::integer,
    count(*) filter (where per_sls.n_lap > 0)::integer,
    count(*) filter (where per_sls.status_terakhir = 'selesai')::integer,
    coalesce(sum(per_sls.didata), 0)::integer,
    coalesce(sum(per_sls.submitted), 0)::integer,
    coalesce(sum(per_sls.sisa), 0)::integer
  from per_sls
  group by per_sls.hari_ke
  order by per_sls.hari_ke nulls last;
$$;

grant execute on function public.get_revisit_progres_hari_ke() to authenticated;

-- ── Rekap kumulatif per petugas ─────────────────────────────────────────────
create or replace function public.get_revisit_rekap_petugas()
returns table (
  petugas_id         uuid,
  nama               text,
  role               text,
  tim                text,
  jumlah_sls         integer,
  sls_dilapor        integer,
  sls_selesai        integer,
  total_didata       integer,
  total_submit       integer,
  sisa_belum_didata  integer,
  jumlah_laporan     integer,
  jumlah_foto        integer,
  tanggal_terakhir   date
)
language sql
stable
security definer
set search_path = public
as $$
  with per_sls as (
    select
      a.petugas_id,
      a.kode_sls,
      coalesce(sum(l.jumlah_dicek), 0)::integer  as didata,
      coalesce(sum(l.jumlah_submit), 0)::integer as submitted,
      count(l.id)::integer                       as n_lap,
      max(l.tanggal)                             as tgl_terakhir,
      coalesce(sum((
        select count(*) from public.se2026_revisit_foto f
        where f.laporan_id = l.id
      )), 0)::integer                            as n_foto,
      last.jumlah_belum_didata                   as sisa,
      last.status                                as status_terakhir
    from public.se2026_revisit_alokasi a
    left join public.se2026_revisit_laporan l on l.kode_sls = a.kode_sls
    left join lateral (
      select l2.status, l2.jumlah_belum_didata
      from public.se2026_revisit_laporan l2
      where l2.kode_sls = a.kode_sls
      order by l2.tanggal desc, l2.updated_at desc
      limit 1
    ) last on true
    group by a.petugas_id, a.kode_sls, last.jumlah_belum_didata, last.status
  )
  select
    n.petugas_id,
    n.nama::text,
    n.role::text,
    rp.tim::text,
    count(ps.kode_sls)::integer,
    count(ps.kode_sls) filter (where ps.n_lap > 0)::integer,
    count(ps.kode_sls) filter (where ps.status_terakhir = 'selesai')::integer,
    coalesce(sum(ps.didata), 0)::integer,
    coalesce(sum(ps.submitted), 0)::integer,
    coalesce(sum(ps.sisa), 0)::integer,
    coalesce(sum(ps.n_lap), 0)::integer,
    coalesce(sum(ps.n_foto), 0)::integer,
    max(ps.tgl_terakhir)
  from public._revisit_me() me
  join public.se2026_revisit_petugas rp on true
  join public.vw_revisit_petugas_nama n on n.petugas_id = rp.petugas_id
  left join per_sls ps on ps.petugas_id = rp.petugas_id
  where me.petugas_id is not null
    and (me.role = 'admin' or rp.petugas_id = me.petugas_id)
  group by n.petugas_id, n.nama, n.role, rp.tim
  order by n.nama;
$$;

grant execute on function public.get_revisit_rekap_petugas() to authenticated;
