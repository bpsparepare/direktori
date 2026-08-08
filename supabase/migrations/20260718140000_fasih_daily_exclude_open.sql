-- get_fasih_daily_contribution versi baru: progress harian dihitung dari SELISIH
-- antar snapshot se2026_rekap_sls_harian (bukan lagi petugas_completed_at).
--
--   today_count      = "terkirim" kumulatif pada snapshot <= target
--   yesterday_count  = "terkirim" kumulatif pada snapshot <= (target-1)
--   delta            = today_count - yesterday_count (progress hari itu)
--   status_counts_today = pecahan kenaikan per status antar kedua snapshot
--
-- REVISI: "terkirim" = Σ status bernama tanpa DRAFT (dan tanpa OPEN, karena
-- OPEN tak punya kolom). Sebelumnya pakai `total - draft` yang keliru memuat
-- OPEN. Kontrak JSON & unit_id per level identik → merge dgn get_fasih_rekap
-- tetap benar. p_progress_mode dipertahankan tapi tidak dipakai.

drop function if exists public.get_fasih_daily_contribution(date, text, uuid, uuid, boolean, text);
create function public.get_fasih_daily_contribution(
  p_target_date      date    default current_date,
  p_survey_period_id text    default null,
  p_pengawas_id      uuid    default null,
  p_petugas_id       uuid    default null,
  p_all_petugas      boolean default false,
  p_progress_mode    text    default 'petugas'
)
returns jsonb
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
  v_is_active  boolean;
  v_yesterday  date := p_target_date - 1;
  v_level      text;
  v_snap_today date;
  v_snap_yest  date;
  v_result     jsonb;
begin
  if v_auth_uid is null then return jsonb_build_object(
    'target_date', p_target_date,
    'yesterday',   v_yesterday,
    'role',        coalesce(v_role, ''),
    'summary',     jsonb_build_object('total_today', 0, 'total_yesterday', 0,
                                      'total_delta', 0, 'active_units', 0),
    'rows',        '[]'::jsonb,
    'meta',        jsonb_build_object('level', coalesce(v_level, ''))
  ); end if;

  select u.id into v_user_id
  from public.users u where u.auth_uid = v_auth_uid limit 1;
  if v_user_id is null then return jsonb_build_object(
    'target_date', p_target_date,
    'yesterday',   v_yesterday,
    'role',        coalesce(v_role, ''),
    'summary',     jsonb_build_object('total_today', 0, 'total_yesterday', 0,
                                      'total_delta', 0, 'active_units', 0),
    'rows',        '[]'::jsonb,
    'meta',        jsonb_build_object('level', coalesce(v_level, ''))
  ); end if;

  select p.id, p.role, coalesce(p.is_active, false)
    into v_petugas_id, v_role, v_is_active
  from public.se2026_petugas p
  where p.user_id = v_user_id
  order by p.created_at desc nulls last limit 1;

  if v_petugas_id is null or not v_is_active then
    return jsonb_build_object(
    'target_date', p_target_date,
    'yesterday',   v_yesterday,
    'role',        coalesce(v_role, ''),
    'summary',     jsonb_build_object('total_today', 0, 'total_yesterday', 0,
                                      'total_delta', 0, 'active_units', 0),
    'rows',        '[]'::jsonb,
    'meta',        jsonb_build_object('level', coalesce(v_level, ''))
  );
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

  -- Snapshot terdekat <= target dan <= kemarin.
  select max(snapshot_date) into v_snap_today
  from public.se2026_rekap_sls_harian where snapshot_date <= p_target_date;
  select max(snapshot_date) into v_snap_yest
  from public.se2026_rekap_sls_harian where snapshot_date <= v_yesterday;
  -- Tanpa snapshot pembanding (mis. impor pertama), jangan tampilkan lonjakan
  -- palsu: pakai snapshot hari ini sebagai baseline → delta 0.
  if v_snap_yest is null then v_snap_yest := v_snap_today; end if;

  with
  scope_base as (
    select
      sw.kode_wilayah,
      sw.nm_sls, sw.nm_kec, sw.nm_desa,
      sw.pml_id, sw.pml_name, sw.pml_username,
      sw.ppl_id, sw.ppl_name, sw.ppl_username,
      -- "Terkirim" = status bernama tanpa OPEN & DRAFT (OPEN tak punya kolom).
      (coalesce(rt.approved_pengawas,0) + coalesce(rt.submitted_pencacah,0)
       + coalesce(rt.submitted_respondent,0) + coalesce(rt.rejected_pengawas,0)
       + coalesce(rt.edited_admin_kab,0) + coalesce(rt.rejected_admin_kab,0)
       + coalesce(rt.revoked_pengawas,0)) as terk_today,
      (coalesce(ry.approved_pengawas,0) + coalesce(ry.submitted_pencacah,0)
       + coalesce(ry.submitted_respondent,0) + coalesce(ry.rejected_pengawas,0)
       + coalesce(ry.edited_admin_kab,0) + coalesce(ry.rejected_admin_kab,0)
       + coalesce(ry.revoked_pengawas,0)) as terk_yest,
      coalesce(rt.approved_pengawas,0)    - coalesce(ry.approved_pengawas,0)    as d_approved_pengawas,
      coalesce(rt.submitted_pencacah,0)   - coalesce(ry.submitted_pencacah,0)   as d_submitted_pencacah,
      coalesce(rt.submitted_respondent,0) - coalesce(ry.submitted_respondent,0) as d_submitted_respondent,
      coalesce(rt.rejected_pengawas,0)    - coalesce(ry.rejected_pengawas,0)    as d_rejected_pengawas,
      coalesce(rt.revoked_pengawas,0)     - coalesce(ry.revoked_pengawas,0)     as d_revoked_pengawas,
      coalesce(rt.edited_admin_kab,0)     - coalesce(ry.edited_admin_kab,0)     as d_edited_admin_kab,
      coalesce(rt.rejected_admin_kab,0)   - coalesce(ry.rejected_admin_kab,0)   as d_rejected_admin_kab
    from public.vw_fasih_wilayah_scope_base sw
    left join public.se2026_rekap_sls_harian rt
      on rt.level_6_full_code = sw.kode_wilayah and rt.snapshot_date = v_snap_today
    left join public.se2026_rekap_sls_harian ry
      on ry.level_6_full_code = sw.kode_wilayah and ry.snapshot_date = v_snap_yest
  ),
  scoped as (
    select *
    from scope_base
    where (v_level <> 'pendata_wilayah'  or ppl_id = v_petugas_id)
      and (v_level not in ('pengawas_petugas','pengawas_wilayah')
           or pml_id = v_petugas_id)
      and (v_level <> 'admin_petugas'
           or p_pengawas_id is null
           or pml_id = p_pengawas_id)
      and (v_level not in ('pengawas_wilayah','admin_wilayah')
           or ppl_id = p_petugas_id)
  ),
  normalized as (
    select
      case v_level
        when 'pendata_wilayah'  then kode_wilayah
        when 'pengawas_petugas' then ppl_id::text
        when 'pengawas_wilayah' then kode_wilayah
        when 'admin_pengawas'   then pml_id::text
        when 'admin_petugas'    then ppl_id::text
        when 'admin_wilayah'    then kode_wilayah
      end as unit_id,
      case v_level
        when 'pengawas_petugas' then ppl_name
        when 'admin_petugas'    then ppl_name
        when 'admin_pengawas'   then pml_name
        else coalesce(nullif(trim(nm_sls), ''), kode_wilayah)
      end as title,
      case v_level
        when 'pengawas_petugas' then coalesce(ppl_username, '-')
        when 'admin_petugas'    then coalesce(ppl_username, '-')
        when 'admin_pengawas'   then coalesce(pml_username, '-')
        else concat_ws(' / ', nullif(trim(nm_kec), ''), nullif(trim(nm_desa), ''))
      end as subtitle,
      terk_today, terk_yest,
      d_approved_pengawas, d_submitted_pencacah, d_submitted_respondent,
      d_rejected_pengawas, d_revoked_pengawas, d_edited_admin_kab, d_rejected_admin_kab
    from scoped
  ),
  rows_agg as (
    select
      unit_id,
      min(title)    as title,
      min(subtitle) as subtitle,
      sum(terk_today)::int as today_count,
      sum(terk_yest)::int  as yesterday_count,
      (sum(terk_today) - sum(terk_yest))::int as delta
    from normalized
    where unit_id is not null and unit_id <> ''
    group by unit_id
  ),
  status_today_long as (
    select n.unit_id, s.label, s.d
    from normalized n
    cross join lateral (values
      ('APPROVED Pengawas',    n.d_approved_pengawas),
      ('SUBMITTED Pencacah',   n.d_submitted_pencacah),
      ('SUBMITTED Respondent', n.d_submitted_respondent),
      ('REJECTED Pengawas',    n.d_rejected_pengawas),
      ('REVOKED Pengawas',     n.d_revoked_pengawas),
      ('EDITED Admin Kab',     n.d_edited_admin_kab),
      ('REJECTED Admin Kab',   n.d_rejected_admin_kab)
    ) as s(label, d)
    where n.unit_id is not null and n.unit_id <> ''
  ),
  status_counts_today as (
    select unit_id, jsonb_object_agg(label, total order by label) as status_counts_today
    from (
      select unit_id, label, sum(d)::int as total
      from status_today_long
      group by unit_id, label
    ) x
    where total > 0
    group by unit_id
  ),
  rows_final as (
    select
      r.unit_id,
      r.title,
      coalesce(r.subtitle, '') as subtitle,
      r.today_count,
      r.yesterday_count,
      r.delta,
      coalesce(sc.status_counts_today, '{}'::jsonb) as status_counts_today
    from rows_agg r
    left join status_counts_today sc on sc.unit_id = r.unit_id
    order by r.delta desc, r.title asc
  ),
  summary as (
    select
      coalesce(sum(today_count),    0)::int as total_today,
      coalesce(sum(yesterday_count),0)::int as total_yesterday,
      coalesce(sum(delta),          0)::int as total_delta,
      count(*) filter (where delta > 0)::int as active_units
    from rows_final
  )
  select jsonb_build_object(
    'target_date',   p_target_date,
    'yesterday',     v_yesterday,
    'role',          v_role,
    'progress_mode', lower(coalesce(p_progress_mode, 'petugas')),
    'summary',       (select to_jsonb(s) from summary s),
    'rows',          coalesce((select jsonb_agg(to_jsonb(r)) from rows_final r), '[]'::jsonb),
    'meta',          jsonb_build_object('level', v_level, 'snapshot_date', v_snap_today)
  )
  into v_result;

  return coalesce(v_result, jsonb_build_object(
    'target_date', p_target_date,
    'yesterday',   v_yesterday,
    'role',        coalesce(v_role, ''),
    'summary',     jsonb_build_object('total_today', 0, 'total_yesterday', 0,
                                      'total_delta', 0, 'active_units', 0),
    'rows',        '[]'::jsonb,
    'meta',        jsonb_build_object('level', coalesce(v_level, ''))
  ));
end;
$$;

grant execute on function public.get_fasih_daily_contribution(date, text, uuid, uuid, boolean, text) to authenticated;
