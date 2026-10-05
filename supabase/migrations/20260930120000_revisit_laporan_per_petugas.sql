-- Laporan revisit: satu laporan per PETUGAS per SLS per TANGGAL.
-- Sebelumnya kuncinya (kode_sls, tanggal) sehingga dua petugas yang bekerja
-- di SLS yang sama pada hari yang sama harus berbagi satu laporan.
--
-- Dampak perhitungan:
--   * Angka per petugas = laporan miliknya sendiri (tidak lagi dobel saat
--     satu SLS dikerjakan beberapa orang).
--   * Angka per SLS = jumlah laporan semua petugas di SLS itu.

alter table public.se2026_revisit_laporan
  drop constraint if exists se2026_revisit_laporan_kode_sls_tanggal_key;

create unique index if not exists uq_revisit_laporan_sls_tanggal_petugas
  on public.se2026_revisit_laporan (kode_sls, tanggal, petugas_id);

create index if not exists idx_revisit_laporan_sls_petugas
  on public.se2026_revisit_laporan (kode_sls, petugas_id);

-- ── Jadwal: angka milik petugas + angka seluruh SLS ─────────────────────────
-- Susunan kolom berubah (ada kolom baru di tengah), jadi view harus di-drop
-- dulu; CREATE OR REPLACE VIEW tidak bisa menyisipkan/mengganti nama kolom.
drop view if exists public.vw_revisit_jadwal;
create view public.vw_revisit_jadwal as
select
  a.kode_sls,
  a.petugas_id,
  a.hari_ke,
  -- Urutan hari jadwal MILIK PETUGAS INI pada SLS tsb.
  row_number() over (
    partition by a.kode_sls, a.petugas_id order by a.hari_ke
  ) as urutan,
  -- Angka milik petugas ini saja (dipakai rekap per petugas).
  saya.jumlah_laporan,
  saya.total_didata,
  saya.total_submit,
  saya.tanggal_terakhir,
  saya.status_terakhir,
  saya.belum_didata,
  -- Angka seluruh SLS (semua petugas) — dipakai progres SLS.
  sls.jumlah_laporan     as sls_jumlah_laporan,
  sls.total_didata       as sls_total_didata,
  sls.total_submit       as sls_total_submit,
  sls.tanggal_terakhir   as sls_tanggal_terakhir,
  sls.status_terakhir    as sls_status_terakhir,
  sls.belum_didata       as sls_belum_didata,
  (saya.jumlah_laporan >= row_number() over (
     partition by a.kode_sls, a.petugas_id order by a.hari_ke
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

-- ── Simpan laporan: milik petugas yang login ────────────────────────────────
drop function if exists public.upsert_revisit_laporan(
  text, date, text, integer, text, integer, integer);
create function public.upsert_revisit_laporan(
  p_kode_sls      text,
  p_tanggal       date,
  p_status        text,
  p_jumlah_dicek  integer default null,
  p_catatan       text default null,
  p_jumlah_belum  integer default null,
  p_jumlah_submit integer default null
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
  if v_me.petugas_id is null then
    return jsonb_build_object('ok', false, 'error', 'Petugas tidak aktif');
  end if;

  if not exists (
    select 1 from public.se2026_revisit_alokasi a
    where a.kode_sls = p_kode_sls and a.petugas_id = v_me.petugas_id
  ) then
    return jsonb_build_object('ok', false, 'error', 'SLS ini bukan alokasi revisit Anda');
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

  -- Satu laporan per petugas per SLS per tanggal.
  select l.id into v_id
  from public.se2026_revisit_laporan l
  where l.kode_sls = p_kode_sls
    and l.tanggal = p_tanggal
    and l.petugas_id = v_me.petugas_id;

  if v_id is null then
    insert into public.se2026_revisit_laporan
      (kode_sls, petugas_id, tanggal, status, jumlah_dicek, jumlah_submit,
       jumlah_belum_didata, catatan)
    values
      (p_kode_sls, v_me.petugas_id, p_tanggal, p_status, p_jumlah_dicek,
       p_jumlah_submit, p_jumlah_belum, nullif(trim(p_catatan), ''))
    returning id into v_id;
  else
    update public.se2026_revisit_laporan
       set status              = p_status,
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
  text, date, text, integer, text, integer, integer) to authenticated;

-- ── Daftar laporan: + filter "punya saya" untuk form laporan ────────────────
drop function if exists public.get_revisit_laporan(date, date, uuid, text);
create function public.get_revisit_laporan(
  p_dari        date,
  p_sampai      date,
  p_petugas_id  uuid default null,
  p_kode_sls    text default null,
  p_milik_saya  boolean default false
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
  -- Hari jadwal petugas pemilik laporan pada SLS tsb.
  left join lateral (
    select min(a.hari_ke) as hari_ke
    from public.se2026_revisit_alokasi a
    where a.kode_sls = l.kode_sls and a.petugas_id = l.petugas_id
  ) jad on true
  where me.petugas_id is not null
    and (me.role = 'admin' or l.petugas_id = me.petugas_id)
    and (not p_milik_saya or l.petugas_id = me.petugas_id)
    and (p_petugas_id is null or l.petugas_id = p_petugas_id)
    and (p_kode_sls is null or l.kode_sls = p_kode_sls)
  order by l.tanggal desc, n.nama, l.kode_sls, l.id;
$$;

grant execute on function public.get_revisit_laporan(date, date, uuid, text, boolean) to authenticated;

-- ── Tugas saya: angka SLS (gabungan) + status kunjungan milik sendiri ───────
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
  laporan_saya     integer
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
    j.jumlah_laporan
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

-- ── Rekap per petugas: pakai angka MILIK PETUGAS (tidak dobel) ──────────────
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
      max(j.jumlah_laporan)   as n_lap,
      max(j.total_didata)     as didata,
      max(j.total_submit)     as submitted,
      max(j.tanggal_terakhir) as tgl_terakhir,
      max(j.sls_belum_didata) as sisa,
      (array_agg(j.status_terakhir))[1] as status_terakhir,
      (
        select count(*)::integer
        from public.se2026_revisit_laporan l
        join public.se2026_revisit_foto f on f.laporan_id = l.id
        where l.kode_sls = j.kode_sls and l.petugas_id = j.petugas_id
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

-- ── Progres per hari ke-: jumlahkan angka tiap petugas (sekali per petugas) ─
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
      bool_or(j.sudah_dikunjungi)            as sudah,
      (array_agg(j.sls_status_terakhir))[1]  as status_terakhir,
      -- Angka petugas dijumlahkan sekali, pada hari jadwal pertamanya.
      coalesce(sum(j.total_didata) filter (where j.urutan = 1), 0) as didata,
      coalesce(sum(j.total_submit) filter (where j.urutan = 1), 0) as submitted,
      max(j.sls_belum_didata)                as sisa,
      min(j.urutan)                          as urutan_sls
    from j
    group by j.hari_ke, j.kode_sls
  )
  select
    nullif(per_sls.hari_ke, 0),
    count(*)::integer,
    count(*) filter (where per_sls.sudah)::integer,
    count(*) filter (where per_sls.status_terakhir = 'selesai')::integer,
    coalesce(sum(per_sls.didata), 0)::integer,
    coalesce(sum(per_sls.submitted), 0)::integer,
    coalesce(sum(per_sls.sisa) filter (where per_sls.urutan_sls = 1), 0)::integer
  from per_sls
  group by per_sls.hari_ke
  order by per_sls.hari_ke;
$$;

grant execute on function public.get_revisit_progres_hari_ke() to authenticated;

-- ── Matriks: angka milik petugas pada hari tsb ──────────────────────────────
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
    count(*) filter (where j.status_terakhir = 'selesai')::integer,
    coalesce(sum(j.total_didata) filter (where j.urutan = 1), 0)::integer,
    coalesce(sum(j.total_submit) filter (where j.urutan = 1), 0)::integer
  from j
  group by j.petugas_id, j.hari_ke
  order by j.petugas_id, j.hari_ke;
$$;

grant execute on function public.get_revisit_matriks_hari() to authenticated;
