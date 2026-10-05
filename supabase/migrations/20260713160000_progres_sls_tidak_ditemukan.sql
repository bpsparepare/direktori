-- get_progres_sls_by_wilayah: tambah kk_tidak_ditemukan & usaha_tidak_ditemukan
-- pada output (untuk kolom "Tidak Ditemukan" di tab Riil).
-- Return type berubah -> drop dulu.

drop function if exists public.get_progres_sls_by_wilayah();

create function public.get_progres_sls_by_wilayah()
returns table (
  kode_wilayah          text,
  ppl_id                uuid,
  snapshot_date         date,
  kk_riil               integer,
  usaha_riil            integer,
  usaha_ditemukan       integer,
  kk_tidak_ditemukan    integer,
  usaha_tidak_ditemukan integer
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_auth_uid   uuid := auth.uid();
  v_user_id    uuid;
  v_petugas_id uuid;
  v_role       text;
  v_is_active  boolean := false;
begin
  if v_auth_uid is null then
    return;
  end if;

  select u.id into v_user_id
  from public.users u
  where u.auth_uid = v_auth_uid
  limit 1;
  if v_user_id is null then
    return;
  end if;

  select p.id, p.role, coalesce(p.is_active, false)
    into v_petugas_id, v_role, v_is_active
  from public.se2026_petugas p
  where p.user_id = v_user_id
  order by p.created_at desc nulls last
  limit 1;

  if not v_is_active or v_petugas_id is null then
    return;
  end if;

  return query
  with wilayah_scope as (
    select distinct on (left(wt.id, 16))
      left(wt.id, 16) as w16,
      wt.pml_id,
      wt.ppl_id as scope_ppl_id
    from public.se2026_wilayah_tugas wt
    where wt.id is not null
    order by left(wt.id, 16), wt.created_at desc nulls last
  ),
  latest as (
    select distinct on (left(ps.level_6_full_code, 16))
      left(ps.level_6_full_code, 16) as w16,
      ps.snapshot_date,
      ps.kk_riil,
      ps.usaha_riil,
      ps.usaha_ditemukan,
      ps.kk_tidak_ditemukan,
      ps.usaha_tidak_ditemukan
    from public.se2026_progres_sls_harian ps
    order by left(ps.level_6_full_code, 16), ps.snapshot_date desc
  )
  select
    ws.w16 as kode_wilayah,
    ws.scope_ppl_id as ppl_id,
    l.snapshot_date,
    coalesce(l.kk_riil, 0),
    coalesce(l.usaha_riil, 0),
    coalesce(l.usaha_ditemukan, 0),
    coalesce(l.kk_tidak_ditemukan, 0),
    coalesce(l.usaha_tidak_ditemukan, 0)
  from wilayah_scope ws
  join latest l on l.w16 = ws.w16
  where (
    v_role = 'admin'
    or (v_role = 'pengawas' and ws.pml_id = v_petugas_id)
    or (v_role = 'pendata'  and ws.scope_ppl_id = v_petugas_id)
  );
end;
$$;

grant execute on function public.get_progres_sls_by_wilayah() to authenticated;
