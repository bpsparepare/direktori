-- Fitur "Submit": daftar assignment yang belum submit (REJECTED/DRAFT/OPEN)
-- + penandaan "Perlu Dihapus" oleh petugas.
--
-- Latar: se2026_tindak_lanjut di-REPLACE PENUH tiap upload ekstensi
-- (import_tindak_lanjut menghapus semua baris lalu mengisi ulang). Karena itu
-- tanda "perlu dihapus" TIDAK boleh berupa kolom di tabel tsb — akan hilang
-- setiap impor. Tanda disimpan di tabel TERPISAH se2026_tindak_lanjut_hapus
-- (kunci assignment_id, stabil lintas impor) dan digabung saat baca.
--
-- Hak baca/tandai: admin semua; pengawas SLS dgn pml_id = dirinya; pendata SLS
-- dgn ppl_id = dirinya (via se2026_wilayah_tugas.id = level_6_full_code).

-- ── Tabel sumber (sama dgn skrip impor ekstensi; idempoten) ──────────────────
create table if not exists public.se2026_tindak_lanjut (
  assignment_id            text primary key,
  assignment_status_alias  text,
  assignment_status_id     integer,
  level_6_full_code        text,
  level_6_name             text,
  nama                     text,
  alamat                   text,
  no_bang                  text,
  updated_at               timestamptz not null default now()
);

create index if not exists idx_tindak_level6
  on public.se2026_tindak_lanjut (level_6_full_code);
create index if not exists idx_tindak_status
  on public.se2026_tindak_lanjut (assignment_status_alias);

alter table public.se2026_tindak_lanjut enable row level security;

-- ── Tabel tanda "perlu dihapus" (tidak tersentuh impor) ──────────────────────
create table if not exists public.se2026_tindak_lanjut_hapus (
  assignment_id text primary key,
  alasan        text,
  flagged_by    uuid,          -- se2026_petugas.id
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- Akses langsung ditolak; hanya lewat RPC security definer di bawah.
alter table public.se2026_tindak_lanjut_hapus enable row level security;

-- ── Helper: petugas aktif saat ini + cek scope wilayah ───────────────────────
-- Mengembalikan pesan error (text) atau null bila boleh. p_kode = kode SLS 16 digit.
create or replace function public._tindak_lanjut_scope_error(
  p_kode       text,
  out petugas_id uuid,
  out err_msg    text
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_role      text;
  v_is_active boolean := false;
begin
  if auth.uid() is null then
    err_msg := 'Tidak terautentikasi';
    return;
  end if;

  select p.id, p.role, coalesce(p.is_active, false)
    into petugas_id, v_role, v_is_active
  from public.users u
  join public.se2026_petugas p on p.user_id = u.id
  where u.auth_uid = auth.uid()
  order by p.created_at desc nulls last
  limit 1;

  if petugas_id is null or not v_is_active then
    err_msg := 'Petugas tidak aktif';
    return;
  end if;

  if v_role = 'admin' then
    return;
  elsif v_role in ('pengawas', 'pendata') then
    if not exists (
      select 1
      from public.se2026_wilayah_tugas wt
      where wt.id = p_kode
        and (
          (v_role = 'pengawas' and wt.pml_id = petugas_id)
          or (v_role = 'pendata' and wt.ppl_id = petugas_id)
        )
    ) then
      err_msg := 'Di luar wilayah tugas Anda';
    end if;
  else
    err_msg := 'Role tidak diizinkan';
  end if;
end;
$$;

revoke all on function public._tindak_lanjut_scope_error(text) from public, anon;

-- ── Baca daftar (role-based) + gabung tanda hapus ────────────────────────────
drop function if exists public.get_tindak_lanjut();
create function public.get_tindak_lanjut()
returns table (
  assignment_id           text,
  assignment_status_alias text,
  assignment_status_id    integer,
  level_6_full_code       text,
  level_6_name            text,
  nama                    text,
  alamat                  text,
  no_bang                 text,
  nm_kec                  text,
  nm_desa                 text,
  nm_sls                  text,
  ppl_nama                text,
  pml_nama                text,
  updated_at              timestamptz,
  perlu_hapus             boolean,
  alasan_hapus            text,
  hapus_oleh              text,
  hapus_at                timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  with me as (
    select p.id as petugas_id, p.role
    from public.users u
    join public.se2026_petugas p on p.user_id = u.id
    where u.auth_uid = auth.uid()
      and coalesce(p.is_active, false)
    order by p.created_at desc nulls last
    limit 1
  )
  select
    t.assignment_id,
    t.assignment_status_alias,
    t.assignment_status_id,
    t.level_6_full_code,
    t.level_6_name,
    t.nama,
    t.alamat,
    t.no_bang,
    sw.nm_kec,
    sw.nm_desa,
    sw.nm_sls,
    sw.ppl_name,
    sw.pml_name,
    t.updated_at,
    (h.assignment_id is not null) as perlu_hapus,
    h.alasan,
    coalesce(nullif(trim(hu.name), ''), hu.email),
    h.updated_at
  from public.se2026_tindak_lanjut t
  cross join me
  left join public.vw_fasih_wilayah_scope_base sw
    on sw.kode_wilayah = t.level_6_full_code
  left join public.se2026_tindak_lanjut_hapus h
    on h.assignment_id = t.assignment_id
  left join public.se2026_petugas hp on hp.id = h.flagged_by
  left join public.users hu on hu.id = hp.user_id
  where me.role = 'admin'
     or (me.role = 'pengawas' and sw.pml_id = me.petugas_id)
     or (me.role = 'pendata'  and sw.ppl_id = me.petugas_id)
  order by sw.nm_kec nulls last, sw.nm_desa nulls last,
           t.level_6_full_code, t.nama;
$$;

grant execute on function public.get_tindak_lanjut() to authenticated;

-- ── Tandai "perlu dihapus" ───────────────────────────────────────────────────
create or replace function public.set_tindak_lanjut_hapus(
  p_assignment_id text,
  p_alasan        text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_kode  text;
  v_scope record;
begin
  if p_assignment_id is null or trim(p_assignment_id) = '' then
    return jsonb_build_object('ok', false, 'error', 'assignment_id kosong');
  end if;

  select t.level_6_full_code into v_kode
  from public.se2026_tindak_lanjut t
  where t.assignment_id = p_assignment_id;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Assignment tidak ditemukan');
  end if;

  select * into v_scope from public._tindak_lanjut_scope_error(v_kode);
  if v_scope.err_msg is not null then
    return jsonb_build_object('ok', false, 'error', v_scope.err_msg);
  end if;

  insert into public.se2026_tindak_lanjut_hapus as h
    (assignment_id, alasan, flagged_by, created_at, updated_at)
  values
    (p_assignment_id, nullif(trim(p_alasan), ''), v_scope.petugas_id, now(), now())
  on conflict (assignment_id) do update
    set alasan     = excluded.alasan,
        flagged_by = excluded.flagged_by,
        updated_at = now();

  return jsonb_build_object('ok', true, 'assignment_id', p_assignment_id);
end;
$$;

grant execute on function public.set_tindak_lanjut_hapus(text, text) to authenticated;

-- ── Batalkan tanda "perlu dihapus" ───────────────────────────────────────────
create or replace function public.unset_tindak_lanjut_hapus(
  p_assignment_id text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_kode  text;
  v_scope record;
begin
  select t.level_6_full_code into v_kode
  from public.se2026_tindak_lanjut t
  where t.assignment_id = p_assignment_id;

  -- Bila assignment sudah tidak ada di daftar (sudah beres), tanda yatim boleh
  -- dibersihkan siapa pun yang aktif; selain itu wajib dalam scope.
  select * into v_scope from public._tindak_lanjut_scope_error(v_kode);
  if v_scope.petugas_id is null
     or (v_kode is not null and v_scope.err_msg is not null) then
    return jsonb_build_object('ok', false, 'error', coalesce(v_scope.err_msg, 'Tidak diizinkan'));
  end if;

  delete from public.se2026_tindak_lanjut_hapus
  where assignment_id = p_assignment_id;

  return jsonb_build_object('ok', true, 'assignment_id', p_assignment_id);
end;
$$;

grant execute on function public.unset_tindak_lanjut_hapus(text) to authenticated;
