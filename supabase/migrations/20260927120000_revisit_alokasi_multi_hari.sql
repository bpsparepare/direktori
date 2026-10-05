-- Alokasi revisit: satu SLS boleh DIJADWALKAN beberapa hari.
-- Kunci berubah dari (kode_sls) menjadi (kode_sls, hari_ke).
--   * hari_ke 0 = "hari belum ditentukan" (menggantikan NULL, karena kolom
--     kunci tidak boleh NULL).
--   * Satu SLS tetap satu petugas: saat dialokasikan, SEMUA baris hari SLS
--     itu ikut dipindah ke petugas yang sama.
--   * "Kunjungan terjadwal ke-n sudah dilakukan?" ditentukan dari urutan
--     hari: SLS dengan jadwal H1 & H3 dan baru 1 laporan -> H1 dianggap
--     sudah, H3 belum.

-- ── Ubah kunci tabel ────────────────────────────────────────────────────────
update public.se2026_revisit_alokasi set hari_ke = 0 where hari_ke is null;

alter table public.se2026_revisit_alokasi
  drop constraint if exists se2026_revisit_alokasi_hari_ke_check;
alter table public.se2026_revisit_alokasi
  alter column hari_ke set default 0;
alter table public.se2026_revisit_alokasi
  alter column hari_ke set not null;
alter table public.se2026_revisit_alokasi
  add constraint se2026_revisit_alokasi_hari_ke_check
    check (hari_ke between 0 and 366);

alter table public.se2026_revisit_alokasi
  drop constraint if exists se2026_revisit_alokasi_pkey;
alter table public.se2026_revisit_alokasi
  add primary key (kode_sls, hari_ke);

create index if not exists idx_revisit_alokasi_kode
  on public.se2026_revisit_alokasi (kode_sls);

-- ── Jadwal + penanda sudah/belum dikunjungi ─────────────────────────────────
create or replace view public.vw_revisit_jadwal as
select
  a.kode_sls,
  a.petugas_id,
  a.hari_ke,
  row_number() over (partition by a.kode_sls order by a.hari_ke) as urutan,
  lap.jumlah_laporan,
  lap.total_didata,
  lap.total_submit,
  lap.tanggal_terakhir,
  lap.status_terakhir,
  lap.belum_didata,
  -- Kunjungan ke-n dianggap sudah bila laporan SLS ini minimal n.
  (lap.jumlah_laporan >= row_number() over (
     partition by a.kode_sls order by a.hari_ke
   )) as sudah_dikunjungi
from public.se2026_revisit_alokasi a
left join lateral (
  select
    count(*)::integer                          as jumlah_laporan,
    coalesce(sum(l.jumlah_dicek), 0)::integer  as total_didata,
    coalesce(sum(l.jumlah_submit), 0)::integer as total_submit,
    max(l.tanggal)                             as tanggal_terakhir,
    (array_agg(l.status order by l.tanggal desc, l.updated_at desc))[1]
                                               as status_terakhir,
    (array_agg(l.jumlah_belum_didata order by l.tanggal desc,
                                              l.updated_at desc))[1]
                                               as belum_didata
  from public.se2026_revisit_laporan l
  where l.kode_sls = a.kode_sls
) lap on true;

revoke all on public.vw_revisit_jadwal from anon, authenticated;

-- ── Alokasikan / lepas ──────────────────────────────────────────────────────
-- p_hari_ke null -> 0 (hari belum ditentukan).
-- p_petugas_id null -> lepas: hanya hari tsb bila p_hari_ke diisi, atau
-- SEMUA hari SLS tsb bila p_hari_ke null.
create or replace function public.set_revisit_alokasi(
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
  v_hari  integer := coalesce(p_hari_ke, 0);
begin
  select * into v_me from public._revisit_me();
  if v_me.role is distinct from 'admin' then
    return jsonb_build_object('ok', false, 'error', 'Hanya admin');
  end if;

  if p_petugas_id is null then
    if p_hari_ke is null then
      delete from public.se2026_revisit_alokasi
      where kode_sls = any(p_kode_sls);
    else
      delete from public.se2026_revisit_alokasi
      where kode_sls = any(p_kode_sls) and hari_ke = v_hari;
    end if;
    get diagnostics v_count = row_count;
    return jsonb_build_object('ok', true, 'count', v_count);
  end if;

  if not exists (
    select 1 from public.se2026_revisit_petugas where petugas_id = p_petugas_id
  ) then
    return jsonb_build_object('ok', false, 'error', 'Petugas belum masuk tim revisit');
  end if;

  -- Satu SLS satu petugas: samakan dulu petugas pada semua hari SLS ini.
  update public.se2026_revisit_alokasi
     set petugas_id = p_petugas_id, assigned_by = v_me.petugas_id
   where kode_sls = any(p_kode_sls) and petugas_id <> p_petugas_id;

  insert into public.se2026_revisit_alokasi as a
    (kode_sls, petugas_id, hari_ke, assigned_by, assigned_at)
  select k, p_petugas_id, v_hari, v_me.petugas_id, now()
  from unnest(p_kode_sls) as k
  where exists (select 1 from public.se2026_wilayah_tugas wt where wt.id = k)
  on conflict (kode_sls, hari_ke) do update
    set petugas_id  = excluded.petugas_id,
        assigned_by = excluded.assigned_by,
        assigned_at = now();
  get diagnostics v_count = row_count;

  return jsonb_build_object('ok', true, 'count', v_count);
end;
$$;

grant execute on function public.set_revisit_alokasi(text[], uuid, integer) to authenticated;

-- ── Impor cepat ─────────────────────────────────────────────────────────────
create or replace function public._revisit_import_rows(p_rows jsonb)
returns table (kode_sls text, petugas_id uuid, hari_ke integer, tim text)
language sql
stable
security definer
set search_path = public
as $$
  select distinct on (x.kode_sls, coalesce(x.hari_ke, 0))
    x.kode_sls,
    x.petugas_id,
    coalesce(x.hari_ke, 0),
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
    and (x.hari_ke is null or x.hari_ke between 0 and 366)
  order by x.kode_sls, coalesce(x.hari_ke, 0), x.ord desc;
$$;

revoke all on function public._revisit_import_rows(jsonb) from public, anon;

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

  -- Satu SLS satu petugas, termasuk baris hari lain yang sudah ada.
  update public.se2026_revisit_alokasi a
     set petugas_id = i.petugas_id, assigned_by = v_me.petugas_id
  from (
    select distinct on (r.kode_sls) r.kode_sls, r.petugas_id
    from public._revisit_import_rows(p_rows) r
    order by r.kode_sls, r.hari_ke
  ) i
  where a.kode_sls = i.kode_sls and a.petugas_id <> i.petugas_id;

  insert into public.se2026_revisit_alokasi as a
    (kode_sls, petugas_id, hari_ke, assigned_by, assigned_at)
  select i.kode_sls, i.petugas_id, i.hari_ke, v_me.petugas_id, now()
  from public._revisit_import_rows(p_rows) i
  on conflict (kode_sls, hari_ke) do update
    set petugas_id  = excluded.petugas_id,
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

-- ── Daftar alokasi (admin): satu baris per SLS + daftar hari ────────────────
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
  hari_list          integer[]
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
    ag.petugas_id,
    n.nama::text,
    rp.tim::text,
    ag.hari_list
  from public.vw_fasih_wilayah_scope_base sw
  left join lateral (
    select
      (array_agg(a.petugas_id))[1] as petugas_id,
      array_agg(a.hari_ke order by a.hari_ke) as hari_list
    from public.se2026_revisit_alokasi a
    where a.kode_sls = sw.kode_wilayah
  ) ag on true
  left join public.se2026_revisit_petugas rp on rp.petugas_id = ag.petugas_id
  left join public.vw_revisit_petugas_nama n on n.petugas_id = ag.petugas_id
  order by sw.nm_kec nulls last, sw.nm_desa nulls last, sw.kode_wilayah;
end;
$$;

grant execute on function public.get_revisit_alokasi() to authenticated;

-- ── Tugas saya: satu baris per (SLS, hari jadwal) ───────────────────────────
drop function if exists public.get_revisit_tugas_saya(uuid);
create function public.get_revisit_tugas_saya(p_petugas_id uuid default null)
returns table (
  kode_sls         text,
  nm_kec           text,
  nm_desa          text,
  nm_sls           text,
  hari_ke          integer,
  jumlah_laporan   integer,
  status_terakhir  text,
  tanggal_terakhir date,
  total_didata     integer,
  total_submit     integer,
  belum_didata     integer,
  sudah_dikunjungi boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select
    j.kode_sls,
    sw.nm_kec::text,
    sw.nm_desa::text,
    sw.nm_sls::text,
    nullif(j.hari_ke, 0),
    j.jumlah_laporan,
    j.status_terakhir,
    j.tanggal_terakhir,
    j.total_didata,
    j.total_submit,
    j.belum_didata,
    j.sudah_dikunjungi
  from public._revisit_me() me
  join public.vw_revisit_jadwal j
    on j.petugas_id = coalesce(p_petugas_id, me.petugas_id)
  left join public.vw_fasih_wilayah_scope_base sw
    on sw.kode_wilayah = j.kode_sls
  where me.petugas_id is not null
    and (p_petugas_id is null or p_petugas_id = me.petugas_id or me.role = 'admin')
  order by j.hari_ke, sw.nm_kec nulls last, sw.nm_desa nulls last, j.kode_sls;
$$;

grant execute on function public.get_revisit_tugas_saya(uuid) to authenticated;

-- ── Progres per hari ke- ────────────────────────────────────────────────────
drop function if exists public.get_revisit_progres_hari_ke();
create function public.get_revisit_progres_hari_ke()
returns table (
  hari_ke            integer,
  jumlah_sls         integer,
  sls_dilapor        integer,
  sls_selesai        integer,
  total_didata       integer,
  total_submit       integer,
  sisa_belum_didata  integer
)
language sql
stable
security definer
set search_path = public
as $$
  with j as (
    select jj.*
    from public._revisit_me() me
    join public.vw_revisit_jadwal jj
      on me.role = 'admin' or jj.petugas_id = me.petugas_id
    where me.petugas_id is not null
  )
  select
    nullif(j.hari_ke, 0),
    count(*)::integer,
    count(*) filter (where j.sudah_dikunjungi)::integer,
    count(*) filter (where j.status_terakhir = 'selesai')::integer,
    -- Nilai SLS dihitung sekali, pada hari jadwal pertamanya.
    coalesce(sum(j.total_didata) filter (where j.urutan = 1), 0)::integer,
    coalesce(sum(j.total_submit) filter (where j.urutan = 1), 0)::integer,
    coalesce(sum(j.belum_didata) filter (where j.urutan = 1), 0)::integer
  from j
  group by j.hari_ke
  order by j.hari_ke;
$$;

grant execute on function public.get_revisit_progres_hari_ke() to authenticated;

-- ── Matriks petugas × hari ke- ──────────────────────────────────────────────
drop function if exists public.get_revisit_matriks_hari();
create function public.get_revisit_matriks_hari()
returns table (
  petugas_id   uuid,
  hari_ke      integer,
  jumlah_sls   integer,
  sls_dilapor  integer,
  sls_selesai  integer,
  total_didata integer,
  total_submit integer
)
language sql
stable
security definer
set search_path = public
as $$
  with j as (
    select jj.*
    from public._revisit_me() me
    join public.vw_revisit_jadwal jj
      on me.role = 'admin' or jj.petugas_id = me.petugas_id
    where me.petugas_id is not null
  )
  select
    j.petugas_id,
    nullif(j.hari_ke, 0),
    count(*)::integer,
    count(*) filter (where j.sudah_dikunjungi)::integer,
    count(*) filter (where j.status_terakhir = 'selesai')::integer,
    coalesce(sum(j.total_didata) filter (where j.urutan = 1), 0)::integer,
    coalesce(sum(j.total_submit) filter (where j.urutan = 1), 0)::integer
  from j
  group by j.petugas_id, j.hari_ke
  order by j.petugas_id, j.hari_ke;
$$;

grant execute on function public.get_revisit_matriks_hari() to authenticated;

-- ── Rekap kumulatif per petugas (SLS dihitung unik) ─────────────────────────
create or replace function public.get_revisit_rekap_petugas()
returns table (
  petugas_id         uuid,
  nama               text,
  role               text,
  tim                text,
  jumlah_sls         integer,
  sls_dilapor        integer,
  sls_selesai        integer,
  total_didata       integer,
  total_submit       integer,
  sisa_belum_didata  integer,
  jumlah_laporan     integer,
  jumlah_foto        integer,
  tanggal_terakhir   date
)
language sql
stable
security definer
set search_path = public
as $$
  with per_sls as (
    select
      j.petugas_id as pid,
      j.kode_sls   as kode,
      max(j.jumlah_laporan)     as n_lap,
      max(j.total_didata)       as didata,
      max(j.total_submit)       as submitted,
      max(j.tanggal_terakhir)   as tgl_terakhir,
      max(j.belum_didata)       as sisa,
      (array_agg(j.status_terakhir))[1] as status_terakhir,
      (
        select count(*)::integer
        from public.se2026_revisit_laporan l
        join public.se2026_revisit_foto f on f.laporan_id = l.id
        where l.kode_sls = j.kode_sls
      ) as n_foto
    from public.vw_revisit_jadwal j
    group by j.petugas_id, j.kode_sls
  )
  select
    n.petugas_id,
    n.nama::text,
    n.role::text,
    rp.tim::text,
    count(ps.kode)::integer,
    count(ps.kode) filter (where ps.n_lap > 0)::integer,
    count(ps.kode) filter (where ps.status_terakhir = 'selesai')::integer,
    coalesce(sum(ps.didata), 0)::integer,
    coalesce(sum(ps.submitted), 0)::integer,
    coalesce(sum(ps.sisa), 0)::integer,
    coalesce(sum(ps.n_lap), 0)::integer,
    coalesce(sum(ps.n_foto), 0)::integer,
    max(ps.tgl_terakhir)
  from public._revisit_me() me
  join public.se2026_revisit_petugas rp on true
  join public.vw_revisit_petugas_nama n on n.petugas_id = rp.petugas_id
  left join per_sls ps on ps.pid = rp.petugas_id
  where me.petugas_id is not null
    and (me.role = 'admin' or rp.petugas_id = me.petugas_id)
  group by n.petugas_id, n.nama, n.role, rp.tim
  order by n.nama;
$$;

grant execute on function public.get_revisit_rekap_petugas() to authenticated;

-- ── Laporan: hari_ke = hari jadwal paling awal SLS tsb ──────────────────────
drop function if exists public.get_revisit_laporan(date, date, uuid, text);
create function public.get_revisit_laporan(
  p_dari       date,
  p_sampai     date,
  p_petugas_id uuid default null,
  p_kode_sls   text default null
)
returns table (
  id                  uuid,
  kode_sls            text,
  nm_kec              text,
  nm_desa             text,
  nm_sls              text,
  petugas_id          uuid,
  petugas_nama        text,
  petugas_role        text,
  petugas_tim         text,
  hari_ke             integer,
  tanggal             date,
  status              text,
  jumlah_dicek        integer,
  jumlah_submit       integer,
  jumlah_belum_didata integer,
  catatan             text,
  created_at          timestamptz,
  updated_at          timestamptz,
  foto                jsonb
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
    nullif(jad.hari_ke, 0),
    l.tanggal,
    l.status,
    l.jumlah_dicek,
    l.jumlah_submit,
    l.jumlah_belum_didata,
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
  left join lateral (
    select min(a.hari_ke) as hari_ke
    from public.se2026_revisit_alokasi a
    where a.kode_sls = l.kode_sls
  ) jad on true
  where me.petugas_id is not null
    and (me.role = 'admin' or l.petugas_id = me.petugas_id)
    and (p_petugas_id is null or l.petugas_id = p_petugas_id)
    and (p_kode_sls is null or l.kode_sls = p_kode_sls)
  order by l.tanggal desc, n.nama, l.kode_sls, l.id;
$$;

grant execute on function public.get_revisit_laporan(date, date, uuid, text) to authenticated;

-- ── Boleh melapor bila SLS termasuk alokasi (hari mana pun) ─────────────────
-- (upsert_revisit_laporan sudah memakai EXISTS, aman terhadap banyak baris.)

-- ── Reject: alokasi kini banyak baris per SLS, ambil satu ───────────────────
create or replace function public._revisit_reject_scope_error(
  p_kode         text,
  out petugas_id uuid,
  out err_msg    text
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_me record;
begin
  select * into v_me from public._revisit_me();
  petugas_id := v_me.petugas_id;

  if petugas_id is null then
    err_msg := 'Petugas tidak aktif';
    return;
  end if;
  if v_me.role = 'admin' then
    return;
  end if;
  if not exists (
    select 1 from public.se2026_revisit_alokasi a
    where a.kode_sls = p_kode and a.petugas_id = v_me.petugas_id
  ) then
    err_msg := 'SLS ini bukan alokasi revisit Anda';
  end if;
end;
$$;

revoke all on function public._revisit_reject_scope_error(text) from public, anon;

create or replace function public.get_revisit_reject_sls()
returns table (
  kode_sls           text,
  level_6_name       text,
  nm_kec             text,
  nm_desa            text,
  nm_sls             text,
  revisit_petugas_id uuid,
  revisit_nama       text,
  revisit_tim        text,
  hari_ke            integer,
  jumlah_assignment  integer,
  jumlah_ditandai    integer
)
language sql
stable
security definer
set search_path = public
as $$
  -- Satu baris per SLS walau jadwalnya beberapa hari. Dipakai group by
  -- (bukan DISTINCT ON + ORDER BY) supaya aman digabung dengan UNION ALL.
  with alokasi_sls as (
    select
      a.kode_sls,
      (array_agg(a.petugas_id order by a.hari_ke))[1] as petugas_id,
      min(a.hari_ke) as hari_ke
    from public._revisit_me() me
    join public.se2026_revisit_alokasi a
      on me.role = 'admin' or a.petugas_id = me.petugas_id
    where me.petugas_id is not null
    group by a.kode_sls
  ),
  -- Admin juga melihat SLS di daftar sumber yang belum dialokasikan.
  tanpa_alokasi as (
    select distinct t.level_6_full_code as kode_sls,
           null::uuid as petugas_id,
           null::integer as hari_ke
    from public._revisit_me() me
    join public.se2026_revisit_reject_sumber t on me.role = 'admin'
    where me.petugas_id is not null
      and not exists (
        select 1 from public.se2026_revisit_alokasi a
        where a.kode_sls = t.level_6_full_code
      )
  ),
  kode as (
    select * from alokasi_sls
    union all
    select * from tanpa_alokasi
  ),
  hitung as (
    select
      k.kode_sls,
      k.petugas_id,
      nullif(k.hari_ke, 0) as hari_ke,
      (
        select count(*)::integer
        from public.se2026_revisit_reject_sumber t
        where t.level_6_full_code = k.kode_sls
      ) as jumlah_assignment,
      (
        select count(*)::integer
        from public.se2026_revisit_reject_sumber t
        join public.se2026_revisit_reject r
          on r.assignment_id = t.assignment_id
        where t.level_6_full_code = k.kode_sls
      ) as jumlah_ditandai,
      (
        select t.level_6_name
        from public.se2026_revisit_reject_sumber t
        where t.level_6_full_code = k.kode_sls
        limit 1
      ) as level_6_name
    from kode k
  )
  select
    h.kode_sls::text,
    h.level_6_name::text,
    sw.nm_kec::text,
    sw.nm_desa::text,
    sw.nm_sls::text,
    h.petugas_id,
    n.nama::text,
    rp.tim::text,
    h.hari_ke,
    h.jumlah_assignment,
    h.jumlah_ditandai
  from hitung h
  left join public.vw_fasih_wilayah_scope_base sw on sw.kode_wilayah = h.kode_sls
  left join public.vw_revisit_petugas_nama n on n.petugas_id = h.petugas_id
  left join public.se2026_revisit_petugas rp on rp.petugas_id = h.petugas_id
  where h.jumlah_assignment > 0
  order by sw.nm_kec nulls last, sw.nm_desa nulls last, h.kode_sls;
$$;

grant execute on function public.get_revisit_reject_sls() to authenticated;

create or replace function public.get_revisit_reject_detail(p_kode_sls text)
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
  revisit_petugas_id      uuid,
  revisit_nama            text,
  revisit_tim             text,
  hari_ke                 integer,
  updated_at              timestamptz,
  perlu_reject            boolean,
  alasan_reject           text,
  reject_oleh             text,
  reject_at               timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    t.assignment_id,
    t.assignment_status_alias::text,
    t.assignment_status_id,
    t.level_6_full_code::text,
    t.level_6_name::text,
    t.nama::text,
    t.alamat::text,
    t.no_bang::text,
    sw.nm_kec::text,
    sw.nm_desa::text,
    sw.nm_sls::text,
    a.petugas_id,
    n.nama::text,
    rp.tim::text,
    nullif(a.hari_ke, 0),
    t.updated_at,
    (r.assignment_id is not null),
    r.alasan,
    coalesce(nullif(trim(ru.name), ''), ru.email)::text,
    r.updated_at
  from public._revisit_me() me
  join public.se2026_revisit_reject_sumber t
    on t.level_6_full_code = p_kode_sls
  -- Satu baris alokasi saja (jadwal paling awal) agar tidak berlipat.
  left join lateral (
    select a2.petugas_id, a2.hari_ke
    from public.se2026_revisit_alokasi a2
    where a2.kode_sls = t.level_6_full_code
    order by a2.hari_ke
    limit 1
  ) a on true
  left join public.vw_fasih_wilayah_scope_base sw
    on sw.kode_wilayah = t.level_6_full_code
  left join public.vw_revisit_petugas_nama n on n.petugas_id = a.petugas_id
  left join public.se2026_revisit_petugas rp on rp.petugas_id = a.petugas_id
  left join public.se2026_revisit_reject r on r.assignment_id = t.assignment_id
  left join public.se2026_petugas rpg on rpg.id = r.flagged_by
  left join public.users ru on ru.id = rpg.user_id
  where me.petugas_id is not null
    and (me.role = 'admin' or a.petugas_id = me.petugas_id)
  order by t.nama, t.assignment_id;
$$;

grant execute on function public.get_revisit_reject_detail(text) to authenticated;

-- Fungsi lama yang menarik semua assignment sekaligus tidak dipakai lagi.
drop function if exists public.get_revisit_reject();
