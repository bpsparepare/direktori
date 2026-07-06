-- RPC untuk tab "Analisis" (khusus admin): statistik jumlah baris
-- se2026_keterangan_umum dikelompokkan berdasarkan kode_bang.
--
-- Pemetaan label kode_bang dilakukan di sisi aplikasi Flutter. RPC hanya
-- mengembalikan kode mentah (di-trim) + jumlah. NULL/kosong dikembalikan apa
-- adanya (NULL) agar aplikasi memetakannya menjadi "Tidak Diketahui".
--
-- Akses dibatasi role = 'admin' (mengikuti pola RPC lain): selain admin
-- mengembalikan hasil kosong.

create or replace function public.get_se2026_kode_bang_stats()
returns table (
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
    nullif(btrim(ku.kode_bang), '') as kode_bang,
    count(*)::bigint as jumlah
  from public.se2026_keterangan_umum ku
  group by 1
  order by jumlah desc, 1 asc;
end;
$$;

grant execute on function public.get_se2026_kode_bang_stats() to authenticated;
