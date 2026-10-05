-- Pindahkan sumber titik marker peta (tab Jelajah) dari se2026_keterangan_umum
-- ke se2026_geotag. Signature kedua RPC TIDAK berubah, jadi kode Flutter
-- (AssignmentPlacesService) tidak perlu diubah sama sekali.
--
-- Perubahan sumber:
--   ku.kode_wilayah        -> g.level_6_full_code
--   ku.data1               -> g.nama_usaha_bang (fallback g.nama_kk)
--   ku.no_bang   (integer) -> g.no_bang (text, dicast aman: ambil digit saja)
--   ku.latitude/longitude  -> g.geotag_latitude/geotag_longitude (float8 -> numeric)
--   ku.kode_bang           -> g.kode_bang_value
--   ku.source_modified_at  -> g.updated_at  (assignment_date_modified bertipe TEXT
--                             sehingga tidak dipakai untuk sync incremental)
--
-- Override koordinat hasil drag (se2026_koordinat_override) tetap di-COALESCE
-- di atas koordinat import, persis seperti sebelumnya.
--
-- CATATAN PERUBAHAN PERILAKU (perbaikan bug):
--   Pada versi lama, cabang pengawas/pendata di get_assignment_places_for_current_user
--   memakai `ku.kode_bang IS NULL`, padahal cabang admin dan RPC per-SLS memakai
--   `IS NOT NULL` (lihat 20260705160000 yang menyatakan "hanya baris dengan kode_bang
--   TERISI yang ditampilkan"). Di sini semuanya diseragamkan ke IS NOT NULL.

-- Index bantu untuk sync incremental (filter updated_at).
create index if not exists idx_geotag_updated_at
  on public.se2026_geotag using btree (updated_at);

-- ── 1) RPC per-SLS (dipakai peta on-demand saat SLS dipilih) ─────────────────
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
  v_len int;
  v_sls14 text;
  v_code16 text;
begin
  if p_idsls is null or length(p_idsls) < 14 then
    return;
  end if;
  v_len := length(p_idsls);
  v_sls14 := left(p_idsls, 14);
  v_code16 := left(p_idsls, 16);

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

  if v_role in ('pengawas', 'pendata') then
    if not exists (
      select 1
      from public.se2026_wilayah_tugas wt
      where left(wt.id, 14) = v_sls14
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
    g.assignment_id,
    nullif(regexp_replace(coalesce(g.no_bang, ''), '[^0-9]', '', 'g'), '')::integer
      as no_bang,
    coalesce(
      nullif(btrim(g.nama_usaha_bang), ''),
      nullif(btrim(g.nama_kk), ''),
      ''
    ) as nama_usaha,
    coalesce(ov.latitude,  g.geotag_latitude::numeric)  as latitude,
    coalesce(ov.longitude, g.geotag_longitude::numeric) as longitude
  from public.se2026_geotag g
  left join public.se2026_koordinat_override ov
    on ov.assignment_id = g.assignment_id
  where
    (
      (v_len >= 16 and g.level_6_full_code = v_code16)
      or (v_len < 16 and left(g.level_6_full_code, 14) = v_sls14)
    )
    and g.kode_bang_value is not null
    and coalesce(ov.latitude,  g.geotag_latitude::numeric)  is not null
    and coalesce(ov.longitude, g.geotag_longitude::numeric) is not null
    and coalesce(ov.latitude,  g.geotag_latitude::numeric)  between -90  and 90
    and coalesce(ov.longitude, g.geotag_longitude::numeric) between -180 and 180;
end;
$$;

grant execute on function public.get_assignment_places_by_sls(text) to authenticated;

-- ── 2) RPC full / incremental (tombol download & cache offline) ──────────────
create or replace function public.get_assignment_places_for_current_user(
  p_sync_mode text,
  p_modified_after timestamp with time zone default null
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
begin
  if p_sync_mode not in ('full', 'incremental') then
    raise exception 'Invalid sync mode: %', p_sync_mode
      using errcode = '22023';
  end if;

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

  if v_role = 'admin' then
    return query
    select
      g.assignment_id,
      nullif(regexp_replace(coalesce(g.no_bang, ''), '[^0-9]', '', 'g'), '')::integer
        as no_bang,
      coalesce(
        nullif(btrim(g.nama_usaha_bang), ''),
        nullif(btrim(g.nama_kk), ''),
        ''
      ) as nama_usaha,
      coalesce(ov.latitude,  g.geotag_latitude::numeric)  as latitude,
      coalesce(ov.longitude, g.geotag_longitude::numeric) as longitude
    from public.se2026_geotag g
    left join public.se2026_koordinat_override ov
      on ov.assignment_id = g.assignment_id
    where
      g.kode_bang_value is not null
      and coalesce(ov.latitude,  g.geotag_latitude::numeric)  is not null
      and coalesce(ov.longitude, g.geotag_longitude::numeric) is not null
      and coalesce(ov.latitude,  g.geotag_latitude::numeric)  between -90  and 90
      and coalesce(ov.longitude, g.geotag_longitude::numeric) between -180 and 180
      and (
        p_sync_mode = 'full'
        or p_modified_after is null
        or g.updated_at > p_modified_after
      );
    return;
  end if;

  if v_role not in ('pengawas', 'pendata') then
    return;
  end if;

  return query
  with wilayah_scope as (
    select distinct wt.id as kode_wilayah
    from public.se2026_wilayah_tugas wt
    where (
      v_role = 'pengawas' and wt.pml_id = v_petugas_id
    ) or (
      v_role = 'pendata' and wt.ppl_id = v_petugas_id
    )
  )
  select distinct
    g.assignment_id,
    nullif(regexp_replace(coalesce(g.no_bang, ''), '[^0-9]', '', 'g'), '')::integer
      as no_bang,
    coalesce(
      nullif(btrim(g.nama_usaha_bang), ''),
      nullif(btrim(g.nama_kk), ''),
      ''
    ) as nama_usaha,
    coalesce(ov.latitude,  g.geotag_latitude::numeric)  as latitude,
    coalesce(ov.longitude, g.geotag_longitude::numeric) as longitude
  from public.se2026_geotag g
  join wilayah_scope ws
    on g.level_6_full_code = ws.kode_wilayah
  left join public.se2026_koordinat_override ov
    on ov.assignment_id = g.assignment_id
  where
    g.kode_bang_value is not null
    and coalesce(ov.latitude,  g.geotag_latitude::numeric)  is not null
    and coalesce(ov.longitude, g.geotag_longitude::numeric) is not null
    and coalesce(ov.latitude,  g.geotag_latitude::numeric)  between -90  and 90
    and coalesce(ov.longitude, g.geotag_longitude::numeric) between -180 and 180
    and (
      p_sync_mode = 'full'
      or p_modified_after is null
      or g.updated_at > p_modified_after
    );
end;
$$;

grant execute on function public.get_assignment_places_for_current_user(text, timestamp with time zone) to authenticated;

-- ── 3) Validasi scope saat simpan override: ikut lihat se2026_geotag ─────────
-- upsert_koordinat_override mengambil kode_wilayah dari se2026_keterangan_umum.
-- Kalau assignment hanya ada di se2026_geotag, drag marker akan gagal dengan
-- "Assignment tidak ditemukan". Tambahkan fallback ke geotag.
create or replace function public.upsert_koordinat_override(
  p_assignment_id text,
  p_latitude      numeric,
  p_longitude     numeric,
  p_note          text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_auth_uid     uuid := auth.uid();
  v_user_id      uuid;
  v_petugas_id   uuid;
  v_role         text;
  v_is_active    boolean := false;
  v_kode_wilayah text;
  v_sls14        text;
begin
  if v_auth_uid is null then
    return jsonb_build_object('ok', false, 'error', 'Tidak terautentikasi');
  end if;
  if p_assignment_id is null or trim(p_assignment_id) = '' then
    return jsonb_build_object('ok', false, 'error', 'assignment_id kosong');
  end if;
  if p_latitude is null or p_longitude is null
     or p_latitude  not between -90  and 90
     or p_longitude not between -180 and 180 then
    return jsonb_build_object('ok', false, 'error', 'Koordinat tidak valid');
  end if;

  select u.id into v_user_id
  from public.users u
  where u.auth_uid = v_auth_uid
  limit 1;
  if v_user_id is null then
    return jsonb_build_object('ok', false, 'error', 'User tidak ditemukan');
  end if;

  select p.id, p.role, coalesce(p.is_active, false)
    into v_petugas_id, v_role, v_is_active
  from public.se2026_petugas p
  where p.user_id = v_user_id
  order by p.created_at desc nulls last
  limit 1;
  if v_petugas_id is null or not v_is_active then
    return jsonb_build_object('ok', false, 'error', 'Petugas tidak aktif');
  end if;

  -- Ambil kode_wilayah dari geotag (sumber marker), fallback ke keterangan_umum.
  select g.level_6_full_code into v_kode_wilayah
  from public.se2026_geotag g
  where g.assignment_id = p_assignment_id
  limit 1;

  if v_kode_wilayah is null then
    select ku.kode_wilayah into v_kode_wilayah
    from public.se2026_keterangan_umum ku
    where ku.assignment_id = p_assignment_id
    limit 1;
  end if;

  if v_kode_wilayah is null then
    return jsonb_build_object('ok', false, 'error', 'Assignment tidak ditemukan');
  end if;
  v_sls14 := left(v_kode_wilayah, 14);

  if v_role in ('pengawas', 'pendata') then
    if not exists (
      select 1
      from public.se2026_wilayah_tugas wt
      where left(wt.id, 14) = v_sls14
        and (
          (v_role = 'pengawas' and wt.pml_id = v_petugas_id)
          or (v_role = 'pendata' and wt.ppl_id = v_petugas_id)
        )
    ) then
      return jsonb_build_object('ok', false, 'error', 'Di luar wilayah tugas Anda');
    end if;
  elsif v_role <> 'admin' then
    return jsonb_build_object('ok', false, 'error', 'Role tidak diizinkan');
  end if;

  insert into public.se2026_koordinat_override as ov
    (assignment_id, kode_wilayah, latitude, longitude, edited_by, note, created_at, updated_at)
  values
    (p_assignment_id, v_kode_wilayah, p_latitude, p_longitude,
     v_petugas_id, nullif(trim(p_note), ''), now(), now())
  on conflict (assignment_id) do update
    set latitude     = excluded.latitude,
        longitude    = excluded.longitude,
        kode_wilayah = excluded.kode_wilayah,
        edited_by    = excluded.edited_by,
        note         = excluded.note,
        updated_at   = now();

  return jsonb_build_object(
    'ok', true,
    'assignment_id', p_assignment_id,
    'latitude', p_latitude,
    'longitude', p_longitude
  );
end;
$$;

grant execute on function public.upsert_koordinat_override(text, numeric, numeric, text) to authenticated;
