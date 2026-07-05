-- Step 1: Tambah kolom petugas_completed_at ke se2026_assignment_list
-- Kolom ini diisi saat sync: kapan petugas benar-benar menyelesaikan pekerjaan
-- (bukan kapan pengawas approve)
alter table public.se2026_assignment_list
  add column if not exists petugas_completed_at timestamptz,
  add column if not exists petugas_role_name text; -- Pencacah / Pendata

comment on column public.se2026_assignment_list.petugas_completed_at
  is 'Waktu petugas menyelesaikan (DRAFT aktif oleh pencacah atau SUBMITTED). Tidak berubah saat pengawas approve.';
comment on column public.se2026_assignment_list.petugas_role_name
  is 'Role petugas terakhir (Pencacah/Pendata) saat status diset oleh petugas';

-- Step 2: Backfill dari source_modified_at untuk record yang sudah SUBMITTED
-- (sudah selesai oleh petugas, tapi kita tidak punya waktu pasti)
update public.se2026_assignment_list
set
  petugas_completed_at = source_modified_at,
  petugas_role_name    = 'Pencacah'
where status_text in (
  'SUBMITTED BY Pencacah',
  'SUBMITTED',
  'APPROVED BY Pengawas',
  'REJECTED BY Pengawas',
  'REVOKED BY Pengawas',
  'EDITED BY Pengawas',
  'SUBMITTED RESPONDENT'
)
and source_modified_at is not null
and petugas_completed_at is null;

-- Step 3: Drop semua overload get_fasih_daily_contribution lama
drop function if exists public.get_fasih_daily_contribution(date, text, uuid, uuid, boolean);
drop function if exists public.get_fasih_daily_contribution(date, text, uuid, uuid, boolean, text);

-- Step 4: Buat ulang RPC dengan tabel yang benar
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
  v_auth_uid      uuid := auth.uid();
  v_user_id       uuid;
  v_petugas_id    uuid;
  v_role          text;
  v_is_active     boolean;
  v_yesterday     date := p_target_date - 1;
  v_level         text;
  v_progress_mode text := case
    when lower(coalesce(p_progress_mode, 'petugas')) = 'pengawas' then 'pengawas'
    else 'petugas'
  end;
  v_result        jsonb;
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
  -- Base: gabung assignment dengan wilayah scope
  assignment_base as (
    select
      al.assignment_id,
      al.survey_period_id,
      al.status_text                              as status_alias,
      al.kode_wilayah,
      al.source_modified_at,
      al.petugas_completed_at,
      sw.nm_sls,
      sw.pml_id,
      sw.pml_name                                 as pml_nama,
      sw.pml_username,
      sw.ppl_id,
      sw.ppl_name                                 as ppl_nama,
      sw.ppl_username
    from public.se2026_assignment_list al
    join public.vw_fasih_wilayah_scope_base sw
      on sw.kode_wilayah = al.kode_wilayah
    where (p_survey_period_id is null or al.survey_period_id = p_survey_period_id)
  ),
  -- Tentukan progress_at per mode
  base as (
    select
      *,
      case
        -- Mode pengawas: pakai source_modified_at (kapan pengawas aksi)
        when v_progress_mode = 'pengawas'
          then source_modified_at

        -- Mode petugas: prioritas petugas_completed_at (waktu petugas selesai)
        when petugas_completed_at is not null
          then petugas_completed_at

        -- DRAFT yang belum punya petugas_completed_at: petugas masih mengerjakan
        when coalesce(status_alias, '') = 'DRAFT'
          then source_modified_at

        else null
      end as progress_at
    from assignment_base
    where (
        v_progress_mode = 'pengawas'
        and status_alias in ('APPROVED BY Pengawas', 'REJECTED BY Pengawas')
      ) or (
        v_progress_mode <> 'pengawas'
        and coalesce(status_alias, '') not in ('OPEN', '')
      )
  ),
  -- Filter sesuai scope user
  scoped as (
    select *
    from base
    where progress_at is not null
      and (v_level <> 'pendata_wilayah'  or ppl_id = v_petugas_id)
      and (v_level not in ('pengawas_petugas','pengawas_wilayah')
           or pml_id = v_petugas_id)
      and (v_level <> 'admin_petugas'
           or p_pengawas_id is null
           or pml_id = p_pengawas_id)
      and (v_level not in ('pengawas_wilayah','admin_wilayah')
           or ppl_id = p_petugas_id)
  ),
  -- Kumulatif sampai hari ini
  today_grouped as (
    select
      case v_level
        when 'pendata_wilayah'  then kode_wilayah
        when 'pengawas_petugas' then ppl_id::text
        when 'pengawas_wilayah' then kode_wilayah
        when 'admin_pengawas'   then pml_id::text
        when 'admin_petugas'    then ppl_id::text
        when 'admin_wilayah'    then kode_wilayah
      end as unit_id,
      count(*)::int as today_count
    from scoped
    where progress_at::date <= p_target_date
    group by 1
  ),
  -- Delta hari ini (untuk status_counts badge)
  changed_today_grouped as (
    select
      case v_level
        when 'pendata_wilayah'  then kode_wilayah
        when 'pengawas_petugas' then ppl_id::text
        when 'pengawas_wilayah' then kode_wilayah
        when 'admin_pengawas'   then pml_id::text
        when 'admin_petugas'    then ppl_id::text
        when 'admin_wilayah'    then kode_wilayah
      end as unit_id,
      jsonb_object_agg(coalesce(status_alias,'UNKNOWN'), cnt) as status_counts_today
    from (
      select
        case v_level
          when 'pendata_wilayah'  then kode_wilayah
          when 'pengawas_petugas' then ppl_id::text
          when 'pengawas_wilayah' then kode_wilayah
          when 'admin_pengawas'   then pml_id::text
          when 'admin_petugas'    then ppl_id::text
          when 'admin_wilayah'    then kode_wilayah
        end as unit_id,
        coalesce(status_alias,'UNKNOWN') as status_alias,
        count(*)::int as cnt
      from scoped
      where progress_at::date = p_target_date
      group by 1, 2
    ) x
    group by unit_id
  ),
  -- Kumulatif sampai kemarin
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
      coalesce(m.subtitle, '')                                        as subtitle,
      coalesce(t.today_count, 0)                                      as today_count,
      coalesce(y.yesterday_count, 0)                                  as yesterday_count,
      (coalesce(t.today_count,0) - coalesce(y.yesterday_count,0))::int as delta,
      coalesce(ct.status_counts_today, '{}'::jsonb)                   as status_counts_today
    from unit_meta m
    left join today_grouped         t  on t.unit_id  = m.unit_id
    left join yesterday_grouped     y  on y.unit_id  = m.unit_id
    left join changed_today_grouped ct on ct.unit_id = m.unit_id
    order by coalesce(t.today_count, 0) desc, m.title asc
  ),
  summary as (
    select
      coalesce(sum(today_count),    0)::int as total_today,
      coalesce(sum(yesterday_count),0)::int as total_yesterday,
      coalesce(sum(delta),          0)::int as total_delta,
      count(*)::int                         as active_units
    from rows_final
  )
  select jsonb_build_object(
    'target_date',   p_target_date,
    'yesterday',     v_yesterday,
    'role',          v_role,
    'progress_mode', v_progress_mode,
    'summary',       (select to_jsonb(s) from summary s),
    'rows',          coalesce((select jsonb_agg(to_jsonb(r)) from rows_final r), '[]'::jsonb),
    'meta',          jsonb_build_object('level', v_level)
  )
  into v_result;

  return coalesce(v_result, _fasih_rekap_empty(20, 0, 'daily'));
end;
$$;

grant execute on function public.get_fasih_daily_contribution(date, text, uuid, uuid, boolean, text) to authenticated;
