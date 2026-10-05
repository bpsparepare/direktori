-- Fitur "Revisit": kunjungan ulang SLS oleh tim khusus (±26 orang) yang
-- dipilih dari petugas yang ada (bisa PML maupun PPL).
--
-- - Alokasi revisit TERPISAH dari se2026_wilayah_tugas (pml_id/ppl_id asli
--   tidak berubah). 1 SLS = 1 petugas revisit (PK kode_sls).
-- - Laporan harian: satu laporan per SLS per tanggal, berisi status
--   kunjungan, jumlah usaha/ruta dicek, catatan, dan foto (Google Drive).
-- - Hak akses: admin mengatur tim & alokasi serta melihat semua laporan;
--   petugas revisit hanya melihat/mengisi laporan untuk SLS alokasinya.
--
-- Semua akses tabel lewat RPC security definer (RLS aktif tanpa policy).

-- ── Tabel ────────────────────────────────────────────────────────────────────
create table if not exists public.se2026_revisit_petugas (
  petugas_id uuid primary key references public.se2026_petugas(id) on delete cascade,
  added_by   uuid,
  created_at timestamptz not null default now()
);

create table if not exists public.se2026_revisit_alokasi (
  kode_sls    text primary key,  -- 16 digit = se2026_wilayah_tugas.id
  petugas_id  uuid not null references public.se2026_revisit_petugas(petugas_id) on delete cascade,
  assigned_by uuid,
  assigned_at timestamptz not null default now()
);

create index if not exists idx_revisit_alokasi_petugas
  on public.se2026_revisit_alokasi (petugas_id);

create table if not exists public.se2026_revisit_laporan (
  id           uuid primary key default gen_random_uuid(),
  kode_sls     text not null,
  petugas_id   uuid not null references public.se2026_petugas(id),
  tanggal      date not null,
  status       text not null check (
    status in ('selesai', 'belum_selesai', 'kunjungan_ulang', 'tidak_ditemukan')
  ),
  jumlah_dicek integer check (jumlah_dicek is null or jumlah_dicek >= 0),
  catatan      text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (kode_sls, tanggal)
);

create index if not exists idx_revisit_laporan_tanggal
  on public.se2026_revisit_laporan (tanggal, petugas_id);

create table if not exists public.se2026_revisit_foto (
  id            uuid primary key default gen_random_uuid(),
  laporan_id    uuid not null references public.se2026_revisit_laporan(id) on delete cascade,
  drive_file_id text not null,
  link_file     text,
  nama_file     text,
  created_at    timestamptz not null default now()
);

create index if not exists idx_revisit_foto_laporan
  on public.se2026_revisit_foto (laporan_id);

alter table public.se2026_revisit_petugas enable row level security;
alter table public.se2026_revisit_alokasi enable row level security;
alter table public.se2026_revisit_laporan enable row level security;
alter table public.se2026_revisit_foto    enable row level security;

-- ── Helper: petugas aktif saat ini ───────────────────────────────────────────
create or replace function public._revisit_me(
  out petugas_id uuid,
  out role       text,
  out is_revisit boolean
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  select p.id, p.role
    into petugas_id, role
  from public.users u
  join public.se2026_petugas p on p.user_id = u.id
  where u.auth_uid = auth.uid()
    and coalesce(p.is_active, false)
  order by p.created_at desc nulls last
  limit 1;

  is_revisit := petugas_id is not null and exists (
    select 1 from public.se2026_revisit_petugas rp
    where rp.petugas_id = _revisit_me.petugas_id
  );
end;
$$;

revoke all on function public._revisit_me() from public, anon;

-- Nama tampilan petugas (users.name > se2026_petugas.nama > email).
create or replace view public.vw_revisit_petugas_nama as
select
  p.id as petugas_id,
  p.role,
  coalesce(
    nullif(trim(u.name), ''),
    nullif(trim(p.nama), ''),
    nullif(trim(u.email), ''),
    'Tanpa Nama'
  ) as nama,
  u.email
from public.se2026_petugas p
left join public.users u on u.id = p.user_id;

revoke all on public.vw_revisit_petugas_nama from anon, authenticated;

-- ── Konteks untuk menu ───────────────────────────────────────────────────────
create or replace function public.get_revisit_context()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'role', me.role,
    'is_admin', coalesce(me.role = 'admin', false),
    'is_revisit', coalesce(me.is_revisit, false)
  )
  from public._revisit_me() me;
$$;

grant execute on function public.get_revisit_context() to authenticated;

-- ── Tim revisit (admin) ──────────────────────────────────────────────────────
-- Semua petugas aktif + penanda apakah masuk tim revisit + jumlah SLS alokasi.
create or replace function public.get_revisit_petugas()
returns table (
  petugas_id  uuid,
  nama        text,
  email       text,
  role        text,
  is_revisit  boolean,
  jumlah_sls  integer
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if (select me.role from public._revisit_me() me) is distinct from 'admin' then
    raise exception 'Hanya admin';
  end if;

  return query
  select
    n.petugas_id,
    n.nama::text,
    n.email::text,
    n.role::text,
    (rp.petugas_id is not null),
    coalesce((
      select count(*)::integer from public.se2026_revisit_alokasi a
      where a.petugas_id = n.petugas_id
    ), 0)
  from public.vw_revisit_petugas_nama n
  join public.se2026_petugas p on p.id = n.petugas_id
  left join public.se2026_revisit_petugas rp on rp.petugas_id = n.petugas_id
  where coalesce(p.is_active, false)
    and n.role in ('pengawas', 'pendata')
  order by (rp.petugas_id is null), n.nama;
end;
$$;

grant execute on function public.get_revisit_petugas() to authenticated;

-- Tambah/keluarkan petugas dari tim revisit. Mengeluarkan juga melepas
-- alokasi SLS-nya (cascade); laporan yang sudah masuk tetap disimpan.
create or replace function public.set_revisit_petugas(
  p_petugas_id uuid,
  p_aktif      boolean
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_me record;
begin
  select * into v_me from public._revisit_me();
  if v_me.role is distinct from 'admin' then
    return jsonb_build_object('ok', false, 'error', 'Hanya admin');
  end if;

  if p_aktif then
    insert into public.se2026_revisit_petugas (petugas_id, added_by)
    values (p_petugas_id, v_me.petugas_id)
    on conflict (petugas_id) do nothing;
  else
    delete from public.se2026_revisit_petugas where petugas_id = p_petugas_id;
  end if;

  return jsonb_build_object('ok', true);
end;
$$;

grant execute on function public.set_revisit_petugas(uuid, boolean) to authenticated;

-- ── Alokasi SLS (admin) ──────────────────────────────────────────────────────
-- Semua SLS wilayah tugas + petugas revisit (bila sudah dialokasi).
create or replace function public.get_revisit_alokasi()
returns table (
  kode_sls          text,
  nm_kec            text,
  nm_desa           text,
  nm_sls            text,
  pml_nama          text,
  ppl_nama          text,
  revisit_petugas_id uuid,
  revisit_nama      text
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if (select me.role from public._revisit_me() me) is distinct from 'admin' then
    raise exception 'Hanya admin';
  end if;

  return query
  select
    sw.kode_wilayah::text,
    sw.nm_kec::text,
    sw.nm_desa::text,
    sw.nm_sls::text,
    sw.pml_name::text,
    sw.ppl_name::text,
    a.petugas_id,
    n.nama::text
  from public.vw_fasih_wilayah_scope_base sw
  left join public.se2026_revisit_alokasi a on a.kode_sls = sw.kode_wilayah
  left join public.vw_revisit_petugas_nama n on n.petugas_id = a.petugas_id
  order by sw.nm_kec nulls last, sw.nm_desa nulls last, sw.kode_wilayah;
end;
$$;

grant execute on function public.get_revisit_alokasi() to authenticated;

-- Alokasikan banyak SLS sekaligus ke satu petugas revisit.
-- p_petugas_id null = lepas alokasi SLS tersebut.
create or replace function public.set_revisit_alokasi(
  p_kode_sls   text[],
  p_petugas_id uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_me    record;
  v_count integer;
begin
  select * into v_me from public._revisit_me();
  if v_me.role is distinct from 'admin' then
    return jsonb_build_object('ok', false, 'error', 'Hanya admin');
  end if;

  if p_petugas_id is null then
    delete from public.se2026_revisit_alokasi where kode_sls = any(p_kode_sls);
    get diagnostics v_count = row_count;
    return jsonb_build_object('ok', true, 'count', v_count);
  end if;

  if not exists (
    select 1 from public.se2026_revisit_petugas where petugas_id = p_petugas_id
  ) then
    return jsonb_build_object('ok', false, 'error', 'Petugas belum masuk tim revisit');
  end if;

  insert into public.se2026_revisit_alokasi as a
    (kode_sls, petugas_id, assigned_by, assigned_at)
  select k, p_petugas_id, v_me.petugas_id, now()
  from unnest(p_kode_sls) as k
  where exists (select 1 from public.se2026_wilayah_tugas wt where wt.id = k)
  on conflict (kode_sls) do update
    set petugas_id  = excluded.petugas_id,
        assigned_by = excluded.assigned_by,
        assigned_at = now();
  get diagnostics v_count = row_count;

  return jsonb_build_object('ok', true, 'count', v_count);
end;
$$;

grant execute on function public.set_revisit_alokasi(text[], uuid) to authenticated;

-- ── Tugas saya (petugas revisit) ─────────────────────────────────────────────
create or replace function public.get_revisit_tugas_saya()
returns table (
  kode_sls          text,
  nm_kec            text,
  nm_desa           text,
  nm_sls            text,
  jumlah_laporan    integer,
  status_terakhir   text,
  tanggal_terakhir  date
)
language sql
stable
security definer
set search_path = public
as $$
  select
    a.kode_sls,
    sw.nm_kec::text,
    sw.nm_desa::text,
    sw.nm_sls::text,
    (select count(*)::integer from public.se2026_revisit_laporan l
      where l.kode_sls = a.kode_sls),
    last.status,
    last.tanggal
  from public._revisit_me() me
  join public.se2026_revisit_alokasi a on a.petugas_id = me.petugas_id
  left join public.vw_fasih_wilayah_scope_base sw on sw.kode_wilayah = a.kode_sls
  left join lateral (
    select l.status, l.tanggal
    from public.se2026_revisit_laporan l
    where l.kode_sls = a.kode_sls
    order by l.tanggal desc, l.updated_at desc
    limit 1
  ) last on true
  order by sw.nm_kec nulls last, sw.nm_desa nulls last, a.kode_sls;
$$;

grant execute on function public.get_revisit_tugas_saya() to authenticated;

-- ── Laporan harian ───────────────────────────────────────────────────────────
-- Admin: semua petugas (opsional filter p_petugas_id). Selain admin: hanya
-- laporan miliknya sendiri. Foto disertakan sebagai array jsonb.
create or replace function public.get_revisit_laporan(
  p_dari       date,
  p_sampai     date,
  p_petugas_id uuid default null,
  p_kode_sls   text default null
)
returns table (
  id            uuid,
  kode_sls      text,
  nm_kec        text,
  nm_desa       text,
  nm_sls        text,
  petugas_id    uuid,
  petugas_nama  text,
  petugas_role  text,
  tanggal       date,
  status        text,
  jumlah_dicek  integer,
  catatan       text,
  created_at    timestamptz,
  updated_at    timestamptz,
  foto          jsonb
)
language sql
stable
security definer
set search_path = public
as $$
  select
    l.id,
    l.kode_sls,
    sw.nm_kec::text,
    sw.nm_desa::text,
    sw.nm_sls::text,
    l.petugas_id,
    n.nama::text,
    n.role::text,
    l.tanggal,
    l.status,
    l.jumlah_dicek,
    l.catatan,
    l.created_at,
    l.updated_at,
    coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', f.id,
               'drive_file_id', f.drive_file_id,
               'link_file', f.link_file,
               'nama_file', f.nama_file
             ) order by f.created_at)
      from public.se2026_revisit_foto f
      where f.laporan_id = l.id
    ), '[]'::jsonb)
  from public._revisit_me() me
  join public.se2026_revisit_laporan l
    on l.tanggal between p_dari and p_sampai
  left join public.vw_fasih_wilayah_scope_base sw on sw.kode_wilayah = l.kode_sls
  left join public.vw_revisit_petugas_nama n on n.petugas_id = l.petugas_id
  where me.petugas_id is not null
    and (me.role = 'admin' or l.petugas_id = me.petugas_id)
    and (p_petugas_id is null or l.petugas_id = p_petugas_id)
    and (p_kode_sls is null or l.kode_sls = p_kode_sls)
  order by l.tanggal desc, n.nama, l.kode_sls, l.id;
$$;

grant execute on function public.get_revisit_laporan(date, date, uuid, text) to authenticated;

-- Simpan laporan (insert atau update laporan SLS+tanggal yang sama).
-- Hanya petugas revisit yang SLS tsb dialokasikan kepadanya.
create or replace function public.upsert_revisit_laporan(
  p_kode_sls     text,
  p_tanggal      date,
  p_status       text,
  p_jumlah_dicek integer default null,
  p_catatan      text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_me       record;
  v_id       uuid;
  v_owner    uuid;
begin
  select * into v_me from public._revisit_me();
  if v_me.petugas_id is null then
    return jsonb_build_object('ok', false, 'error', 'Petugas tidak aktif');
  end if;

  if not exists (
    select 1 from public.se2026_revisit_alokasi a
    where a.kode_sls = p_kode_sls and a.petugas_id = v_me.petugas_id
  ) then
    return jsonb_build_object('ok', false, 'error', 'SLS ini bukan alokasi revisit Anda');
  end if;

  if p_tanggal is null or p_tanggal > current_date then
    return jsonb_build_object('ok', false, 'error', 'Tanggal tidak valid');
  end if;

  select l.id, l.petugas_id into v_id, v_owner
  from public.se2026_revisit_laporan l
  where l.kode_sls = p_kode_sls and l.tanggal = p_tanggal;

  if v_id is not null and v_owner <> v_me.petugas_id then
    return jsonb_build_object('ok', false, 'error', 'Laporan tanggal ini sudah diisi petugas lain');
  end if;

  if v_id is null then
    insert into public.se2026_revisit_laporan
      (kode_sls, petugas_id, tanggal, status, jumlah_dicek, catatan)
    values
      (p_kode_sls, v_me.petugas_id, p_tanggal, p_status, p_jumlah_dicek,
       nullif(trim(p_catatan), ''))
    returning id into v_id;
  else
    update public.se2026_revisit_laporan
       set status       = p_status,
           jumlah_dicek = p_jumlah_dicek,
           catatan      = nullif(trim(p_catatan), ''),
           updated_at   = now()
     where id = v_id;
  end if;

  return jsonb_build_object('ok', true, 'id', v_id);
end;
$$;

grant execute on function public.upsert_revisit_laporan(text, date, text, integer, text) to authenticated;

-- Hapus laporan (pemilik atau admin). Foto ikut terhapus (cascade); file di
-- Drive dihapus oleh aplikasi sebelum memanggil RPC ini.
create or replace function public.delete_revisit_laporan(p_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_me record;
begin
  select * into v_me from public._revisit_me();
  delete from public.se2026_revisit_laporan l
  where l.id = p_id
    and (v_me.role = 'admin' or l.petugas_id = v_me.petugas_id);
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Laporan tidak ditemukan / tidak diizinkan');
  end if;
  return jsonb_build_object('ok', true);
end;
$$;

grant execute on function public.delete_revisit_laporan(uuid) to authenticated;

-- ── Foto ─────────────────────────────────────────────────────────────────────
create or replace function public.add_revisit_foto(
  p_laporan_id    uuid,
  p_drive_file_id text,
  p_link_file     text default null,
  p_nama_file     text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_me record;
  v_id uuid;
begin
  select * into v_me from public._revisit_me();
  if not exists (
    select 1 from public.se2026_revisit_laporan l
    where l.id = p_laporan_id and l.petugas_id = v_me.petugas_id
  ) then
    return jsonb_build_object('ok', false, 'error', 'Laporan bukan milik Anda');
  end if;

  insert into public.se2026_revisit_foto (laporan_id, drive_file_id, link_file, nama_file)
  values (p_laporan_id, p_drive_file_id, p_link_file, p_nama_file)
  returning id into v_id;

  return jsonb_build_object('ok', true, 'id', v_id);
end;
$$;

grant execute on function public.add_revisit_foto(uuid, text, text, text) to authenticated;

create or replace function public.delete_revisit_foto(p_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_me record;
begin
  select * into v_me from public._revisit_me();
  delete from public.se2026_revisit_foto f
  using public.se2026_revisit_laporan l
  where f.id = p_id
    and l.id = f.laporan_id
    and (v_me.role = 'admin' or l.petugas_id = v_me.petugas_id);
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Foto tidak ditemukan / tidak diizinkan');
  end if;
  return jsonb_build_object('ok', true);
end;
$$;

grant execute on function public.delete_revisit_foto(uuid) to authenticated;
