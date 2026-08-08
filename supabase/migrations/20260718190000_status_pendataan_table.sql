-- Status pendataan manual per wilayah (SLS/sub-SLS) — diisi petugas.
--
-- Latar: progres otomatis (submitted/target) berasal dari data FASIH. Petugas
-- ingin juga menandai STATUS pendataan secara manual per wilayah kerja:
--   Belum Mulai, 30%, 50%, 70%, 90%, Selesai.
-- Status ini disimpan TERPISAH dari data rekap dan digabung saat baca.
--
-- Kunci     : kode_wilayah (SLS/sub-SLS, mengikuti unit_id di Lembar Kerja).
-- Hak edit  : bebas untuk semua petugas aktif (tanpa batas scope wilayah),
--             sesuai keputusan produk. Server hanya memvalidasi autentikasi
--             dan nilai status yang diizinkan.

create table if not exists public.se2026_status_pendataan (
  kode_wilayah text primary key,
  status       text not null,
  note         text,
  edited_by    uuid,          -- se2026_petugas.id (audit)
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

-- Akses langsung ditolak; hanya lewat RPC security definer di bawah.
alter table public.se2026_status_pendataan enable row level security;

-- Nilai status yang diizinkan (kode kanonik).
--   BELUM  = Belum Mulai Pendataan
--   P30    = 30%
--   P50    = 50%
--   P70    = 70%
--   P90    = 90%
--   SELESAI= Selesai Pendataan

-- ── Baca seluruh status (semua wilayah, untuk digabung di Lembar Kerja) ───────
create or replace function public.get_status_pendataan()
returns table (
  kode_wilayah text,
  status       text,
  note         text,
  updated_at   timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select sp.kode_wilayah, sp.status, sp.note, sp.updated_at
  from public.se2026_status_pendataan sp;
$$;

grant execute on function public.get_status_pendataan() to authenticated;

-- ── Simpan / perbarui status pendataan ───────────────────────────────────────
create or replace function public.upsert_status_pendataan(
  p_kode_wilayah text,
  p_status       text,
  p_note         text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_auth_uid   uuid := auth.uid();
  v_user_id    uuid;
  v_petugas_id uuid;
  v_is_active  boolean := false;
  v_status     text := upper(trim(coalesce(p_status, '')));
begin
  if v_auth_uid is null then
    return jsonb_build_object('ok', false, 'error', 'Tidak terautentikasi');
  end if;
  if p_kode_wilayah is null or trim(p_kode_wilayah) = '' then
    return jsonb_build_object('ok', false, 'error', 'kode_wilayah kosong');
  end if;
  if v_status not in ('BELUM', 'P30', 'P50', 'P70', 'P90', 'SELESAI') then
    return jsonb_build_object('ok', false, 'error', 'Status tidak valid');
  end if;

  select u.id into v_user_id
  from public.users u
  where u.auth_uid = v_auth_uid
  limit 1;
  if v_user_id is null then
    return jsonb_build_object('ok', false, 'error', 'User tidak ditemukan');
  end if;

  select p.id, coalesce(p.is_active, false)
    into v_petugas_id, v_is_active
  from public.se2026_petugas p
  where p.user_id = v_user_id
  order by p.created_at desc nulls last
  limit 1;
  if v_petugas_id is null or not v_is_active then
    return jsonb_build_object('ok', false, 'error', 'Petugas tidak aktif');
  end if;

  insert into public.se2026_status_pendataan as sp
    (kode_wilayah, status, note, edited_by, created_at, updated_at)
  values
    (trim(p_kode_wilayah), v_status, nullif(trim(p_note), ''),
     v_petugas_id, now(), now())
  on conflict (kode_wilayah) do update
    set status     = excluded.status,
        note       = excluded.note,
        edited_by  = excluded.edited_by,
        updated_at = now();

  return jsonb_build_object(
    'ok', true,
    'kode_wilayah', trim(p_kode_wilayah),
    'status', v_status
  );
end;
$$;

grant execute on function public.upsert_status_pendataan(text, text, text) to authenticated;

-- ── Hapus status (kembalikan wilayah ke "belum ditandai") ─────────────────────
create or replace function public.delete_status_pendataan(
  p_kode_wilayah text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_auth_uid   uuid := auth.uid();
  v_user_id    uuid;
  v_petugas_id uuid;
  v_is_active  boolean := false;
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

  select p.id, coalesce(p.is_active, false)
    into v_petugas_id, v_is_active
  from public.se2026_petugas p
  where p.user_id = v_user_id
  order by p.created_at desc nulls last
  limit 1;
  if v_petugas_id is null or not v_is_active then
    return jsonb_build_object('ok', false, 'error', 'Petugas tidak aktif');
  end if;

  delete from public.se2026_status_pendataan
  where kode_wilayah = trim(p_kode_wilayah);

  return jsonb_build_object('ok', true, 'kode_wilayah', trim(p_kode_wilayah));
end;
$$;

grant execute on function public.delete_status_pendataan(text) to authenticated;
