create or replace view public.vw_fasih_assignment_user_base as
select
  mv.id,
  mv.survey_period_id,
  mv.assignment_id,
  mv.status_alias,
  mv.kode_wilayah,
  mv.kecamatan,
  mv.desa,
  nullif(trim(fa.payload_json ->> 'currentUserId'), '') as assignment_user_id,
  coalesce(
    nullif(trim(fa.payload_json ->> 'currentUserFullname'), ''),
    nullif(trim(fa.payload_json ->> 'currentUserUsername'), ''),
    'Tanpa Nama'
  ) as assignment_user_name,
  nullif(trim(fa.payload_json ->> 'currentUserUsername'), '') as assignment_username,
  case lower(coalesce(fa.payload_json ->> 'currentUserSurveyRoleName', ''))
    when 'pencacah' then 'pendata'
    when 'pengawas' then 'pengawas'
    when 'admin' then 'admin'
    else lower(nullif(trim(fa.payload_json ->> 'currentUserSurveyRoleName'), ''))
  end as assignment_role
from public.mv_fasih_assignment_summary mv
join public.fasih_assignments fa
  on fa.assignment_id = mv.assignment_id
where nullif(trim(fa.payload_json ->> 'currentUserId'), '') is not null;

drop function if exists public.get_fasih_rekap_per_user(
  uuid,
  text,
  integer,
  integer,
  text,
  text
);

drop function if exists public.get_fasih_rekap_per_user(
  text,
  text,
  integer,
  integer,
  text,
  text
);

create function public.get_fasih_rekap_per_user(
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
  v_auth_uid uuid := auth.uid();
  v_user_id uuid;
  v_petugas_id uuid;
  v_role text;
  v_is_active boolean := false;
  v_limit integer := greatest(1, least(coalesce(p_limit, 20), 200));
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_sort_by text;
  v_sort_dir text;
  v_query text;
  v_result jsonb;
begin
  if v_auth_uid is null then
    return jsonb_build_object(
      'summary', jsonb_build_object(
        'total_users', 0,
        'total_assignments', 0,
        'total_open', 0,
        'total_draft', 0,
        'total_approved', 0,
        'total_rejected', 0
      ),
      'chart', '[]'::jsonb,
      'rows', '[]'::jsonb,
      'periods', '[]'::jsonb,
      'meta', jsonb_build_object(
        'limit', v_limit,
        'offset', v_offset,
        'returned_rows', 0
      )
    );
  end if;

  select u.id
    into v_user_id
  from public.users u
  where u.auth_uid = v_auth_uid
  limit 1;

  if v_user_id is null then
    return jsonb_build_object(
      'summary', jsonb_build_object(
        'total_users', 0,
        'total_assignments', 0,
        'total_open', 0,
        'total_draft', 0,
        'total_approved', 0,
        'total_rejected', 0
      ),
      'chart', '[]'::jsonb,
      'rows', '[]'::jsonb,
      'periods', '[]'::jsonb,
      'meta', jsonb_build_object(
        'limit', v_limit,
        'offset', v_offset,
        'returned_rows', 0
      )
    );
  end if;

  select p.id, p.role, coalesce(p.is_active, false)
    into v_petugas_id, v_role, v_is_active
  from public.se2026_petugas p
  where p.user_id = v_user_id
  order by p.created_at desc nulls last
  limit 1;

  if v_petugas_id is null or not v_is_active or v_role not in ('admin', 'pengawas', 'pendata') then
    return jsonb_build_object(
      'summary', jsonb_build_object(
        'total_users', 0,
        'total_assignments', 0,
        'total_open', 0,
        'total_draft', 0,
        'total_approved', 0,
        'total_rejected', 0
      ),
      'chart', '[]'::jsonb,
      'rows', '[]'::jsonb,
      'periods', '[]'::jsonb,
      'meta', jsonb_build_object(
        'limit', v_limit,
        'offset', v_offset,
        'returned_rows', 0
      )
    );
  end if;

  v_sort_by := case lower(coalesce(p_sort_by, ''))
    when 'user_name' then 'user_name'
    when 'username' then 'username'
    when 'role' then 'role'
    when 'wilayah_label' then 'wilayah_label'
    when 'open_count' then 'open_count'
    when 'draft_count' then 'draft_count'
    when 'approved_count' then 'approved_count'
    when 'rejected_count' then 'rejected_count'
    else 'total_assignment'
  end;

  v_sort_dir := case lower(coalesce(p_sort_dir, ''))
    when 'asc' then 'asc'
    else 'desc'
  end;

  v_query := format(
    $sql$
    with role_scope as (
      select b.*
      from public.vw_fasih_assignment_user_base b
      where %1$L = 'admin'
         or exists (
           select 1
           from public.se2026_wilayah_tugas wt
           where wt.id = b.kode_wilayah
             and (
               (%1$L = 'pengawas' and wt.pml_id = %2$L::uuid)
               or (%1$L = 'pendata' and wt.ppl_id = %2$L::uuid)
             )
         )
    ),
    filtered as (
      select *
      from role_scope
      where (%3$L is null or survey_period_id = %3$L)
        and (
          %4$L = ''
          or assignment_user_name ilike '%%' || %4$L || '%%'
          or coalesce(assignment_username, '') ilike '%%' || %4$L || '%%'
        )
    ),
    rows_agg as (
      select
        assignment_user_id as user_id,
        min(assignment_user_name) as user_name,
        min(coalesce(assignment_username, '')) as username,
        min(coalesce(assignment_role, '-')) as role,
        case
          when count(distinct nullif(trim(kecamatan), '')) = 0 then '-'
          when count(distinct nullif(trim(kecamatan), '')) = 1 then coalesce(min(nullif(trim(kecamatan), '')), '-')
          else count(distinct nullif(trim(kecamatan), ''))::text || ' kecamatan'
        end as wilayah_label,
        count(*)::int as total_assignment,
        count(*) filter (where coalesce(status_alias, '') = 'OPEN')::int as open_count,
        count(*) filter (where coalesce(status_alias, '') = 'DRAFT')::int as draft_count,
        count(*) filter (where coalesce(status_alias, '') = 'APPROVED')::int as approved_count,
        count(*) filter (where coalesce(status_alias, '') = 'REJECTED')::int as rejected_count
      from filtered
      group by assignment_user_id
    ),
    scope_periods as (
      select distinct rs.survey_period_id
      from role_scope rs
    ),
    periods as (
      select
        spc.survey_period_id as survey_period_id,
        trim(coalesce(sp.name, spc.survey_period_id)) as name,
        coalesce(sp.is_active, false) as is_active,
        sp.start_date,
        sp.end_date
      from scope_periods spc
      left join public.monev_fasih_survey_period sp
        on sp.survey_period_id::text = spc.survey_period_id
      order by sp.is_active desc, sp.start_date desc nulls last, name asc
    ),
    summary as (
      select
        count(*)::int as total_users,
        coalesce(sum(total_assignment), 0)::int as total_assignments,
        coalesce(sum(open_count), 0)::int as total_open,
        coalesce(sum(draft_count), 0)::int as total_draft,
        coalesce(sum(approved_count), 0)::int as total_approved,
        coalesce(sum(rejected_count), 0)::int as total_rejected
      from rows_agg
    ),
    chart as (
      select
        user_id,
        user_name as label,
        total_assignment
      from rows_agg
      order by total_assignment desc, user_name asc
      limit 8
    ),
    paged as (
      select *
      from rows_agg
      order by %5$I %6$s, user_name asc
      limit %7$s
      offset %8$s
    )
    select jsonb_build_object(
      'summary',
      coalesce((select to_jsonb(summary) from summary), '{}'::jsonb),
      'chart',
      coalesce((select jsonb_agg(to_jsonb(chart)) from chart), '[]'::jsonb),
      'rows',
      coalesce((select jsonb_agg(to_jsonb(paged)) from paged), '[]'::jsonb),
      'periods',
      coalesce((select jsonb_agg(to_jsonb(periods)) from periods), '[]'::jsonb),
      'meta',
      jsonb_build_object(
        'limit', %7$s,
        'offset', %8$s,
        'returned_rows', coalesce((select count(*) from paged), 0),
        'scope_role', %1$L,
        'sort_by', %5$L,
        'sort_dir', %6$L
      )
    );
    $sql$,
    v_role,
    v_petugas_id,
    p_survey_period_id,
    coalesce(trim(p_search), ''),
    v_sort_by,
    v_sort_dir,
    v_limit,
    v_offset
  );

  execute v_query into v_result;

  return coalesce(
    v_result,
    jsonb_build_object(
      'summary', jsonb_build_object(
        'total_users', 0,
        'total_assignments', 0,
        'total_open', 0,
        'total_draft', 0,
        'total_approved', 0,
        'total_rejected', 0
      ),
      'chart', '[]'::jsonb,
      'rows', '[]'::jsonb,
      'periods', '[]'::jsonb,
      'meta', jsonb_build_object(
        'limit', v_limit,
        'offset', v_offset,
        'returned_rows', 0
      )
    )
  );
end;
$$;

grant execute on function public.get_fasih_rekap_per_user(text, text, integer, integer, text, text) to authenticated;
