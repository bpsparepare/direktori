-- Ganti sumber data get_assignment_places_for_current_user dari
-- mv_fasih_assignment_summary ke tabel public.se2026_keterangan_umum.
--
-- Output kolom tetap sama (assignment_id, no_bang, nama_usaha, latitude,
-- longitude) sehingga aplikasi Flutter / model AssignmentPlaceRecord tidak
-- perlu berubah. Pemetaan:
--   nama_usaha  <- data1
--   no_bang     <- no_bang (bigint di-cast ke integer agar signature tetap)
--   latitude/longitude/kode_wilayah/source_modified_at <- kolom senama.
--
-- Logika role & scope wilayah dipertahankan: admin melihat semua, pengawas
-- (pml_id) / pendata (ppl_id) dibatasi lewat se2026_wilayah_tugas.kode_wilayah.

drop function if exists public.get_assignment_places_for_current_user(
  text,
  timestamp with time zone
);

create function public.get_assignment_places_for_current_user(
  p_sync_mode text,
  p_modified_after timestamp with time zone default null
)
returns table (
  assignment_id text,
  no_bang integer,
  nama_usaha text,
  latitude numeric,
  longitude numeric
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_auth_uid uuid := auth.uid();
  v_user_id uuid;
  v_petugas_id uuid;
  v_role text;
  v_is_active boolean := false;
begin
  if p_sync_mode not in ('full', 'incremental') then
    raise exception 'Invalid sync mode: %', p_sync_mode
      using errcode = '22023';
  end if;

  if v_auth_uid is null then
    return;
  end if;

  select u.id
    into v_user_id
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

  if v_petugas_id is null or not v_is_active then
    return;
  end if;

  if v_role = 'admin' then
    return query
    select
      ku.assignment_id,
      ku.no_bang::integer,
      ku.data1 as nama_usaha,
      ku.latitude,
      ku.longitude
    from public.se2026_keterangan_umum ku
    where
      ku.latitude is not null
      and ku.longitude is not null
      and ku.latitude between -90 and 90
      and ku.longitude between -180 and 180
      and (
        p_sync_mode = 'full'
        or p_modified_after is null
        or ku.source_modified_at > p_modified_after
      );
    return;
  end if;

  if v_role not in ('pengawas', 'pendata') then
    return;
  end if;

  return query
  with wilayah_scope as (
    select distinct wt.id as kode_wilayah
    from public.se2026_wilayah_tugas wt
    where (
      v_role = 'pengawas' and wt.pml_id = v_petugas_id
    ) or (
      v_role = 'pendata' and wt.ppl_id = v_petugas_id
    )
  )
  select distinct
    ku.assignment_id,
    ku.no_bang::integer,
    ku.data1 as nama_usaha,
    ku.latitude,
    ku.longitude
  from public.se2026_keterangan_umum ku
  join wilayah_scope ws
    on ku.kode_wilayah = ws.kode_wilayah
  where
    ku.latitude is not null
    and ku.longitude is not null
    and ku.latitude between -90 and 90
    and ku.longitude between -180 and 180
    and (
      p_sync_mode = 'full'
      or p_modified_after is null
      or ku.source_modified_at > p_modified_after
    );
end;
$$;

grant execute on function public.get_assignment_places_for_current_user(text, timestamp with time zone) to authenticated;
