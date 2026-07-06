-- RPC untuk tab "Analisis" (khusus admin): pivot Petugas × Keberadaan Usaha.
--
-- Jumlah dihitung dari baris se2026_usaha (per usaha), dikelompokkan
-- berdasarkan PETUGAS PENCACAH (ppl_id) DAN keberadaan_usaha.
--
-- Rantai relasi:
--   se2026_usaha.assignment_id -> se2026_keterangan_umum.assignment_id (FK)
--   -> kode_wilayah -> se2026_wilayah_tugas via wilayah 16 digit
--   -> ppl_id -> users.name.
-- Wilayah tanpa PPL / tak cocok -> petugas 'Tidak Diketahui'. keberadaan_usaha
-- kosong dikembalikan NULL untuk dipetakan menjadi "Tidak Diketahui" di aplikasi.
--
-- Akses dibatasi role = 'admin': selain admin mengembalikan hasil kosong.

create or replace function public.get_se2026_petugas_usaha_stats()
returns table (
  petugas text,
  keberadaan_usaha text,
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
  with wilayah16 as (
    select distinct on (left(wt.id, 16))
      left(wt.id, 16) as w16,
      wt.ppl_id
    from public.se2026_wilayah_tugas wt
    where wt.id is not null
    order by left(wt.id, 16), wt.created_at desc nulls last
  )
  select
    coalesce(
      nullif(btrim(u.name), ''),
      nullif(btrim(u.email), ''),
      'Tidak Diketahui'
    ) as petugas,
    nullif(btrim(us.keberadaan_usaha), '') as keberadaan_usaha,
    count(*)::bigint as jumlah
  from public.se2026_usaha us
  join public.se2026_keterangan_umum ku
    on ku.assignment_id = us.assignment_id
  left join wilayah16 w
    on w.w16 = left(ku.kode_wilayah, 16)
  left join public.se2026_petugas p
    on p.id = w.ppl_id
  left join public.users u
    on u.id = p.user_id
  group by 1, 2
  order by 1 asc, jumlah desc, 2 asc;
end;
$$;

grant execute on function public.get_se2026_petugas_usaha_stats() to authenticated;
