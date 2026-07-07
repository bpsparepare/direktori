-- Fitur "Responden Sulit".
--
-- Petugas mendata responden yang sulit ditemui/diwawancarai. Setiap entri
-- otomatis terhubung ke PPL (pendata) dan PML (pengawas) wilayah yang dipilih,
-- sehingga:
--   * PPL (role 'pendata') melihat & mengelola entri di wilayahnya sendiri.
--   * PML (role 'pengawas') melihat SEMUA entri PPL di bawahnya, dan boleh
--     ikut menambah / mengisi tindak lanjut.
--   * admin melihat semua.
--
-- Wilayah kerja bersifat opsional. Jika dipilih (id se2026_wilayah_tugas),
-- ppl_id & pml_id diturunkan dari wilayah tersebut. Jika tidak dipilih:
--   * pendata -> ppl_id = dirinya, pml_id = pengawas_id-nya.
--   * pengawas -> pml_id = dirinya, ppl_id kosong.
--
-- Field inti: nama, alamat, penjelasan, tindak_lanjut.

-- ============================================================
-- 1. TABEL
-- ============================================================
create table if not exists public.se2026_responden_sulit (
  id uuid primary key default gen_random_uuid(),
  kode_wilayah text,                       -- id se2026_wilayah_tugas (opsional)
  ppl_id uuid references public.se2026_petugas(id),
  pml_id uuid references public.se2026_petugas(id),
  nama text not null,
  alamat text,
  penjelasan text,
  tindak_lanjut text,
  created_by uuid references public.se2026_petugas(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_responden_sulit_ppl on public.se2026_responden_sulit (ppl_id);
create index if not exists idx_responden_sulit_pml on public.se2026_responden_sulit (pml_id);
create index if not exists idx_responden_sulit_wilayah on public.se2026_responden_sulit (kode_wilayah);

-- Akses hanya lewat RPC security definer di bawah.
alter table public.se2026_responden_sulit enable row level security;

-- ============================================================
-- 2. LIST (role-based)
-- ============================================================
create or replace function public.get_responden_sulit(
  p_limit integer default 500,
  p_offset integer default 0
)
returns table (
  id uuid,
  kode_wilayah text,
  nm_kec text,
  nm_desa text,
  nm_sls text,
  ppl_id uuid,
  pml_id uuid,
  ppl_nama text,
  pml_nama text,
  created_by uuid,
  created_by_nama text,
  nama text,
  alamat text,
  penjelasan text,
  tindak_lanjut text,
  can_edit boolean,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_petugas_id uuid;
  v_role text;
  v_is_active boolean := false;
begin
  select p.id, p.role, coalesce(p.is_active, false)
    into v_petugas_id, v_role, v_is_active
  from public.users u
  join public.se2026_petugas p on p.user_id = u.id
  where u.auth_uid = auth.uid()
  limit 1;

  if v_petugas_id is null or not v_is_active then
    return;
  end if;

  return query
  select
    r.id,
    r.kode_wilayah,
    wt.nm_kec,
    wt.nm_desa,
    wt.nm_sls,
    r.ppl_id,
    r.pml_id,
    ppl.nama,
    pml.nama,
    r.created_by,
    cb.nama,
    r.nama,
    r.alamat,
    r.penjelasan,
    r.tindak_lanjut,
    (
      v_role = 'admin'
      or r.created_by = v_petugas_id
      or (v_role = 'pengawas' and r.pml_id = v_petugas_id)
    ) as can_edit,
    r.created_at,
    r.updated_at
  from public.se2026_responden_sulit r
  left join public.se2026_wilayah_tugas wt on wt.id = r.kode_wilayah
  left join public.se2026_petugas ppl on ppl.id = r.ppl_id
  left join public.se2026_petugas pml on pml.id = r.pml_id
  left join public.se2026_petugas cb on cb.id = r.created_by
  where
    v_role = 'admin'
    or (v_role = 'pengawas' and r.pml_id = v_petugas_id)
    or (v_role = 'pendata' and r.ppl_id = v_petugas_id)
  order by r.updated_at desc
  limit p_limit offset p_offset;
end;
$$;

-- ============================================================
-- 3. UPSERT (insert baru bila p_id null, kalau tidak update)
-- ============================================================
create or replace function public.upsert_responden_sulit(
  p_nama text,
  p_id uuid default null,
  p_kode_wilayah text default null,
  p_alamat text default null,
  p_penjelasan text default null,
  p_tindak_lanjut text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_petugas_id uuid;
  v_role text;
  v_is_active boolean := false;
  v_pengawas_id uuid;
  v_kode text := nullif(btrim(coalesce(p_kode_wilayah, '')), '');
  v_ppl_id uuid;
  v_pml_id uuid;
  v_result uuid;
  v_owner uuid;
  v_owner_pml uuid;
begin
  if nullif(btrim(coalesce(p_nama, '')), '') is null then
    raise exception 'Nama responden wajib diisi';
  end if;

  select p.id, p.role, coalesce(p.is_active, false), p.pengawas_id
    into v_petugas_id, v_role, v_is_active, v_pengawas_id
  from public.users u
  join public.se2026_petugas p on p.user_id = u.id
  where u.auth_uid = auth.uid()
  limit 1;

  if v_petugas_id is null or not v_is_active then
    raise exception 'Tidak diizinkan';
  end if;

  -- Turunkan ppl_id & pml_id.
  if v_kode is not null then
    select wt.ppl_id, wt.pml_id
      into v_ppl_id, v_pml_id
    from public.se2026_wilayah_tugas wt
    where wt.id = v_kode
    limit 1;

    if v_ppl_id is null and v_pml_id is null then
      raise exception 'Wilayah kerja tidak ditemukan';
    end if;
  else
    if v_role = 'pendata' then
      v_ppl_id := v_petugas_id;
      v_pml_id := v_pengawas_id;
    elsif v_role = 'pengawas' then
      v_pml_id := v_petugas_id;
    end if;
  end if;

  -- Otorisasi: pendata hanya boleh wilayahnya sendiri, pengawas hanya
  -- wilayah timnya, admin bebas.
  if v_role = 'pendata' and coalesce(v_ppl_id, '00000000-0000-0000-0000-000000000000') <> v_petugas_id then
    raise exception 'Wilayah kerja bukan milik Anda';
  elsif v_role = 'pengawas' and coalesce(v_pml_id, '00000000-0000-0000-0000-000000000000') <> v_petugas_id then
    raise exception 'Wilayah kerja bukan tim Anda';
  elsif v_role not in ('pendata', 'pengawas', 'admin') then
    raise exception 'Tidak diizinkan';
  end if;

  if p_id is null then
    insert into public.se2026_responden_sulit (
      kode_wilayah, ppl_id, pml_id, nama, alamat, penjelasan, tindak_lanjut, created_by
    )
    values (
      v_kode, v_ppl_id, v_pml_id,
      btrim(p_nama), p_alamat, p_penjelasan, p_tindak_lanjut, v_petugas_id
    )
    returning id into v_result;
  else
    select created_by, pml_id into v_owner, v_owner_pml
    from public.se2026_responden_sulit
    where id = p_id;

    if v_owner is null then
      raise exception 'Entri tidak ditemukan';
    end if;

    if not (
      v_role = 'admin'
      or v_owner = v_petugas_id
      or (v_role = 'pengawas' and v_owner_pml = v_petugas_id)
    ) then
      raise exception 'Tidak diizinkan mengubah entri ini';
    end if;

    update public.se2026_responden_sulit
    set kode_wilayah = v_kode,
        ppl_id = v_ppl_id,
        pml_id = v_pml_id,
        nama = btrim(p_nama),
        alamat = p_alamat,
        penjelasan = p_penjelasan,
        tindak_lanjut = p_tindak_lanjut,
        updated_at = now()
    where id = p_id
    returning id into v_result;
  end if;

  return v_result;
end;
$$;

-- ============================================================
-- 4. HAPUS
-- ============================================================
create or replace function public.delete_responden_sulit(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_petugas_id uuid;
  v_role text;
  v_is_active boolean := false;
  v_owner uuid;
  v_owner_pml uuid;
begin
  select p.id, p.role, coalesce(p.is_active, false)
    into v_petugas_id, v_role, v_is_active
  from public.users u
  join public.se2026_petugas p on p.user_id = u.id
  where u.auth_uid = auth.uid()
  limit 1;

  if v_petugas_id is null or not v_is_active then
    raise exception 'Tidak diizinkan';
  end if;

  select created_by, pml_id into v_owner, v_owner_pml
  from public.se2026_responden_sulit
  where id = p_id;

  if v_owner is null then
    return;
  end if;

  if not (
    v_role = 'admin'
    or v_owner = v_petugas_id
    or (v_role = 'pengawas' and v_owner_pml = v_petugas_id)
  ) then
    raise exception 'Tidak diizinkan menghapus entri ini';
  end if;

  delete from public.se2026_responden_sulit where id = p_id;
end;
$$;

grant execute on function public.get_responden_sulit(integer, integer) to authenticated;
grant execute on function public.upsert_responden_sulit(text, uuid, text, text, text, text) to authenticated;
grant execute on function public.delete_responden_sulit(uuid) to authenticated;

notify pgrst, 'reload schema';
