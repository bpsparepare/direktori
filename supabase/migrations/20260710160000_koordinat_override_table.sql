-- Override koordinat marker (edit posisi via drag di peta).
--
-- Latar: titik marker bersumber dari se2026_keterangan_umum yang diisi lewat
-- IMPORT, sehingga latitude/longitude bisa tertimpa saat data pusat berubah.
-- Agar hasil edit posisi tidak hilang, koreksi disimpan di tabel TERPISAH ini
-- dan digabung saat baca (COALESCE) — lihat migrasi read RPC berikutnya.
--
-- Kunci join: assignment_id (dijamin stabil lintas import).
-- Hak edit  : sesuai scope wilayah (admin bebas; pengawas/pendata hanya SLS di
--             se2026_wilayah_tugas miliknya) — konsisten dgn get_assignment_places_by_sls.

create table if not exists public.se2026_koordinat_override (
  assignment_id text primary key,
  kode_wilayah  text,
  latitude      numeric not null,
  longitude     numeric not null,
  edited_by     uuid,          -- se2026_petugas.id
  note          text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index if not exists idx_koordinat_override_kode_wilayah
  on public.se2026_koordinat_override (kode_wilayah);

-- Akses langsung ditolak; hanya lewat RPC security definer di bawah.
alter table public.se2026_koordinat_override enable row level security;

-- ── Simpan / perbarui override posisi ────────────────────────────────────────
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

  -- Ambil kode_wilayah dari assignment untuk validasi scope.
  select ku.kode_wilayah into v_kode_wilayah
  from public.se2026_keterangan_umum ku
  where ku.assignment_id = p_assignment_id
  limit 1;
  if v_kode_wilayah is null then
    return jsonb_build_object('ok', false, 'error', 'Assignment tidak ditemukan');
  end if;
  v_sls14 := left(v_kode_wilayah, 14);

  -- Scope: pengawas/pendata hanya boleh di wilayah tugasnya; admin bebas.
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

-- ── Hapus override (kembalikan ke posisi asli hasil import) ───────────────────
create or replace function public.delete_koordinat_override(
  p_assignment_id text
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

  select ov.kode_wilayah into v_kode_wilayah
  from public.se2026_koordinat_override ov
  where ov.assignment_id = p_assignment_id
  limit 1;
  if v_kode_wilayah is null then
    -- tidak ada override → anggap sukses (idempoten)
    return jsonb_build_object('ok', true, 'assignment_id', p_assignment_id, 'deleted', false);
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

  delete from public.se2026_koordinat_override
  where assignment_id = p_assignment_id;

  return jsonb_build_object('ok', true, 'assignment_id', p_assignment_id, 'deleted', true);
end;
$$;

grant execute on function public.delete_koordinat_override(text) to authenticated;
