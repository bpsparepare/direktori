-- Bukti Dukung: daftar petugas + bukti dokumentasi terakhir per kategori.
--
-- Termin 1 : bukti kategori 'fasih' terakhir dengan created_at < 2026-08-01
--            (yaitu "terakhir sampai bulan Juli 2026").
-- Termin 2 : bukti kategori 'fasih' terakhir (keseluruhan).
-- Paket data: bukti kategori 'bukti paket data' terakhir.
--
-- Akses (mengikuti pola RPC lain, dicek server-side):
--   admin    -> semua petugas aktif.
--   pengawas -> petugas aktif yang pengawas_id = petugas pengawas tsb.
--   lainnya  -> kosong.
create or replace function public.get_bukti_dukung()
returns table (
  petugas_id  uuid,
  user_id     uuid,
  nama        text,
  role        text,
  t1_nama_file text, t1_link text, t1_drive_id text, t1_preview text, t1_created timestamptz,
  t2_nama_file text, t2_link text, t2_drive_id text, t2_preview text, t2_created timestamptz,
  pd_nama_file text, pd_link text, pd_drive_id text, pd_preview text, pd_created timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_auth_uid  uuid := auth.uid();
  v_user_id   uuid;
  v_role      text;
  v_petugas_id uuid;
  v_is_active boolean;
begin
  if v_auth_uid is null then return; end if;

  select u.id into v_user_id
  from public.users u
  where u.auth_uid = v_auth_uid
  limit 1;
  if v_user_id is null then return; end if;

  select p.id, p.role, coalesce(p.is_active, false)
    into v_petugas_id, v_role, v_is_active
  from public.se2026_petugas p
  where p.user_id = v_user_id
  order by p.created_at desc nulls last
  limit 1;

  if v_petugas_id is null or not v_is_active then return; end if;
  if v_role not in ('admin', 'pengawas') then return; end if;

  return query
  with target as (
    select p.id as petugas_id, p.user_id, p.role
    from public.se2026_petugas p
    where coalesce(p.is_active, false) = true
      and (
        v_role = 'admin'
        or (v_role = 'pengawas' and p.pengawas_id = v_petugas_id)
      )
  )
  select
    t.petugas_id,
    t.user_id,
    coalesce(nullif(trim(u.name), ''), u.email, '-')::text as nama,
    t.role::text,
    d1.nama_file, d1.link_file, d1.drive_file_id, d1.preview_url, d1.created_at,
    d2.nama_file, d2.link_file, d2.drive_file_id, d2.preview_url, d2.created_at,
    dp.nama_file, dp.link_file, dp.drive_file_id, dp.preview_url, dp.created_at
  from target t
  join public.users u on u.id = t.user_id
  left join lateral (
    select d.nama_file, d.link_file, d.drive_file_id, d.preview_url, d.created_at
    from public.documentation_uploads d
    where d.user_id = t.user_id
      and d.kategori = 'fasih'
      and d.created_at < timestamptz '2026-08-01T00:00:00+00:00'
    order by d.created_at desc
    limit 1
  ) d1 on true
  left join lateral (
    select d.nama_file, d.link_file, d.drive_file_id, d.preview_url, d.created_at
    from public.documentation_uploads d
    where d.user_id = t.user_id
      and d.kategori = 'fasih'
    order by d.created_at desc
    limit 1
  ) d2 on true
  left join lateral (
    select d.nama_file, d.link_file, d.drive_file_id, d.preview_url, d.created_at
    from public.documentation_uploads d
    where d.user_id = t.user_id
      and d.kategori = 'bukti paket data'
    order by d.created_at desc
    limit 1
  ) dp on true
  order by nama;
end;
$$;

grant execute on function public.get_bukti_dukung() to authenticated;
