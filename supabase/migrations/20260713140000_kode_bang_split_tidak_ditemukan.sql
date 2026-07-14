-- get_se2026_kode_bang_by_wilayah: pecah "Tidak Ditemukan" (kode_bang kosong)
-- menjadi Usaha vs Keluarga berdasarkan se2026_keterangan_umum.jenis_prelist.
--
-- Untuk record dengan kode_bang kosong/NULL:
--   * jenis_prelist mengandung 'keluarga' -> key 'TD_KELUARGA'
--   * selain itu (termasuk kosong)        -> key 'TD_USAHA'
-- Record dengan kode_bang terisi (1..9) memakai kode_bang apa adanya.
--
-- Return type tetap (kode_wilayah, ppl_id, kode_bang_counts jsonb); hanya
-- KUNCI di dalam jsonb yang berubah ('' diganti TD_USAHA/TD_KELUARGA).

create or replace function public.get_se2026_kode_bang_by_wilayah()
returns table (
  kode_wilayah text,
  ppl_id uuid,
  kode_bang_counts jsonb
)
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
  v_is_active  boolean := false;
begin
  if v_auth_uid is null then
    return;
  end if;

  select u.id into v_user_id
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

  if not v_is_active or v_petugas_id is null then
    return;
  end if;

  return query
  with wilayah_scope as (
    select distinct on (left(wt.id, 16))
      left(wt.id, 16) as w16,
      wt.pml_id,
      wt.ppl_id as scope_ppl_id
    from public.se2026_wilayah_tugas wt
    where wt.id is not null
    order by left(wt.id, 16), wt.created_at desc nulls last
  ),
  base as (
    select
      ws.w16 as kode_wilayah,
      ws.scope_ppl_id as ppl_id,
      case
        when nullif(btrim(ku.kode_bang), '') is not null
          then btrim(ku.kode_bang)
        when lower(btrim(coalesce(ku.jenis_prelist, ''))) like '%keluarga%'
          then 'TD_KELUARGA'
        else 'TD_USAHA'
      end as kb,
      count(*)::int as cnt
    from public.se2026_keterangan_umum ku
    join wilayah_scope ws
      on ws.w16 = left(ku.kode_wilayah, 16)
    where (
      v_role = 'admin'
      or (v_role = 'pengawas' and ws.pml_id = v_petugas_id)
      or (v_role = 'pendata'  and ws.scope_ppl_id = v_petugas_id)
    )
    -- Hanya record submitted (bukan OPEN & bukan DRAFT).
    and ku.assignment_status_alias is not null
    and upper(btrim(ku.assignment_status_alias)) not like 'OPEN%'
    and upper(btrim(ku.assignment_status_alias)) not like 'DRAFT%'
    group by 1, 2, 3
  )
  select
    base.kode_wilayah,
    base.ppl_id,
    jsonb_object_agg(base.kb, base.cnt) as kode_bang_counts
  from base
  group by 1, 2;
end;
$$;

grant execute on function public.get_se2026_kode_bang_by_wilayah() to authenticated;
