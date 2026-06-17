create or replace view public.vw_fasih_wilayah_scope_base as
select
  wt.id as kode_wilayah,
  wt.id_sls,
  wt.nm_prov,
  wt.nm_kab,
  wt.nm_kec,
  wt.nm_desa,
  wt.nm_sls,
  wt.pml_id,
  pml.user_id as pml_user_id,
  coalesce(nullif(trim(upml.name), ''), nullif(trim(upml.email), ''), 'Tanpa Nama') as pml_name,
  upml.email as pml_username,
  wt.ppl_id,
  ppl.user_id as ppl_user_id,
  coalesce(nullif(trim(uppl.name), ''), nullif(trim(uppl.email), ''), 'Tanpa Nama') as ppl_name,
  uppl.email as ppl_username
from public.se2026_wilayah_tugas wt
left join public.se2026_petugas pml
  on pml.id = wt.pml_id
left join public.users upml
  on upml.id = pml.user_id
left join public.se2026_petugas ppl
  on ppl.id = wt.ppl_id
left join public.users uppl
  on uppl.id = ppl.user_id;

create or replace function public._fasih_current_context()
returns table (
  user_id uuid,
  petugas_id uuid,
  role text,
  is_active boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select
    u.id as user_id,
    p.id as petugas_id,
    p.role,
    coalesce(p.is_active, false) as is_active
  from public.users u
  join public.se2026_petugas p
    on p.user_id = u.id
  where u.auth_uid = auth.uid()
  order by p.created_at desc nulls last
  limit 1
$$;

create or replace function public._fasih_empty_payload(
  p_level text,
  p_limit integer,
  p_offset integer
)
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'summary', jsonb_build_object(
      'level', p_level,
      'total_units', 0,
      'total_assignments', 0
    ),
    'chart', '[]'::jsonb,
    'rows', '[]'::jsonb,
    'status_aliases', '[]'::jsonb,
    'periods', '[]'::jsonb,
    'meta', jsonb_build_object(
      'level', p_level,
      'limit', greatest(1, least(coalesce(p_limit, 20), 200)),
      'offset', greatest(coalesce(p_offset, 0), 0),
      'returned_rows', 0
    )
  )
$$;

create or replace function public._fasih_rekap_build(
  p_level text,
  p_current_petugas_id uuid,
  p_parent_id text default null,
  p_survey_period_id text default null,
  p_search text default null,
  p_limit integer default 20,
  p_offset integer default 0,
  p_sort_by text default 'total_assignment',
  p_sort_dir text default 'desc'
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_limit integer := greatest(1, least(coalesce(p_limit, 20), 200));
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_sort_by text := case lower(coalesce(p_sort_by, ''))
    when 'title' then 'title'
    when 'subtitle' then 'subtitle'
    else 'total_assignment'
  end;
  v_sort_dir text := case lower(coalesce(p_sort_dir, ''))
    when 'asc' then 'asc'
    else 'desc'
  end;
  v_parent_uuid uuid := nullif(trim(p_parent_id), '')::uuid;
  v_result jsonb;
begin
  if p_level not in (
    'pendata_wilayah',
    'pengawas_petugas',
    'admin_pengawas',
    'petugas_by_pengawas',
    'wilayah_by_petugas'
  ) then
    raise exception 'Invalid rekap level: %', p_level
      using errcode = '22023';
  end if;

  with scope_wilayah as (
    select *
    from public.vw_fasih_wilayah_scope_base sw
    where
      (p_level = 'pendata_wilayah' and sw.ppl_id = p_current_petugas_id)
      or (p_level = 'pengawas_petugas' and sw.pml_id = p_current_petugas_id)
      or (p_level = 'admin_pengawas')
      or (p_level = 'petugas_by_pengawas' and sw.pml_id = v_parent_uuid)
      or (p_level = 'wilayah_by_petugas' and sw.ppl_id = v_parent_uuid)
  ),
  available_periods as (
    select distinct mv.survey_period_id
    from scope_wilayah sw
    join public.mv_fasih_assignment_summary mv
      on mv.kode_wilayah = sw.kode_wilayah
    where mv.survey_period_id is not null
  ),
  joined as (
    select
      sw.*,
      mv.assignment_id,
      mv.survey_period_id,
      mv.status_alias
    from scope_wilayah sw
    left join public.mv_fasih_assignment_summary mv
      on mv.kode_wilayah = sw.kode_wilayah
     and (p_survey_period_id is null or mv.survey_period_id = p_survey_period_id)
  ),
  normalized as (
    select
      case
        when p_level = 'admin_pengawas' then coalesce(pml_id::text, '')
        when p_level in ('pengawas_petugas', 'petugas_by_pengawas') then coalesce(ppl_id::text, '')
        else kode_wilayah
      end as unit_id,
      case
        when p_level = 'admin_pengawas' then pml_name
        when p_level in ('pengawas_petugas', 'petugas_by_pengawas') then ppl_name
        else coalesce(nullif(trim(nm_sls), ''), kode_wilayah)
      end as title,
      case
        when p_level = 'admin_pengawas' then coalesce(pml_username, '-')
        when p_level in ('pengawas_petugas', 'petugas_by_pengawas') then coalesce(ppl_username, '-')
        else concat_ws(' / ', nullif(trim(nm_kec), ''), nullif(trim(nm_desa), ''))
      end as subtitle,
      assignment_id,
      coalesce(nullif(trim(status_alias), ''), 'TANPA STATUS') as status_alias
    from joined
  ),
  rows_base as (
    select
      unit_id,
      min(title) as title,
      min(subtitle) as subtitle,
      count(assignment_id)::int as total_assignment
    from normalized
    group by unit_id
  ),
  status_counts as (
    select
      unit_id,
      jsonb_object_agg(status_alias, cnt order by status_alias) as status_counts
    from (
      select
        unit_id,
        status_alias,
        count(assignment_id)::int as cnt
      from normalized
      where assignment_id is not null
      group by unit_id, status_alias
    ) counts
    group by unit_id
  ),
  rows_with_counts as (
    select
      rb.unit_id,
      rb.title,
      rb.subtitle,
      rb.total_assignment,
      coalesce(sc.status_counts, '{}'::jsonb) as status_counts
    from rows_base rb
    left join status_counts sc
      on sc.unit_id = rb.unit_id
  ),
  filtered_rows as (
    select *
    from rows_with_counts
    where
      coalesce(trim(p_search), '') = ''
      or title ilike '%' || trim(p_search) || '%'
      or subtitle ilike '%' || trim(p_search) || '%'
  ),
  summary as (
    select
      count(*)::int as total_units,
      coalesce(sum(total_assignment), 0)::int as total_assignments
    from filtered_rows
  ),
  chart as (
    select
      unit_id,
      title as label,
      total_assignment
    from filtered_rows
    order by total_assignment desc, title asc
    limit 8
  ),
  status_aliases as (
    select
      status_alias,
      count(assignment_id)::int as total
    from normalized
    where assignment_id is not null
    group by status_alias
    order by total desc, status_alias asc
  ),
  periods as (
    select
      ap.survey_period_id as survey_period_id,
      trim(coalesce(sp.name, ap.survey_period_id)) as name,
      coalesce(sp.is_active, false) as is_active,
      sp.start_date,
      sp.end_date
    from available_periods ap
    left join public.monev_fasih_survey_period sp
      on sp.survey_period_id::text = ap.survey_period_id
    order by sp.is_active desc, sp.start_date desc nulls last, name asc
  ),
  paged as (
    select *
    from filtered_rows
    order by
      case when v_sort_by = 'title' and v_sort_dir = 'asc' then title end asc,
      case when v_sort_by = 'title' and v_sort_dir = 'desc' then title end desc,
      case when v_sort_by = 'subtitle' and v_sort_dir = 'asc' then subtitle end asc,
      case when v_sort_by = 'subtitle' and v_sort_dir = 'desc' then subtitle end desc,
      case when v_sort_by = 'total_assignment' and v_sort_dir = 'asc' then total_assignment end asc,
      case when v_sort_by = 'total_assignment' and v_sort_dir = 'desc' then total_assignment end desc,
      title asc
    limit v_limit
    offset v_offset
  )
  select jsonb_build_object(
    'summary',
    jsonb_build_object(
      'level', p_level,
      'total_units', coalesce((select total_units from summary), 0),
      'total_assignments', coalesce((select total_assignments from summary), 0)
    ),
    'chart',
    coalesce((select jsonb_agg(to_jsonb(chart)) from chart), '[]'::jsonb),
    'rows',
    coalesce((select jsonb_agg(to_jsonb(paged)) from paged), '[]'::jsonb),
    'status_aliases',
    coalesce((select jsonb_agg(to_jsonb(status_aliases)) from status_aliases), '[]'::jsonb),
    'periods',
    coalesce((select jsonb_agg(to_jsonb(periods)) from periods), '[]'::jsonb),
    'meta',
    jsonb_build_object(
      'level', p_level,
      'limit', v_limit,
      'offset', v_offset,
      'returned_rows', coalesce((select count(*) from paged), 0),
      'sort_by', v_sort_by,
      'sort_dir', v_sort_dir
    )
  )
  into v_result;

  return coalesce(v_result, public._fasih_empty_payload(p_level, v_limit, v_offset));
end;
$$;

drop function if exists public.get_fasih_rekap_pendata_wilayah(text, text, integer, integer, text, text);
create function public.get_fasih_rekap_pendata_wilayah(
  p_survey_period_id text default null,
  p_search text default null,
  p_limit integer default 50,
  p_offset integer default 0,
  p_sort_by text default 'title',
  p_sort_dir text default 'asc'
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_ctx record;
begin
  select * into v_ctx from public._fasih_current_context();
  if v_ctx.petugas_id is null or v_ctx.role <> 'pendata' or not v_ctx.is_active then
    return public._fasih_empty_payload('pendata_wilayah', p_limit, p_offset);
  end if;
  return public._fasih_rekap_build(
    'pendata_wilayah',
    v_ctx.petugas_id,
    null,
    p_survey_period_id,
    p_search,
    p_limit,
    p_offset,
    p_sort_by,
    p_sort_dir
  );
end;
$$;

drop function if exists public.get_fasih_rekap_pengawas_petugas(text, text, integer, integer, text, text);
create function public.get_fasih_rekap_pengawas_petugas(
  p_survey_period_id text default null,
  p_search text default null,
  p_limit integer default 50,
  p_offset integer default 0,
  p_sort_by text default 'total_assignment',
  p_sort_dir text default 'desc'
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_ctx record;
begin
  select * into v_ctx from public._fasih_current_context();
  if v_ctx.petugas_id is null or v_ctx.role <> 'pengawas' or not v_ctx.is_active then
    return public._fasih_empty_payload('pengawas_petugas', p_limit, p_offset);
  end if;
  return public._fasih_rekap_build(
    'pengawas_petugas',
    v_ctx.petugas_id,
    null,
    p_survey_period_id,
    p_search,
    p_limit,
    p_offset,
    p_sort_by,
    p_sort_dir
  );
end;
$$;

drop function if exists public.get_fasih_rekap_pengawas_wilayah_petugas(text, text, text, integer, integer, text, text);
create function public.get_fasih_rekap_pengawas_wilayah_petugas(
  p_petugas_id text,
  p_survey_period_id text default null,
  p_search text default null,
  p_limit integer default 200,
  p_offset integer default 0,
  p_sort_by text default 'title',
  p_sort_dir text default 'asc'
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_ctx record;
  v_target_petugas uuid := nullif(trim(p_petugas_id), '')::uuid;
begin
  select * into v_ctx from public._fasih_current_context();
  if v_ctx.petugas_id is null or v_ctx.role <> 'pengawas' or not v_ctx.is_active then
    return public._fasih_empty_payload('wilayah_by_petugas', p_limit, p_offset);
  end if;
  if v_target_petugas is null or not exists (
    select 1
    from public.se2026_wilayah_tugas wt
    where wt.pml_id = v_ctx.petugas_id
      and wt.ppl_id = v_target_petugas
  ) then
    return public._fasih_empty_payload('wilayah_by_petugas', p_limit, p_offset);
  end if;
  return public._fasih_rekap_build(
    'wilayah_by_petugas',
    v_ctx.petugas_id,
    p_petugas_id,
    p_survey_period_id,
    p_search,
    p_limit,
    p_offset,
    p_sort_by,
    p_sort_dir
  );
end;
$$;

drop function if exists public.get_fasih_rekap_admin_pengawas(text, text, integer, integer, text, text);
create function public.get_fasih_rekap_admin_pengawas(
  p_survey_period_id text default null,
  p_search text default null,
  p_limit integer default 50,
  p_offset integer default 0,
  p_sort_by text default 'total_assignment',
  p_sort_dir text default 'desc'
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_ctx record;
begin
  select * into v_ctx from public._fasih_current_context();
  if v_ctx.petugas_id is null or v_ctx.role <> 'admin' or not v_ctx.is_active then
    return public._fasih_empty_payload('admin_pengawas', p_limit, p_offset);
  end if;
  return public._fasih_rekap_build(
    'admin_pengawas',
    v_ctx.petugas_id,
    null,
    p_survey_period_id,
    p_search,
    p_limit,
    p_offset,
    p_sort_by,
    p_sort_dir
  );
end;
$$;

drop function if exists public.get_fasih_rekap_admin_petugas_by_pengawas(text, text, text, integer, integer, text, text);
create function public.get_fasih_rekap_admin_petugas_by_pengawas(
  p_pengawas_id text,
  p_survey_period_id text default null,
  p_search text default null,
  p_limit integer default 100,
  p_offset integer default 0,
  p_sort_by text default 'total_assignment',
  p_sort_dir text default 'desc'
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_ctx record;
begin
  select * into v_ctx from public._fasih_current_context();
  if v_ctx.petugas_id is null or v_ctx.role <> 'admin' or not v_ctx.is_active then
    return public._fasih_empty_payload('petugas_by_pengawas', p_limit, p_offset);
  end if;
  return public._fasih_rekap_build(
    'petugas_by_pengawas',
    v_ctx.petugas_id,
    p_pengawas_id,
    p_survey_period_id,
    p_search,
    p_limit,
    p_offset,
    p_sort_by,
    p_sort_dir
  );
end;
$$;

drop function if exists public.get_fasih_rekap_admin_wilayah_by_petugas(text, text, text, integer, integer, text, text);
create function public.get_fasih_rekap_admin_wilayah_by_petugas(
  p_petugas_id text,
  p_survey_period_id text default null,
  p_search text default null,
  p_limit integer default 200,
  p_offset integer default 0,
  p_sort_by text default 'title',
  p_sort_dir text default 'asc'
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_ctx record;
begin
  select * into v_ctx from public._fasih_current_context();
  if v_ctx.petugas_id is null or v_ctx.role <> 'admin' or not v_ctx.is_active then
    return public._fasih_empty_payload('wilayah_by_petugas', p_limit, p_offset);
  end if;
  return public._fasih_rekap_build(
    'wilayah_by_petugas',
    v_ctx.petugas_id,
    p_petugas_id,
    p_survey_period_id,
    p_search,
    p_limit,
    p_offset,
    p_sort_by,
    p_sort_dir
  );
end;
$$;

grant execute on function public.get_fasih_rekap_pendata_wilayah(text, text, integer, integer, text, text) to authenticated;
grant execute on function public.get_fasih_rekap_pengawas_petugas(text, text, integer, integer, text, text) to authenticated;
grant execute on function public.get_fasih_rekap_pengawas_wilayah_petugas(text, text, text, integer, integer, text, text) to authenticated;
grant execute on function public.get_fasih_rekap_admin_pengawas(text, text, integer, integer, text, text) to authenticated;
grant execute on function public.get_fasih_rekap_admin_petugas_by_pengawas(text, text, text, integer, integer, text, text) to authenticated;
grant execute on function public.get_fasih_rekap_admin_wilayah_by_petugas(text, text, text, integer, integer, text, text) to authenticated;
