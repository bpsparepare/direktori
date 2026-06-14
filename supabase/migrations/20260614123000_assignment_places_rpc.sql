create index if not exists fasih_assignments_source_modified_at_idx
on public.fasih_assignments using btree (source_modified_at desc);

create index if not exists fasih_assignments_fullcode_modified_idx
on public.fasih_assignments using btree (
  (
    (((((((payload_json -> 'region'::text) -> 'level1'::text) -> 'level2'::text) -> 'level3'::text) -> 'level4'::text) -> 'level5'::text) -> 'level6'::text) ->> 'fullCode'::text
  ),
  source_modified_at desc
);

drop function if exists public.get_assignment_places_for_current_user(
  text,
  timestamp with time zone
);

create function public.get_assignment_places_for_current_user(
  p_sync_mode text,
  p_modified_after timestamp with time zone default null
)
returns table (
  id bigint,
  workspace_key_hash text,
  survey_period_id text,
  assignment_id text,
  idsbr text,
  nama_usaha text,
  alamat text,
  kode_usaha text,
  status_text text,
  latitude double precision,
  longitude double precision,
  modified timestamp with time zone,
  source_modified_at timestamp with time zone,
  last_seen_at timestamp with time zone,
  updated_at timestamp with time zone,
  fullcode_subsls text
)
language plpgsql
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
      fa.id,
      fa.workspace_key_hash,
      fa.survey_period_id,
      fa.assignment_id,
      (fa.payload_json ->> 'data3'::text) as idsbr,
      (fa.payload_json ->> 'data1'::text) as nama_usaha,
      (fa.payload_json ->> 'data2'::text) as alamat,
      (fa.payload_json ->> 'data6'::text) as kode_usaha,
      fa.status_text,
      ((fa.payload_json ->> 'latitude'::text))::double precision as latitude,
      ((fa.payload_json ->> 'longitude'::text))::double precision as longitude,
      fa.source_modified_at as modified,
      fa.source_modified_at,
      fa.last_seen_at,
      fa.updated_at,
      ((((((((fa.payload_json -> 'region'::text) -> 'level1'::text) -> 'level2'::text) -> 'level3'::text) -> 'level4'::text) -> 'level5'::text) -> 'level6'::text) ->> 'fullCode'::text) as fullcode_subsls
    from public.fasih_assignments fa
    where
      (fa.payload_json ->> 'latitude'::text) is not null
      and (fa.payload_json ->> 'longitude'::text) is not null
      and ((fa.payload_json ->> 'latitude'::text))::double precision >= -90
      and ((fa.payload_json ->> 'latitude'::text))::double precision <= 90
      and ((fa.payload_json ->> 'longitude'::text))::double precision >= -180
      and ((fa.payload_json ->> 'longitude'::text))::double precision <= 180
      and (
      p_sync_mode = 'full'
      or p_modified_after is null
      or fa.source_modified_at > p_modified_after
      );
    return;
  end if;

  if v_role not in ('pengawas', 'pendata') then
    return;
  end if;

  return query
  with wilayah_scope as (
    select distinct
    from public.se2026_wilayah_tugas wt
    where (
      v_role = 'pengawas' and wt.pml_id = v_petugas_id
    ) or (
      v_role = 'pendata' and wt.ppl_id = v_petugas_id
    )
  )
  select distinct
    fa.id,
    fa.workspace_key_hash,
    fa.survey_period_id,
    fa.assignment_id,
    (fa.payload_json ->> 'data3'::text) as idsbr,
    (fa.payload_json ->> 'data1'::text) as nama_usaha,
    (fa.payload_json ->> 'data2'::text) as alamat,
    (fa.payload_json ->> 'data6'::text) as kode_usaha,
    fa.status_text,
    ((fa.payload_json ->> 'latitude'::text))::double precision as latitude,
    ((fa.payload_json ->> 'longitude'::text))::double precision as longitude,
    fa.source_modified_at as modified,
    fa.source_modified_at,
    fa.last_seen_at,
    fa.updated_at,
    ((((((((fa.payload_json -> 'region'::text) -> 'level1'::text) -> 'level2'::text) -> 'level3'::text) -> 'level4'::text) -> 'level5'::text) -> 'level6'::text) ->> 'fullCode'::text) as fullcode_subsls
  from public.fasih_assignments fa
  join wilayah_scope ws
    on ((((((((fa.payload_json -> 'region'::text) -> 'level1'::text) -> 'level2'::text) -> 'level3'::text) -> 'level4'::text) -> 'level5'::text) -> 'level6'::text) ->> 'fullCode'::text) = ws.wilayah_id
  where
    (fa.payload_json ->> 'latitude'::text) is not null
    and (fa.payload_json ->> 'longitude'::text) is not null
    and ((fa.payload_json ->> 'latitude'::text))::double precision >= -90
    and ((fa.payload_json ->> 'latitude'::text))::double precision <= 90
    and ((fa.payload_json ->> 'longitude'::text))::double precision >= -180
    and ((fa.payload_json ->> 'longitude'::text))::double precision <= 180
    and (
    p_sync_mode = 'full'
    or p_modified_after is null
    or fa.source_modified_at > p_modified_after
    );
end;
$$;

grant execute on function public.get_assignment_places_for_current_user(text, timestamp with time zone) to authenticated;
