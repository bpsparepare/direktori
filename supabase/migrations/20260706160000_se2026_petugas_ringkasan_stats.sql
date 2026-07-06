-- RPC untuk tab "Analisis" (khusus admin): ringkasan perolehan per PETUGAS
-- pencacah (ppl_id). Tiga metrik per petugas:
--   * Usaha            = jumlah se2026_usaha dgn keberadaan_usaha IN (1,2)
--   * Keluarga         = jumlah se2026_keluarga
--   * Anggota Keluarga = jumlah se2026_anggota_keluarga
--
-- Semua tabel terhubung ke se2026_keterangan_umum via assignment_id (FK), lalu
-- ke petugas lewat kode_wilayah -> se2026_wilayah_tugas (16 digit) -> ppl_id
-- -> users.name. Wilayah tanpa PPL / tak cocok -> 'Tidak Diketahui'.
--
-- Output long-format (petugas, metrik, jumlah) supaya aplikasi menyusunnya
-- menjadi pivot. Akses dibatasi role = 'admin'.

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
      ) as petugas
    from public.se2026_keterangan_umum ku
    left join wilayah16 w on w.w16 = left(ku.kode_wilayah, 16)
    left join public.se2026_petugas p on p.id = w.ppl_id
    left join public.users u on u.id = p.user_id
  )
  select kp.petugas, 'Usaha'::text as metrik, count(*)::bigint as jumlah
  from public.se2026_usaha us
  join ku_petugas kp on kp.assignment_id = us.assignment_id
  where btrim(us.keberadaan_usaha) in ('1', '2')
  group by kp.petugas
  union all
  select kp.petugas, 'Keluarga'::text, count(*)::bigint
  from public.se2026_keluarga kl
  join ku_petugas kp on kp.assignment_id = kl.assignment_id
  group by kp.petugas
  union all
  select kp.petugas, 'Anggota Keluarga'::text, count(*)::bigint
  from public.se2026_anggota_keluarga ak
  join ku_petugas kp on kp.assignment_id = ak.assignment_id
  group by kp.petugas
  order by 1, 2;
end;
$$;

grant execute on function public.get_se2026_petugas_ringkasan_stats() to authenticated;
