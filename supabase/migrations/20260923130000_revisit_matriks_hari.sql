-- Matriks Rekap Revisit: per petugas × "hari ke-" alokasi, berapa SLS
-- jadwal hari itu yang sudah dilapor. Dipakai untuk melihat sel mana yang
-- masih kosong (belum lapor). Admin = semua petugas; selain admin = sendiri.
create or replace function public.get_revisit_matriks_hari()
returns table (
  petugas_id   uuid,
  hari_ke      integer,
  jumlah_sls   integer,
  sls_dilapor  integer,
  sls_selesai  integer,
  total_didata integer,
  total_submit integer
)
language sql
stable
security definer
set search_path = public
as $$
  with alok as (
    select a.petugas_id, a.kode_sls, a.hari_ke
    from public._revisit_me() me
    join public.se2026_revisit_alokasi a
      on me.role = 'admin' or a.petugas_id = me.petugas_id
    where me.petugas_id is not null
  ),
  per_sls as (
    select
      al.petugas_id                              as pid,
      al.hari_ke                                 as hari,
      al.kode_sls                                as kode,
      count(l.id)::integer                       as n_lap,
      coalesce(sum(l.jumlah_dicek), 0)::integer  as didata,
      coalesce(sum(l.jumlah_submit), 0)::integer as submitted,
      last.status                                as status_terakhir
    from alok al
    left join public.se2026_revisit_laporan l on l.kode_sls = al.kode_sls
    left join lateral (
      select l2.status
      from public.se2026_revisit_laporan l2
      where l2.kode_sls = al.kode_sls
      order by l2.tanggal desc, l2.updated_at desc
      limit 1
    ) last on true
    group by al.petugas_id, al.hari_ke, al.kode_sls, last.status
  )
  select
    per_sls.pid,
    per_sls.hari,
    count(*)::integer,
    count(*) filter (where per_sls.n_lap > 0)::integer,
    count(*) filter (where per_sls.status_terakhir = 'selesai')::integer,
    coalesce(sum(per_sls.didata), 0)::integer,
    coalesce(sum(per_sls.submitted), 0)::integer
  from per_sls
  group by per_sls.pid, per_sls.hari
  order by per_sls.pid, per_sls.hari nulls last;
$$;

grant execute on function public.get_revisit_matriks_hari() to authenticated;
