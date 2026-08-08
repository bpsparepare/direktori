-- get_fasih_rekap versi baru: sumber = se2026_rekap_sls_harian (rekap agregat
-- per-SLS hasil impor SQLLab) + join se2026_wilayah_tugas (via
-- vw_fasih_wilayah_scope_base) untuk hierarki pengawas/petugas & scope.
--
-- Kontrak JSON & unit_id per level IDENTIK dengan versi lama, sehingga Flutter
-- dan merge dengan get_fasih_daily_contribution tetap jalan.
--
-- REVISI: status OPEN DIKECUALIKAN. Kolom `total` (COUNT assignment) memuat
-- OPEN, sedangkan OPEN tak punya kolom sendiri di rekap. Karena itu angka
-- dihitung dari PENJUMLAHAN kolom status bernama (otomatis tanpa OPEN):
--   total_assignment (Total Kumulatif) = Σ status bernama (termasuk DRAFT)
--   total_terkirim   (Terkirim/final)  = Σ status bernama tanpa DRAFT
--   status_counts                      = pecahan per status (tanpa OPEN)
-- Kumulatif memakai snapshot_date TERBARU yang tersedia.

drop function if exists public.get_fasih_rekap(text, text, boolean, text, text, integer, integer, text, text);
create function public.get_fasih_rekap(
  p_pengawas_id      text    default null,
  p_petugas_id       text    default null,
  p_all_petugas      boolean default false,
  p_survey_period_id text    default null,
  p_search           text    default null,
  p_limit            integer default 200,
  p_offset           integer default 0,
  p_sort_by          text    default null,
  p_sort_dir         text    default null
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
  v_level      text;
  v_pengawas   uuid := nullif(trim(p_pengawas_id), '')::uuid;
  v_petugas    uuid := nullif(trim(p_petugas_id), '')::uuid;
  v_limit      integer := greatest(1, least(coalesce(p_limit, 200), 500));
  v_offset     integer := greatest(coalesce(p_offset, 0), 0);
  v_sort_by    text;
  v_sort_dir   text;
  v_snap       date;
  v_result     jsonb;
begin
  if v_auth_uid is null then
    return public._fasih_empty_payload('pengawas_petugas', v_limit, v_offset);
  end if;

  select u.id into v_user_id
  from public.users u
  where u.auth_uid = v_auth_uid
  limit 1;
  if v_user_id is null then
    return public._fasih_empty_payload('pengawas_petugas', v_limit, v_offset);
  end if;

  select p.id, p.role, coalesce(p.is_active, false)
    into v_petugas_id, v_role, v_is_active
  from public.se2026_petugas p
  where p.user_id = v_user_id
  order by p.created_at desc nulls last
  limit 1;

  if v_petugas_id is null or not v_is_active then
    return public._fasih_empty_payload('pengawas_petugas', v_limit, v_offset);
  end if;

  if v_role = 'pengawas' then v_pengawas := null; end if;
  if v_role = 'pendata'  then v_pengawas := null; v_petugas := null; end if;

  v_level := case
    when v_role = 'pendata'                              then 'pendata_wilayah'
    when v_role = 'pengawas' and v_petugas is not null   then 'pengawas_wilayah'
    when v_role = 'pengawas'                             then 'pengawas_petugas'
    when v_role = 'admin'    and v_petugas is not null   then 'admin_wilayah'
    when v_role = 'admin'    and v_pengawas is not null  then 'admin_petugas'
    when v_role = 'admin'    and p_all_petugas           then 'admin_petugas'
    when v_role = 'admin'                                then 'admin_pengawas'
    else 'unknown'
  end;

  if v_level = 'unknown' then
    return public._fasih_empty_payload('pengawas_petugas', v_limit, v_offset);
  end if;

  v_sort_by := case lower(coalesce(p_sort_by, ''))
    when 'title' then 'title'
    when 'subtitle' then 'subtitle'
    when 'total_assignment' then 'total_assignment'
    else case
      when v_level in ('pendata_wilayah', 'pengawas_wilayah', 'admin_wilayah') then 'title'
      else 'total_assignment'
    end
  end;
  v_sort_dir := case lower(coalesce(p_sort_dir, ''))
    when 'asc' then 'asc'
    when 'desc' then 'desc'
    else case when v_sort_by = 'title' then 'asc' else 'desc' end
  end;

  -- Snapshot terbaru = kondisi kumulatif terkini.
  select max(snapshot_date) into v_snap from public.se2026_rekap_sls_harian;

  with
  -- Per SLS: wilayah scope (semua SLS wilayah tugas) LEFT JOIN rekap snapshot.
  -- SLS tanpa data rekap → 0 (tetap tampil).
  scope_base as (
    select
      sw.kode_wilayah,
      sw.nm_sls, sw.nm_kec, sw.nm_desa,
      sw.pml_id, sw.pml_name, sw.pml_username,
      sw.ppl_id, sw.ppl_name, sw.ppl_username,
      -- Total kumulatif TANPA OPEN. Kolom `total` (COUNT) memuat OPEN, sedangkan
      -- OPEN tak punya kolom sendiri → jumlahkan status bernama saja.
      (coalesce(r.approved_pengawas,0) + coalesce(r.submitted_pencacah,0)
       + coalesce(r.submitted_respondent,0) + coalesce(r.draft_awal,0)
       + coalesce(r.draft_revisi,0) + coalesce(r.rejected_pengawas,0)
       + coalesce(r.edited_admin_kab,0) + coalesce(r.rejected_admin_kab,0)
       + coalesce(r.revoked_pengawas,0))                                  as m_total,
      -- Terkirim (final) = tanpa OPEN & tanpa DRAFT.
      (coalesce(r.approved_pengawas,0) + coalesce(r.submitted_pencacah,0)
       + coalesce(r.submitted_respondent,0) + coalesce(r.rejected_pengawas,0)
       + coalesce(r.edited_admin_kab,0) + coalesce(r.rejected_admin_kab,0)
       + coalesce(r.revoked_pengawas,0))                                  as m_terkirim,
      coalesce(r.approved_pengawas,0)    as approved_pengawas,
      coalesce(r.submitted_pencacah,0)   as submitted_pencacah,
      coalesce(r.submitted_respondent,0) as submitted_respondent,
      coalesce(r.draft_awal,0)           as draft_awal,
      coalesce(r.draft_revisi,0)         as draft_revisi,
      coalesce(r.rejected_pengawas,0)    as rejected_pengawas,
      coalesce(r.revoked_pengawas,0)     as revoked_pengawas,
      coalesce(r.edited_admin_kab,0)     as edited_admin_kab,
      coalesce(r.rejected_admin_kab,0)   as rejected_admin_kab
    from public.vw_fasih_wilayah_scope_base sw
    left join public.se2026_rekap_sls_harian r
      on r.level_6_full_code = sw.kode_wilayah
     and r.snapshot_date = v_snap
  ),
  scoped as (
    select *
    from scope_base
    where (v_level <> 'pendata_wilayah'  or ppl_id = v_petugas_id)
      and (v_level not in ('pengawas_petugas','pengawas_wilayah')
           or pml_id = v_petugas_id)
      and (v_level <> 'admin_petugas'
           or v_pengawas is null
           or pml_id = v_pengawas)
      and (v_level not in ('pengawas_wilayah','admin_wilayah')
           or ppl_id = v_petugas)
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
      m_total, m_terkirim,
      approved_pengawas, submitted_pencacah, submitted_respondent,
      draft_awal, draft_revisi, rejected_pengawas, revoked_pengawas,
      edited_admin_kab, rejected_admin_kab
    from scoped
  ),
  rows_base as (
    select
      unit_id,
      min(title)    as title,
      min(subtitle) as subtitle,
      sum(m_total)::int    as total_assignment,
      sum(m_terkirim)::int as total_terkirim
    from normalized
    where unit_id is not null and unit_id <> ''
    group by unit_id
  ),
  -- Unpivot status → long, untuk status_counts & status_aliases.
  status_long as (
    select n.unit_id, s.label, s.cnt
    from normalized n
    cross join lateral (values
      ('APPROVED Pengawas',    n.approved_pengawas),
      ('SUBMITTED Pencacah',   n.submitted_pencacah),
      ('SUBMITTED Respondent', n.submitted_respondent),
      ('DRAFT Awal',           n.draft_awal),
      ('DRAFT Revisi',         n.draft_revisi),
      ('REJECTED Pengawas',    n.rejected_pengawas),
      ('REVOKED Pengawas',     n.revoked_pengawas),
      ('EDITED Admin Kab',     n.edited_admin_kab),
      ('REJECTED Admin Kab',   n.rejected_admin_kab)
    ) as s(label, cnt)
    where n.unit_id is not null and n.unit_id <> '' and s.cnt <> 0
  ),
  status_counts as (
    select unit_id, jsonb_object_agg(label, total order by label) as status_counts
    from (
      select unit_id, label, sum(cnt)::int as total
      from status_long
      group by unit_id, label
    ) x
    group by unit_id
  ),
  rows_with_counts as (
    select
      rb.unit_id,
      rb.title,
      rb.subtitle,
      rb.total_assignment,
      rb.total_terkirim,
      coalesce(sc.status_counts, '{}'::jsonb) as status_counts
    from rows_base rb
    left join status_counts sc on sc.unit_id = rb.unit_id
  ),
  filtered_rows as (
    select *
    from rows_with_counts
    where coalesce(trim(p_search), '') = ''
       or title ilike '%' || trim(p_search) || '%'
       or subtitle ilike '%' || trim(p_search) || '%'
  ),
  summary as (
    select
      count(*)::int as total_units,
      coalesce(sum(total_assignment), 0)::int as total_assignments,
      coalesce(sum(total_terkirim), 0)::int as total_terkirim
    from filtered_rows
  ),
  status_aliases as (
    select label as status_alias, sum(cnt)::int as total
    from status_long
    group by label
    order by total desc, label asc
  ),
  chart as (
    select unit_id, title as label, total_assignment
    from filtered_rows
    order by total_assignment desc, title asc
    limit 8
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
    'summary', jsonb_build_object(
      'level', v_level,
      'total_units', coalesce((select total_units from summary), 0),
      'total_assignments', coalesce((select total_assignments from summary), 0),
      'total_terkirim', coalesce((select total_terkirim from summary), 0)
    ),
    'chart', coalesce((select jsonb_agg(to_jsonb(chart)) from chart), '[]'::jsonb),
    'rows', coalesce((select jsonb_agg(to_jsonb(paged)) from paged), '[]'::jsonb),
    'status_aliases', coalesce((select jsonb_agg(to_jsonb(status_aliases)) from status_aliases), '[]'::jsonb),
    'periods', '[]'::jsonb,
    'meta', jsonb_build_object(
      'level', v_level,
      'limit', v_limit,
      'offset', v_offset,
      'returned_rows', coalesce((select count(*) from paged), 0),
      'sort_by', v_sort_by,
      'sort_dir', v_sort_dir,
      'snapshot_date', v_snap
    )
  )
  into v_result;

  return coalesce(v_result, public._fasih_empty_payload(v_level, v_limit, v_offset));
end;
$$;

grant execute on function public.get_fasih_rekap(text, text, boolean, text, text, integer, integer, text, text) to authenticated;
