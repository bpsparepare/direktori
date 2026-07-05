alter table public.se2026_keterangan_umum
add column if not exists waktu_selesai timestamp with time zone null;

create index if not exists idx_se2026_ku_waktu_selesai
on public.se2026_keterangan_umum using btree (waktu_selesai);

drop function if exists public.get_fasih_daily_contribution(date, text, uuid, uuid, boolean);
drop function if exists public.get_fasih_daily_contribution(date, text, uuid, uuid, boolean, text);

create or replace function public.get_fasih_daily_contribution(
  p_target_date      date    default current_date,
  p_survey_period_id text    default null,
  p_pengawas_id      uuid    default null,
  p_petugas_id       uuid    default null,
  p_all_petugas      boolean default false,
  p_progress_mode    text    default 'petugas'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_auth_uid   uuid := auth.uid();
  v_user_id    uuid;
  v_petugas_id uuid;
  v_role       text;
  v_is_active  boolean;
  v_yesterday  date := p_target_date - 1;
  v_level      text;
  v_progress_mode text := case
    when lower(coalesce(p_progress_mode, 'petugas')) = 'pengawas' then 'pengawas'
    else 'petugas'
  end;
  v_result     jsonb;
begin
  if v_auth_uid is null then return _fasih_rekap_empty(20, 0, 'daily'); end if;

  select u.id into v_user_id
  from public.users u where u.auth_uid = v_auth_uid limit 1;
  if v_user_id is null then return _fasih_rekap_empty(20, 0, 'daily'); end if;

  select p.id, p.role, coalesce(p.is_active, false)
    into v_petugas_id, v_role, v_is_active
  from public.se2026_petugas p
  where p.user_id = v_user_id
  order by p.created_at desc nulls last limit 1;

  if v_petugas_id is null or not v_is_active then
    return _fasih_rekap_empty(20, 0, 'daily');
  end if;

  if v_role = 'pengawas' then p_pengawas_id := null; end if;
  if v_role = 'pendata'  then p_pengawas_id := null; p_petugas_id := null; end if;

  v_level := case
    when v_role = 'pendata'                                then 'pendata_wilayah'
    when v_role = 'pengawas' and p_petugas_id is not null  then 'pengawas_wilayah'
    when v_role = 'pengawas'                               then 'pengawas_petugas'
    when v_role = 'admin'    and p_petugas_id is not null  then 'admin_wilayah'
    when v_role = 'admin'    and p_pengawas_id is not null then 'admin_petugas'
    when v_role = 'admin'    and p_all_petugas             then 'admin_petugas'
    when v_role = 'admin'                                  then 'admin_pengawas'
    else 'unknown'
  end;

  with
  assignment_base as (
    select
      mv.assignment_id,
      mv.survey_period_id,
      mv.status_alias,
      mv.kode_wilayah,
      mv.source_modified_at,
      sw.nm_sls,
      sw.pml_id,
      sw.pml_name as pml_nama,
      sw.pml_username,
      sw.ppl_id,
      sw.ppl_name as ppl_nama,
      sw.ppl_username,
      nullif(trim(ku.current_user_role), '') as current_role_name,
      ku.waktu_selesai as waktu_selesai_at
    from public.mv_fasih_assignment_summary mv
    join public.vw_fasih_wilayah_scope_base sw
      on sw.kode_wilayah = mv.kode_wilayah
    left join public.se2026_keterangan_umum ku
      on ku.assignment_id = mv.assignment_id
    where (p_survey_period_id is null or mv.survey_period_id = p_survey_period_id)
  ),
  base as (
    select
      *,
      case
        when v_progress_mode = 'pengawas' then source_modified_at
        when waktu_selesai_at is not null then waktu_selesai_at
        when coalesce(status_alias, '') = 'DRAFT'
          and lower(coalesce(current_role_name, '')) in ('pencacah', 'pendata')
          then source_modified_at
        when coalesce(status_alias, '') in ('SUBMITTED BY Pencacah', 'SUBMITTED BY Pendata', 'SUBMITTED')
          then source_modified_at
        else null
      end as progress_at
    from assignment_base
    where (
        v_progress_mode = 'pengawas'
        and status_alias in ('APPROVED BY Pengawas','REJECTED BY Pengawas')
      ) or (
        v_progress_mode <> 'pengawas'
        and coalesce(status_alias, '') <> 'OPEN'
      )
  ),
  scoped as (
    select *
    from base
    where progress_at is not null
      and (not (v_level = 'pendata_wilayah')
           or ppl_id = v_petugas_id)
      and (not (v_level in ('pengawas_petugas','pengawas_wilayah'))
           or pml_id = v_petugas_id)
      and (not (v_level = 'admin_petugas')
           or p_pengawas_id is null
           or pml_id = p_pengawas_id)
      and (not (v_level in ('pengawas_wilayah','admin_wilayah'))
           or ppl_id = p_petugas_id)
  ),
  today_by_alias as (
    select
      case v_level
        when 'pendata_wilayah'  then kode_wilayah
        when 'pengawas_petugas' then ppl_id::text
        when 'pengawas_wilayah' then kode_wilayah
        when 'admin_pengawas'   then pml_id::text
        when 'admin_petugas'    then ppl_id::text
        when 'admin_wilayah'    then kode_wilayah
      end as unit_id,
      coalesce(status_alias, 'UNKNOWN') as status_alias,
      count(*)::int as cnt
    from scoped
    where progress_at::date <= p_target_date
    group by 1, 2
  ),
  today_grouped as (
    select
      unit_id,
      sum(cnt)::int as today_count
    from today_by_alias
    group by unit_id
  ),
  changed_today_by_alias as (
    select
      case v_level
        when 'pendata_wilayah'  then kode_wilayah
        when 'pengawas_petugas' then ppl_id::text
        when 'pengawas_wilayah' then kode_wilayah
        when 'admin_pengawas'   then pml_id::text
        when 'admin_petugas'    then ppl_id::text
        when 'admin_wilayah'    then kode_wilayah
      end as unit_id,
      coalesce(status_alias, 'UNKNOWN') as status_alias,
      count(*)::int as cnt
    from scoped
    where progress_at::date = p_target_date
    group by 1, 2
  ),
  changed_today_grouped as (
    select
      unit_id,
      jsonb_object_agg(status_alias, cnt) as status_counts_today
    from changed_today_by_alias
    group by unit_id
  ),
  yesterday_grouped as (
    select
      case v_level
        when 'pendata_wilayah'  then kode_wilayah
        when 'pengawas_petugas' then ppl_id::text
        when 'pengawas_wilayah' then kode_wilayah
        when 'admin_pengawas'   then pml_id::text
        when 'admin_petugas'    then ppl_id::text
        when 'admin_wilayah'    then kode_wilayah
      end as unit_id,
      count(*)::int as yesterday_count
    from scoped
    where progress_at::date <= v_yesterday
    group by 1
  ),
  unit_meta as (
    select
      case v_level
        when 'pendata_wilayah'  then kode_wilayah
        when 'pengawas_petugas' then ppl_id::text
        when 'pengawas_wilayah' then kode_wilayah
        when 'admin_pengawas'   then pml_id::text
        when 'admin_petugas'    then ppl_id::text
        when 'admin_wilayah'    then kode_wilayah
      end as unit_id,
      min(case v_level
        when 'pendata_wilayah'  then coalesce(nm_sls, kode_wilayah)
        when 'pengawas_petugas' then ppl_nama
        when 'pengawas_wilayah' then coalesce(nm_sls, kode_wilayah)
        when 'admin_pengawas'   then pml_nama
        when 'admin_petugas'    then ppl_nama
        when 'admin_wilayah'    then coalesce(nm_sls, kode_wilayah)
      end) as title,
      min(case v_level
        when 'pengawas_petugas' then ppl_username
        when 'admin_petugas'    then ppl_username
        when 'admin_pengawas'   then pml_username
        else null
      end) as subtitle
    from scoped
    where progress_at::date <= p_target_date
    group by 1
  ),
  rows_final as (
    select
      m.unit_id,
      m.title,
      coalesce(m.subtitle, '')                               as subtitle,
      coalesce(t.today_count, 0)                             as today_count,
      coalesce(y.yesterday_count, 0)                         as yesterday_count,
      (coalesce(t.today_count,0) - coalesce(y.yesterday_count,0))::int as delta,
      coalesce(ct.status_counts_today, '{}'::jsonb)          as status_counts_today
    from unit_meta m
    left join today_grouped         t on t.unit_id = m.unit_id
    left join yesterday_grouped     y on y.unit_id = m.unit_id
    left join changed_today_grouped ct on ct.unit_id = m.unit_id
    order by coalesce(t.today_count, 0) desc, m.title asc
  ),
  summary as (
    select
      coalesce(sum(today_count),0)::int     as total_today,
      coalesce(sum(yesterday_count),0)::int as total_yesterday,
      coalesce(sum(delta),0)::int           as total_delta,
      count(*)::int                         as active_units
    from rows_final
  )
  select jsonb_build_object(
    'target_date',     p_target_date,
    'yesterday',       v_yesterday,
    'role',            v_role,
    'progress_mode',   v_progress_mode,
    'summary',         (select to_jsonb(s) from summary s),
    'rows',            coalesce((select jsonb_agg(to_jsonb(r)) from rows_final r), '[]'::jsonb),
    'meta',            jsonb_build_object('level', v_level)
  )
  into v_result;

  return coalesce(v_result, _fasih_rekap_empty(20, 0, 'daily'));
end;
$$;

grant execute on function public.get_fasih_daily_contribution(date, text, uuid, uuid, boolean, text) to authenticated;
