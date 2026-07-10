-- Terapkan override koordinat (se2026_koordinat_override) saat membaca titik
-- assignment. Posisi hasil edit (drag di peta) menggantikan lat/long import via
-- COALESCE(override, keterangan_umum). Signature RPC tidak berubah.
--
-- Menyalin ulang definisi dari 20260705160000 + LEFT JOIN override.

-- 1) RPC per-SLS (dipakai peta on-demand).
create or replace function public.get_assignment_places_by_sls(
  p_idsls text
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
  v_len int;
  v_sls14 text;
  v_code16 text;
begin
  if p_idsls is null or length(p_idsls) < 14 then
    return;
  end if;
  v_len := length(p_idsls);
  v_sls14 := left(p_idsls, 14);
  v_code16 := left(p_idsls, 16);

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

  if v_role in ('pengawas', 'pendata') then
    if not exists (
      select 1
      from public.se2026_wilayah_tugas wt
      where left(wt.id, 14) = v_sls14
        and (
          (v_role = 'pengawas' and wt.pml_id = v_petugas_id)
          or (v_role = 'pendata' and wt.ppl_id = v_petugas_id)
        )
    ) then
      return;
    end if;
  elsif v_role <> 'admin' then
    return;
  end if;

  return query
  select
    ku.assignment_id,
    ku.no_bang::integer,
    ku.data1 as nama_usaha,
    coalesce(ov.latitude,  ku.latitude)  as latitude,
    coalesce(ov.longitude, ku.longitude) as longitude
  from public.se2026_keterangan_umum ku
  left join public.se2026_koordinat_override ov
    on ov.assignment_id = ku.assignment_id
  where
    (
      (v_len >= 16 and ku.kode_wilayah = v_code16)
      or (v_len < 16 and left(ku.kode_wilayah, 14) = v_sls14)
    )
    and ku.kode_bang is not null
    and coalesce(ov.latitude,  ku.latitude)  is not null
    and coalesce(ov.longitude, ku.longitude) is not null
    and coalesce(ov.latitude,  ku.latitude)  between -90  and 90
    and coalesce(ov.longitude, ku.longitude) between -180 and 180;
end;
$$;

grant execute on function public.get_assignment_places_by_sls(text) to authenticated;

-- 2) RPC full / incremental (dipakai tombol download / cache offline).
create or replace function public.get_assignment_places_for_current_user(
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
      coalesce(ov.latitude,  ku.latitude)  as latitude,
      coalesce(ov.longitude, ku.longitude) as longitude
    from public.se2026_keterangan_umum ku
    left join public.se2026_koordinat_override ov
      on ov.assignment_id = ku.assignment_id
    where
      ku.kode_bang is not null
      and coalesce(ov.latitude,  ku.latitude)  is not null
      and coalesce(ov.longitude, ku.longitude) is not null
      and coalesce(ov.latitude,  ku.latitude)  between -90  and 90
      and coalesce(ov.longitude, ku.longitude) between -180 and 180
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
    coalesce(ov.latitude,  ku.latitude)  as latitude,
    coalesce(ov.longitude, ku.longitude) as longitude
  from public.se2026_keterangan_umum ku
  join wilayah_scope ws
    on ku.kode_wilayah = ws.kode_wilayah
  left join public.se2026_koordinat_override ov
    on ov.assignment_id = ku.assignment_id
  where
    ku.kode_bang is null
    and coalesce(ov.latitude,  ku.latitude)  is not null
    and coalesce(ov.longitude, ku.longitude) is not null
    and coalesce(ov.latitude,  ku.latitude)  between -90  and 90
    and coalesce(ov.longitude, ku.longitude) between -180 and 180
    and (
      p_sync_mode = 'full'
      or p_modified_after is null
      or ku.source_modified_at > p_modified_after
    );
end;
$$;

grant execute on function public.get_assignment_places_for_current_user(text, timestamp with time zone) to authenticated;
