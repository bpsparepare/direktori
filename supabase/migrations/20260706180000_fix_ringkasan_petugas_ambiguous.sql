-- Perbaikan: "column reference petugas is ambiguous" (42702) pada
-- get_se2026_petugas_ringkasan_stats. Kolom CTE usaha.petugas bentrok dengan
-- OUT parameter fungsi (petugas). Kualifikasikan semua referensi ke CTE.

create or replace function public.get_se2026_petugas_ringkasan_stats()
returns table (
  petugas text,
  metrik text,
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
  ),
  ku_petugas as (
    select
      ku.assignment_id,
      coalesce(
        nullif(btrim(u.name), ''),
        nullif(btrim(u.email), ''),
        'Tidak Diketahui'
      ) as nama_petugas
    from public.se2026_keterangan_umum ku
    left join wilayah16 w on w.w16 = left(ku.kode_wilayah, 16)
    left join public.se2026_petugas p on p.id = w.ppl_id
    left join public.users u on u.id = p.user_id
  ),
  usaha as (
    select kp.nama_petugas, us.kategori
    from public.se2026_usaha us
    join ku_petugas kp on kp.assignment_id = us.assignment_id
    where btrim(us.keberadaan_usaha) in ('1', '2')
  )
  select usaha.nama_petugas, 'Usaha'::text as metrik, count(*)::bigint as jumlah
  from usaha
  group by usaha.nama_petugas
  union all
  select usaha.nama_petugas, 'Usaha Pertanian'::text, count(*)::bigint
  from usaha
  where upper(btrim(usaha.kategori)) = 'A'
  group by usaha.nama_petugas
  union all
  select usaha.nama_petugas, 'Usaha Non Pertanian'::text, count(*)::bigint
  from usaha
  where usaha.kategori is null or upper(btrim(usaha.kategori)) <> 'A'
  group by usaha.nama_petugas
  union all
  select kp.nama_petugas, 'Keluarga'::text, count(*)::bigint
  from public.se2026_keluarga kl
  join ku_petugas kp on kp.assignment_id = kl.assignment_id
  group by kp.nama_petugas
  union all
  select kp.nama_petugas, 'Anggota Keluarga'::text, count(*)::bigint
  from public.se2026_anggota_keluarga ak
  join ku_petugas kp on kp.assignment_id = ak.assignment_id
  group by kp.nama_petugas
  order by 1, 2;
end;
$$;

grant execute on function public.get_se2026_petugas_ringkasan_stats() to authenticated;
