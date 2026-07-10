-- Rekap kumulatif: tampilkan SEMUA wilayah kerja petugas pada level wilayah,
-- termasuk SLS yang belum punya assignment sama sekali (muncul dengan 0).
--
-- Sebelumnya daftar unit dibangun murni dari se2026_assignment_list, sehingga
-- SLS tanpa assignment tidak pernah tampil. Di sini ditambahkan:
--   * wilayah_universe : semua SLS pada scope petugas (dari wilayah_tugas)
--   * unit_universe    : gabungan universe wilayah + unit hasil assignment
-- lalu rows_with_counts di-LEFT JOIN ke agregat assignment (0 bila kosong).
--
-- Level non-wilayah (pengawas/petugas/pengawas-agregat) tidak berubah:
-- wilayah_universe kosong sehingga unit_universe = unit hasil assignment.

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

  -- role membatasi drill (sama seperti harian)
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

  -- default sort per level
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

  with
  -- gabung assignment dengan scope wilayah (sumber sama dengan harian)
  assignment_base as (
    select
      al.assignment_id,
      coalesce(nullif(trim(al.status_text), ''), 'OPEN') as status_alias,
      al.kode_wilayah,
      sw.nm_sls,
      sw.nm_kec,
      sw.nm_desa,
      sw.pml_id,
      sw.pml_name,
      sw.pml_username,
      sw.ppl_id,
      sw.ppl_name,
      sw.ppl_username
    from public.se2026_assignment_list al
    join public.vw_fasih_wilayah_scope_base sw
      on sw.kode_wilayah = al.kode_wilayah
    where (p_survey_period_id is null or al.survey_period_id = p_survey_period_id)
  ),
  -- filter sesuai scope user (predikat identik dengan harian)
  scoped as (
    select *
    from assignment_base
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
      assignment_id,
      status_alias
    from scoped
  ),
  -- SEMUA wilayah kerja petugas pada level wilayah (walau tanpa assignment).
  -- Predikat scope identik dengan CTE `scoped`. Untuk level non-wilayah CTE ini
  -- kosong sehingga tidak mengubah perilaku.
  wilayah_universe as (
    select
      sw.kode_wilayah as unit_id,
      coalesce(nullif(trim(sw.nm_sls), ''), sw.kode_wilayah) as title,
      concat_ws(' / ', nullif(trim(sw.nm_kec), ''), nullif(trim(sw.nm_desa), '')) as subtitle
    from public.vw_fasih_wilayah_scope_base sw
    where v_level in ('pendata_wilayah','pengawas_wilayah','admin_wilayah')
      and (v_level <> 'pendata_wilayah'  or sw.ppl_id = v_petugas_id)
      and (v_level <> 'pengawas_wilayah' or sw.pml_id = v_petugas_id)
      and (v_level not in ('pengawas_wilayah','admin_wilayah')
           or sw.ppl_id = v_petugas)
  ),
  rows_base as (
    select
      unit_id,
      min(title)    as title,
      min(subtitle) as subtitle,
      count(assignment_id)::int as total_assignment,
      -- "terkirim": sudah final, yaitu semua status kecuali OPEN & DRAFT
      count(assignment_id) filter (
        where upper(status_alias) not like 'OPEN%'
          and upper(status_alias) not like 'DRAFT%'
      )::int as total_terkirim
    from normalized
    where unit_id is not null and unit_id <> ''
    group by unit_id
  ),
  status_counts as (
    select
      unit_id,
      jsonb_object_agg(status_alias, cnt order by status_alias) as status_counts
    from (
      select unit_id, status_alias, count(assignment_id)::int as cnt
      from normalized
      where unit_id is not null and unit_id <> ''
      group by unit_id, status_alias
    ) c
    group by unit_id
  ),
  -- Daftar unit final: gabungan universe wilayah + unit hasil assignment.
  unit_universe as (
    select unit_id, min(title) as title, min(subtitle) as subtitle
    from (
      select unit_id, title, subtitle from wilayah_universe
      union all
      select unit_id, title, subtitle
      from normalized
      where unit_id is not null and unit_id <> ''
    ) u
    where unit_id is not null and unit_id <> ''
    group by unit_id
  ),
  rows_with_counts as (
    select
      uu.unit_id,
      uu.title,
      uu.subtitle,
      coalesce(rb.total_assignment, 0) as total_assignment,
      coalesce(rb.total_terkirim, 0)   as total_terkirim,
      coalesce(sc.status_counts, '{}'::jsonb) as status_counts
    from unit_universe uu
    left join rows_base rb    on rb.unit_id = uu.unit_id
    left join status_counts sc on sc.unit_id = uu.unit_id
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
    select status_alias, count(assignment_id)::int as total
    from normalized
    where unit_id is not null and unit_id <> ''
    group by status_alias
    order by total desc, status_alias asc
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
      'sort_dir', v_sort_dir
    )
  )
  into v_result;

  return coalesce(v_result, public._fasih_empty_payload(v_level, v_limit, v_offset));
end;
$$;

grant execute on function public.get_fasih_rekap(text, text, boolean, text, text, integer, integer, text, text) to authenticated;
