-- Perbaikan sumber status: ambil dari se2026_assignment_list.status_text
-- (tabel yang up-to-date), bukan se2026_keterangan_umum.assignment_status_alias.
--
-- 1) get_se2026_status_alias_stats: distribusi status dari assignment_list.
--    Satu status per assignment_id (versi terbaru berdasarkan
--    source_modified_at) agar tidak dobel antar workspace/periode.
-- 2) get_se2026_status_kode_bang_stats: pivot Status × Kode Bangunan.
--    Jumlah dihitung dari baris se2026_keterangan_umum (kode_bang), status
--    diambil dari se2026_assignment_list via assignment_id (versi terbaru).
--
-- Nama kolom output berubah (assignment_status_alias -> status_text) sehingga
-- fungsi di-drop lebih dulu. Akses tetap dibatasi role = 'admin'.

-- 1) Distribusi status ----------------------------------------------------

drop function if exists public.get_se2026_status_alias_stats();

create function public.get_se2026_status_alias_stats()
returns table (
  status_text text,
  jumlah bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_auth_uid uuid := auth.uid();
  v_user_id uuid;
  v_role text;
  v_is_active boolean := false;
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

  select p.role, coalesce(p.is_active, false)
    into v_role, v_is_active
  from public.se2026_petugas p
  where p.user_id = v_user_id
  order by p.created_at desc nulls last
  limit 1;

  if not v_is_active or v_role <> 'admin' then
    return;
  end if;

  return query
  with latest as (
    select distinct on (al.assignment_id) al.status_text
    from public.se2026_assignment_list al
    order by al.assignment_id, al.source_modified_at desc nulls last
  )
  select
    coalesce(nullif(btrim(latest.status_text), ''), 'Tidak Diketahui')
      as status_text,
    count(*)::bigint as jumlah
  from latest
  group by 1
  order by jumlah desc, 1 asc;
end;
$$;

grant execute on function public.get_se2026_status_alias_stats() to authenticated;

-- 2) Pivot Status × Kode Bangunan ----------------------------------------

drop function if exists public.get_se2026_status_kode_bang_stats();

create function public.get_se2026_status_kode_bang_stats()
returns table (
  status_text text,
  kode_bang text,
  jumlah bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_auth_uid uuid := auth.uid();
  v_user_id uuid;
  v_role text;
  v_is_active boolean := false;
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

  select p.role, coalesce(p.is_active, false)
    into v_role, v_is_active
  from public.se2026_petugas p
  where p.user_id = v_user_id
  order by p.created_at desc nulls last
  limit 1;

  if not v_is_active or v_role <> 'admin' then
    return;
  end if;

  return query
  select
    coalesce(nullif(btrim(al.status_text), ''), 'Tidak Diketahui')
      as status_text,
    nullif(btrim(ku.kode_bang), '') as kode_bang,
    count(*)::bigint as jumlah
  from public.se2026_keterangan_umum ku
  left join lateral (
    select a.status_text
    from public.se2026_assignment_list a
    where a.assignment_id = ku.assignment_id
    order by a.source_modified_at desc nulls last
    limit 1
  ) al on true
  group by 1, 2
  order by 1 asc, jumlah desc, 2 asc;
end;
$$;

grant execute on function public.get_se2026_status_kode_bang_stats() to authenticated;
