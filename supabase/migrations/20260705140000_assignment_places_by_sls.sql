-- RPC on-demand: ambil titik assignment untuk SATU SLS saja.
--
-- Menghindari download seluruh se2026_keterangan_umum (bisa 20k baris, kena
-- batas 1000 baris PostgREST). Dipakai halaman peta setelah pengguna memilih
-- SLS lewat long-press. Satu SLS jauh di bawah 1000 baris sehingga aman.
--
-- Pemetaan kode wilayah:
--   idsls (dari polygon peta) = 14 digit  = prov(2)+kab(2)+kec(3)+desa(3)+sls(4)
--   se2026_keterangan_umum.kode_wilayah   = 16 digit = kode_desa(10)+kode_sls(4)+sub_sls(2)
--   => satu SLS = left(kode_wilayah, 14) = idsls
--
-- Scope role dipertahankan: admin boleh SLS mana pun; pengawas (pml_id) /
-- pendata (ppl_id) hanya SLS yang ada di se2026_wilayah_tugas miliknya.

create or replace function public.get_assignment_places_by_sls(
  p_idsls text
)
returns table (
  assignment_id text,
  no_bang integer,
  nama_usaha text,
  latitude numeric,
  longitude numeric
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_auth_uid uuid := auth.uid();
  v_user_id uuid;
  v_petugas_id uuid;
  v_role text;
  v_is_active boolean := false;
  v_sls text;
begin
  if p_idsls is null or length(p_idsls) < 14 then
    return;
  end if;
  v_sls := left(p_idsls, 14);

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

  select p.id, p.role, coalesce(p.is_active, false)
    into v_petugas_id, v_role, v_is_active
  from public.se2026_petugas p
  where p.user_id = v_user_id
  order by p.created_at desc nulls last
  limit 1;

  if v_petugas_id is null or not v_is_active then
    return;
  end if;

  -- Non-admin: SLS harus termasuk wilayah tugasnya.
  if v_role in ('pengawas', 'pendata') then
    if not exists (
      select 1
      from public.se2026_wilayah_tugas wt
      where left(wt.id, 14) = v_sls
        and (
          (v_role = 'pengawas' and wt.pml_id = v_petugas_id)
          or (v_role = 'pendata' and wt.ppl_id = v_petugas_id)
        )
    ) then
      return;
    end if;
  elsif v_role <> 'admin' then
    return;
  end if;

  return query
  select
    ku.assignment_id,
    ku.no_bang::integer,
    ku.data1 as nama_usaha,
    ku.latitude,
    ku.longitude
  from public.se2026_keterangan_umum ku
  where left(ku.kode_wilayah, 14) = v_sls
    and ku.latitude is not null
    and ku.longitude is not null
    and ku.latitude between -90 and 90
    and ku.longitude between -180 and 180;
end;
$$;

grant execute on function public.get_assignment_places_by_sls(text) to authenticated;
