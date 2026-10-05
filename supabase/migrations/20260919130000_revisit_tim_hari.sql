-- Revisit: informasi tim (2 orang per tim, hanya label) + hari ke- per
-- alokasi SLS + impor cepat alokasi (tempel dari clipboard).
-- Lanjutan dari 20260919120000_revisit.sql.

alter table public.se2026_revisit_petugas
  add column if not exists tim text;

alter table public.se2026_revisit_alokasi
  add column if not exists hari_ke integer
    check (hari_ke is null or hari_ke between 1 and 366);

-- ── Tim revisit (admin): + kolom tim ─────────────────────────────────────────
drop function if exists public.get_revisit_petugas();
create function public.get_revisit_petugas()
returns table (
  petugas_id  uuid,
  nama        text,
  email       text,
  role        text,
  is_revisit  boolean,
  jumlah_sls  integer,
  tim         text
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
    ), 0),
    rp.tim::text
  from public.vw_revisit_petugas_nama n
  join public.se2026_petugas p on p.id = n.petugas_id
  left join public.se2026_revisit_petugas rp on rp.petugas_id = n.petugas_id
  where coalesce(p.is_active, false)
    and n.role in ('pengawas', 'pendata')
  order by (rp.petugas_id is null), n.nama;
end;
$$;

grant execute on function public.get_revisit_petugas() to authenticated;

create or replace function public.set_revisit_petugas_tim(
  p_petugas_id uuid,
  p_tim        text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
begin
  if (select me.role from public._revisit_me() me) is distinct from 'admin' then
    return jsonb_build_object('ok', false, 'error', 'Hanya admin');
  end if;

  update public.se2026_revisit_petugas
     set tim = nullif(trim(p_tim), '')
   where petugas_id = p_petugas_id;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Petugas belum masuk tim revisit');
  end if;

  return jsonb_build_object('ok', true);
end;
$$;

grant execute on function public.set_revisit_petugas_tim(uuid, text) to authenticated;

-- ── Alokasi SLS (admin): + hari_ke & tim ─────────────────────────────────────
drop function if exists public.get_revisit_alokasi();
create function public.get_revisit_alokasi()
returns table (
  kode_sls           text,
  nm_kec             text,
  nm_desa            text,
  nm_sls             text,
  pml_nama           text,
  ppl_nama           text,
  revisit_petugas_id uuid,
  revisit_nama       text,
  revisit_tim        text,
  hari_ke            integer
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
    n.nama::text,
    rp.tim::text,
    a.hari_ke
  from public.vw_fasih_wilayah_scope_base sw
  left join public.se2026_revisit_alokasi a on a.kode_sls = sw.kode_wilayah
  left join public.se2026_revisit_petugas rp on rp.petugas_id = a.petugas_id
  left join public.vw_revisit_petugas_nama n on n.petugas_id = a.petugas_id
  order by sw.nm_kec nulls last, sw.nm_desa nulls last, sw.kode_wilayah;
end;
$$;

grant execute on function public.get_revisit_alokasi() to authenticated;

-- p_hari_ke null = pertahankan hari_ke yang sudah ada.
drop function if exists public.set_revisit_alokasi(text[], uuid);
create function public.set_revisit_alokasi(
  p_kode_sls   text[],
  p_petugas_id uuid,
  p_hari_ke    integer default null
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
    (kode_sls, petugas_id, hari_ke, assigned_by, assigned_at)
  select k, p_petugas_id, p_hari_ke, v_me.petugas_id, now()
  from unnest(p_kode_sls) as k
  where exists (select 1 from public.se2026_wilayah_tugas wt where wt.id = k)
  on conflict (kode_sls) do update
    set petugas_id  = excluded.petugas_id,
        hari_ke     = coalesce(excluded.hari_ke, a.hari_ke),
        assigned_by = excluded.assigned_by,
        assigned_at = now();
  get diagnostics v_count = row_count;

  return jsonb_build_object('ok', true, 'count', v_count);
end;
$$;

grant execute on function public.set_revisit_alokasi(text[], uuid, integer) to authenticated;

-- Baris impor yang valid: kode SLS ada di wilayah tugas, petugas aktif,
-- hari_ke dalam rentang. Kode SLS ganda: diambil baris terakhir.
create or replace function public._revisit_import_rows(p_rows jsonb)
returns table (kode_sls text, petugas_id uuid, hari_ke integer, tim text)
language sql
stable
security definer
set search_path = public
as $$
  select distinct on (x.kode_sls)
    x.kode_sls,
    x.petugas_id,
    x.hari_ke,
    nullif(trim(x.tim), '')
  from rows from (
         jsonb_to_recordset(coalesce(p_rows, '[]'::jsonb))
           as (kode_sls text, petugas_id uuid, hari_ke integer, tim text)
       ) with ordinality as x(kode_sls, petugas_id, hari_ke, tim, ord)
  where exists (select 1 from public.se2026_wilayah_tugas wt where wt.id = x.kode_sls)
    and exists (
      select 1 from public.se2026_petugas p
      where p.id = x.petugas_id and coalesce(p.is_active, false)
    )
    and (x.hari_ke is null or x.hari_ke between 1 and 366)
  order by x.kode_sls, x.ord desc;
$$;

revoke all on function public._revisit_import_rows(jsonb) from public, anon;

-- Impor cepat: p_rows = [{kode_sls, petugas_id, hari_ke?, tim?}, ...] yang
-- sudah diverifikasi di aplikasi. Petugas yang belum masuk tim otomatis
-- ditambahkan; tim diisi/diperbarui bila disertakan. Baris dengan kode SLS
-- atau petugas tidak valid dilewati (dilaporkan di 'skipped').
create or replace function public.import_revisit_alokasi(p_rows jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_me    record;
  v_total integer;
  v_valid integer;
begin
  select * into v_me from public._revisit_me();
  if v_me.role is distinct from 'admin' then
    return jsonb_build_object('ok', false, 'error', 'Hanya admin');
  end if;

  v_total := jsonb_array_length(coalesce(p_rows, '[]'::jsonb));
  select count(*) into v_valid from public._revisit_import_rows(p_rows);

  insert into public.se2026_revisit_petugas as rp (petugas_id, added_by, tim)
  select distinct on (i.petugas_id) i.petugas_id, v_me.petugas_id, i.tim
  from public._revisit_import_rows(p_rows) i
  order by i.petugas_id, (i.tim is null)
  on conflict (petugas_id) do update
    set tim = coalesce(excluded.tim, rp.tim);

  insert into public.se2026_revisit_alokasi as a
    (kode_sls, petugas_id, hari_ke, assigned_by, assigned_at)
  select i.kode_sls, i.petugas_id, i.hari_ke, v_me.petugas_id, now()
  from public._revisit_import_rows(p_rows) i
  on conflict (kode_sls) do update
    set petugas_id  = excluded.petugas_id,
        hari_ke     = coalesce(excluded.hari_ke, a.hari_ke),
        assigned_by = excluded.assigned_by,
        assigned_at = now();

  return jsonb_build_object(
    'ok', true,
    'count', v_valid,
    'skipped', v_total - v_valid
  );
end;
$$;

grant execute on function public.import_revisit_alokasi(jsonb) to authenticated;

-- ── Tugas saya: + hari_ke ────────────────────────────────────────────────────
drop function if exists public.get_revisit_tugas_saya();
create function public.get_revisit_tugas_saya()
returns table (
  kode_sls          text,
  nm_kec            text,
  nm_desa           text,
  nm_sls            text,
  hari_ke           integer,
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
    a.hari_ke,
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
  order by a.hari_ke nulls last, sw.nm_kec nulls last, sw.nm_desa nulls last,
           a.kode_sls;
$$;

grant execute on function public.get_revisit_tugas_saya() to authenticated;

-- ── Laporan: + tim petugas & hari_ke alokasi ─────────────────────────────────
drop function if exists public.get_revisit_laporan(date, date, uuid, text);
create function public.get_revisit_laporan(
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
  petugas_tim   text,
  hari_ke       integer,
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
    rp.tim::text,
    a.hari_ke,
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
  left join public.se2026_revisit_petugas rp on rp.petugas_id = l.petugas_id
  left join public.se2026_revisit_alokasi a on a.kode_sls = l.kode_sls
  where me.petugas_id is not null
    and (me.role = 'admin' or l.petugas_id = me.petugas_id)
    and (p_petugas_id is null or l.petugas_id = p_petugas_id)
    and (p_kode_sls is null or l.kode_sls = p_kode_sls)
  order by l.tanggal desc, n.nama, l.kode_sls, l.id;
$$;

grant execute on function public.get_revisit_laporan(date, date, uuid, text) to authenticated;
