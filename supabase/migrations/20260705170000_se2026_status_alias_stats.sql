-- RPC untuk tab "Analisis" (khusus admin).
-- Mengembalikan statistik jumlah baris se2026_keterangan_umum yang
-- dikelompokkan berdasarkan assignment_status_alias, diurutkan dari jumlah
-- terbesar. NULL alias dinormalisasi menjadi 'Tidak Diketahui'.
--
-- Akses dibatasi role = 'admin' (mengikuti pola RPC titik assignment):
-- selain admin mengembalikan hasil kosong.

create or replace function public.get_se2026_status_alias_stats()
returns table (
  assignment_status_alias text,
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

  select u.id
    into v_user_id
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
    coalesce(nullif(btrim(ku.assignment_status_alias), ''), 'Tidak Diketahui')
      as assignment_status_alias,
    count(*)::bigint as jumlah
  from public.se2026_keterangan_umum ku
  group by 1
  order by jumlah desc, 1 asc;
end;
$$;

grant execute on function public.get_se2026_status_alias_stats() to authenticated;
