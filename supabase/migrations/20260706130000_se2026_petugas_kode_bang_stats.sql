-- RPC untuk tab "Analisis" (khusus admin): pivot Petugas × Kode Bangunan.
--
-- Jumlah dihitung dari baris se2026_keterangan_umum, dikelompokkan berdasarkan
-- petugas (current_user_fullname, fallback current_user_username) DAN kode_bang.
-- Petugas kosong -> 'Tidak Diketahui'. kode_bang kosong dikembalikan NULL untuk
-- dipetakan menjadi "Tidak Diketahui" di aplikasi.
--
-- Akses dibatasi role = 'admin': selain admin mengembalikan hasil kosong.

create or replace function public.get_se2026_petugas_kode_bang_stats()
returns table (
  petugas text,
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
    coalesce(
      nullif(btrim(ku.current_user_fullname), ''),
      nullif(btrim(ku.current_user_username), ''),
      'Tidak Diketahui'
    ) as petugas,
    nullif(btrim(ku.kode_bang), '') as kode_bang,
    count(*)::bigint as jumlah
  from public.se2026_keterangan_umum ku
  group by 1, 2
  order by 1 asc, jumlah desc, 2 asc;
end;
$$;

grant execute on function public.get_se2026_petugas_kode_bang_stats() to authenticated;
