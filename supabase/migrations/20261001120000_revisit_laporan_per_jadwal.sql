-- Laporan revisit terikat ke JADWAL: satu laporan per (SLS, petugas,
-- hari ke-). Dua jadwal pada SLS yang sama (mis. H2 dan H5) punya laporan
-- masing-masing, walau diisi pada tanggal yang sama. Tanggal tetap dicatat
-- sebagai kapan kunjungan itu dikerjakan.

alter table public.se2026_revisit_laporan
  add column if not exists hari_ke integer not null default 0;

-- Backfill: laporan ke-n (urut tanggal) dipasangkan ke jadwal ke-n petugas
-- itu pada SLS tsb. Laporan lama yang tidak kebagian jadwal diberi nomor
-- khusus 900+n (di luar rentang jadwal 0..366) supaya tidak bentrok; laporan
-- tsb tetap terhitung pada total SLS/petugas dan tetap bisa diedit.
with urut as (
  select
    l.id,
    l.kode_sls,
    l.petugas_id,
    row_number() over (
      partition by l.kode_sls, l.petugas_id order by l.tanggal, l.created_at
    ) as rn
  from public.se2026_revisit_laporan l
),
jadwal as (
  select
    a.kode_sls,
    a.petugas_id,
    a.hari_ke,
    row_number() over (
      partition by a.kode_sls, a.petugas_id order by a.hari_ke
    ) as rn
  from public.se2026_revisit_alokasi a
)
update public.se2026_revisit_laporan l
   set hari_ke = coalesce(
         j.hari_ke,
         case when u.rn = 1 then 0 else 900 + u.rn end
       )
from urut u
left join jadwal j
  on j.kode_sls = u.kode_sls and j.petugas_id = u.petugas_id and j.rn = u.rn
where l.id = u.id;

drop index if exists public.uq_revisit_laporan_sls_tanggal_petugas;

create unique index if not exists uq_revisit_laporan_sls_petugas_hari
  on public.se2026_revisit_laporan (kode_sls, petugas_id, hari_ke);

-- ── Jadwal: laporan jadwal ini + angka petugas + angka SLS ──────────────────
drop view if exists public.vw_revisit_jadwal;
create view public.vw_revisit_jadwal as
select
  a.kode_sls,
  a.petugas_id,
  a.hari_ke,
  -- Laporan untuk jadwal ini (satu-satunya).
  lap.id                 as laporan_id,
  lap.tanggal            as tanggal,
  lap.status             as status,
  lap.jumlah_dicek       as didata,
  lap.jumlah_submit      as submit_,
  lap.jumlah_belum_didata as belum_didata_hari,
  (lap.id is not null)   as sudah_dikunjungi,
  -- Semua laporan petugas ini di SLS tsb.
  saya.jumlah_laporan,
  saya.total_didata,
  saya.total_submit,
  saya.tanggal_terakhir,
  saya.status_terakhir,
  saya.belum_didata,
  -- Semua laporan (semua petugas) di SLS tsb.
  sls.jumlah_laporan     as sls_jumlah_laporan,
  sls.total_didata       as sls_total_didata,
  sls.total_submit       as sls_total_submit,
  sls.tanggal_terakhir   as sls_tanggal_terakhir,
  sls.status_terakhir    as sls_status_terakhir,
  sls.belum_didata       as sls_belum_didata
from public.se2026_revisit_alokasi a
left join public.se2026_revisit_laporan lap
  on lap.kode_sls = a.kode_sls
 and lap.petugas_id = a.petugas_id
 and lap.hari_ke = a.hari_ke
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
  where l.kode_sls = a.kode_sls and l.petugas_id = a.petugas_id
) saya on true
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
) sls on true;

revoke all on public.vw_revisit_jadwal from anon, authenticated;

-- ── Simpan laporan: per jadwal (SLS + petugas + hari ke-) ───────────────────
drop function if exists public.upsert_revisit_laporan(
  text, date, text, integer, text, integer, integer);
create function public.upsert_revisit_laporan(
  p_kode_sls      text,
  p_tanggal       date,
  p_status        text,
  p_jumlah_dicek  integer default null,
  p_catatan       text default null,
  p_jumlah_belum  integer default null,
  p_jumlah_submit integer default null,
  p_hari_ke       integer default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_me   record;
  v_id   uuid;
  v_hari integer := coalesce(p_hari_ke, 0);
begin
  select * into v_me from public._revisit_me();
  if v_me.petugas_id is null then
    return jsonb_build_object('ok', false, 'error', 'Petugas tidak aktif');
  end if;

  -- Laporan hanya untuk jadwal yang dialokasikan ke petugas ini. Laporan
  -- lama yang sudah terlanjur ada (mis. hasil backfill) tetap boleh diedit.
  if not exists (
    select 1 from public.se2026_revisit_alokasi a
    where a.kode_sls = p_kode_sls
      and a.petugas_id = v_me.petugas_id
      and a.hari_ke = v_hari
  ) and not exists (
    select 1 from public.se2026_revisit_laporan l
    where l.kode_sls = p_kode_sls
      and l.petugas_id = v_me.petugas_id
      and l.hari_ke = v_hari
  ) then
    return jsonb_build_object(
      'ok', false,
      'error', 'Jadwal ini bukan alokasi revisit Anda'
    );
  end if;

  if p_status is null
     or p_jumlah_dicek is null
     or p_jumlah_belum is null
     or p_jumlah_submit is null
     or nullif(trim(p_catatan), '') is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'Status, jumlah didata, jumlah submit, potensi belum didata, dan catatan wajib diisi'
    );
  end if;

  if p_tanggal is null
     or p_tanggal > (now() at time zone 'Asia/Jayapura')::date then
    return jsonb_build_object('ok', false, 'error', 'Tanggal tidak boleh melewati hari ini');
  end if;

  select l.id into v_id
  from public.se2026_revisit_laporan l
  where l.kode_sls = p_kode_sls
    and l.petugas_id = v_me.petugas_id
    and l.hari_ke = v_hari;

  if v_id is null then
    insert into public.se2026_revisit_laporan
      (kode_sls, petugas_id, hari_ke, tanggal, status, jumlah_dicek,
       jumlah_submit, jumlah_belum_didata, catatan)
    values
      (p_kode_sls, v_me.petugas_id, v_hari, p_tanggal, p_status,
       p_jumlah_dicek, p_jumlah_submit, p_jumlah_belum,
       nullif(trim(p_catatan), ''))
    returning id into v_id;
  else
    update public.se2026_revisit_laporan
       set tanggal             = p_tanggal,
           status              = p_status,
           jumlah_dicek        = p_jumlah_dicek,
           jumlah_submit       = p_jumlah_submit,
           jumlah_belum_didata = p_jumlah_belum,
           catatan             = nullif(trim(p_catatan), ''),
           updated_at          = now()
     where id = v_id;
  end if;

  return jsonb_build_object('ok', true, 'id', v_id);
end;
$$;

grant execute on function public.upsert_revisit_laporan(
  text, date, text, integer, text, integer, integer, integer) to authenticated;

-- ── Daftar laporan: hari_ke dari laporan + filter jadwal ────────────────────
drop function if exists public.get_revisit_laporan(date, date, uuid, text, boolean);
create function public.get_revisit_laporan(
  p_dari       date,
  p_sampai     date,
  p_petugas_id uuid default null,
  p_kode_sls   text default null,
  p_milik_saya boolean default false,
  p_hari_ke    integer default null
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
    nullif(l.hari_ke, 0),
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
  where me.petugas_id is not null
    and (me.role = 'admin' or l.petugas_id = me.petugas_id)
    and (not p_milik_saya or l.petugas_id = me.petugas_id)
    and (p_petugas_id is null or l.petugas_id = p_petugas_id)
    and (p_kode_sls is null or l.kode_sls = p_kode_sls)
    and (p_hari_ke is null or l.hari_ke = p_hari_ke)
  order by l.tanggal desc, n.nama, l.kode_sls, l.hari_ke, l.id;
$$;

grant execute on function public.get_revisit_laporan(date, date, uuid, text, boolean, integer) to authenticated;

-- ── Tugas saya: satu baris per jadwal + laporan jadwal itu ──────────────────
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
  sudah_dikunjungi boolean,
  laporan_saya     integer,
  -- Laporan untuk jadwal (hari ke-) ini saja.
  status_hari      text,
  tanggal_hari     date,
  didata_hari      integer,
  submit_hari      integer
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
    j.sls_jumlah_laporan,
    j.sls_status_terakhir,
    j.sls_tanggal_terakhir,
    j.sls_total_didata,
    j.sls_total_submit,
    j.sls_belum_didata,
    j.sudah_dikunjungi,
    j.jumlah_laporan,
    j.status,
    j.tanggal,
    j.didata,
    j.submit_
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

-- ── Progres per hari ke-: angka laporan jadwal hari itu ─────────────────────
create or replace function public.get_revisit_progres_hari_ke()
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
  ),
  per_sls as (
    select
      j.hari_ke,
      j.kode_sls,
      bool_or(j.sudah_dikunjungi)                        as sudah,
      bool_or(j.status = 'selesai')                      as selesai,
      coalesce(sum(j.didata), 0)                         as didata,
      coalesce(sum(j.submit_), 0)                        as submitted,
      max(j.sls_belum_didata)                            as sisa,
      -- Sisa potensi SLS dihitung sekali, pada hari jadwal terkecil.
      (j.hari_ke = min(j.hari_ke) over (partition by j.kode_sls)) as hari_pertama
    from j
    group by j.hari_ke, j.kode_sls
  )
  select
    nullif(per_sls.hari_ke, 0),
    count(*)::integer,
    count(*) filter (where per_sls.sudah)::integer,
    count(*) filter (where per_sls.selesai)::integer,
    coalesce(sum(per_sls.didata), 0)::integer,
    coalesce(sum(per_sls.submitted), 0)::integer,
    coalesce(sum(per_sls.sisa) filter (where per_sls.hari_pertama), 0)::integer
  from per_sls
  group by per_sls.hari_ke
  order by per_sls.hari_ke;
$$;

grant execute on function public.get_revisit_progres_hari_ke() to authenticated;

-- ── Matriks: angka laporan jadwal petugas pada hari tsb ─────────────────────
create or replace function public.get_revisit_matriks_hari()
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
    count(*) filter (where j.status = 'selesai')::integer,
    coalesce(sum(j.didata), 0)::integer,
    coalesce(sum(j.submit_), 0)::integer
  from j
  group by j.petugas_id, j.hari_ke
  order by j.petugas_id, j.hari_ke;
$$;

grant execute on function public.get_revisit_matriks_hari() to authenticated;
