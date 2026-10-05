-- Revisit: variabel "Jumlah Usaha/Keluarga Submit" (wajib) per laporan,
-- + ringkasan per SLS untuk petugas tertentu (halaman detail petugas admin).

alter table public.se2026_revisit_laporan
  add column if not exists jumlah_submit integer
    check (jumlah_submit is null or jumlah_submit >= 0);

-- ── Simpan laporan: + p_jumlah_submit (wajib) ────────────────────────────────
drop function if exists public.upsert_revisit_laporan(text, date, text, integer, text, integer);
create function public.upsert_revisit_laporan(
  p_kode_sls     text,
  p_tanggal      date,
  p_status       text,
  p_jumlah_dicek integer default null,
  p_catatan      text default null,
  p_jumlah_belum integer default null,
  p_jumlah_submit integer default null
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

  -- Semua isian wajib (foto dicek di aplikasi karena diunggah setelahnya).
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

  -- Batas atas memakai zona paling timur Indonesia (lihat 20260919140000).
  if p_tanggal is null
     or p_tanggal > (now() at time zone 'Asia/Jayapura')::date then
    return jsonb_build_object('ok', false, 'error', 'Tanggal tidak boleh melewati hari ini');
  end if;

  select l.id, l.petugas_id into v_id, v_owner
  from public.se2026_revisit_laporan l
  where l.kode_sls = p_kode_sls and l.tanggal = p_tanggal;

  if v_id is not null and v_owner <> v_me.petugas_id then
    return jsonb_build_object('ok', false, 'error', 'Laporan tanggal ini sudah diisi petugas lain');
  end if;

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

grant execute on function public.upsert_revisit_laporan(text, date, text, integer, text, integer, integer) to authenticated;

-- ── Laporan: + jumlah_submit ─────────────────────────────────────────────────
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
    a.hari_ke,
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
  left join public.se2026_revisit_alokasi a on a.kode_sls = l.kode_sls
  where me.petugas_id is not null
    and (me.role = 'admin' or l.petugas_id = me.petugas_id)
    and (p_petugas_id is null or l.petugas_id = p_petugas_id)
    and (p_kode_sls is null or l.kode_sls = p_kode_sls)
  order by l.tanggal desc, n.nama, l.kode_sls, l.id;
$$;

grant execute on function public.get_revisit_laporan(date, date, uuid, text) to authenticated;

-- ── Ringkasan per SLS: + total_submit, + p_petugas_id (admin) ────────────────
-- Tanpa parameter = SLS alokasi pengguna sendiri (Tugas Saya). Dengan
-- p_petugas_id = SLS alokasi petugas tsb (hanya admin / dirinya sendiri).
drop function if exists public.get_revisit_tugas_saya();
drop function if exists public.get_revisit_tugas_saya(uuid);
create function public.get_revisit_tugas_saya(p_petugas_id uuid default null)
returns table (
  kode_sls            text,
  nm_kec              text,
  nm_desa             text,
  nm_sls              text,
  hari_ke             integer,
  jumlah_laporan      integer,
  status_terakhir     text,
  tanggal_terakhir    date,
  total_didata        integer,
  total_submit        integer,
  belum_didata        integer
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
    agg.jumlah_laporan,
    last.status,
    last.tanggal,
    agg.total_didata,
    agg.total_submit,
    last.jumlah_belum_didata
  from public._revisit_me() me
  join public.se2026_revisit_alokasi a
    on a.petugas_id = coalesce(p_petugas_id, me.petugas_id)
  left join public.vw_fasih_wilayah_scope_base sw on sw.kode_wilayah = a.kode_sls
  left join lateral (
    select count(*)::integer as jumlah_laporan,
           coalesce(sum(l.jumlah_dicek), 0)::integer as total_didata,
           coalesce(sum(l.jumlah_submit), 0)::integer as total_submit
    from public.se2026_revisit_laporan l
    where l.kode_sls = a.kode_sls
  ) agg on true
  left join lateral (
    select l.status, l.tanggal, l.jumlah_belum_didata
    from public.se2026_revisit_laporan l
    where l.kode_sls = a.kode_sls
    order by l.tanggal desc, l.updated_at desc
    limit 1
  ) last on true
  where me.petugas_id is not null
    -- Petugas lain hanya boleh dilihat admin.
    and (p_petugas_id is null or p_petugas_id = me.petugas_id or me.role = 'admin')
  order by a.hari_ke nulls last, sw.nm_kec nulls last, sw.nm_desa nulls last,
           a.kode_sls;
$$;

grant execute on function public.get_revisit_tugas_saya(uuid) to authenticated;

-- ── Progres harian: + jumlah_submit ──────────────────────────────────────────
drop function if exists public.get_revisit_progres_harian(uuid);
create function public.get_revisit_progres_harian(
  p_petugas_id uuid default null
)
returns table (
  tanggal            date,
  jumlah_laporan     integer,
  jumlah_didata      integer,
  jumlah_submit      integer,
  jumlah_petugas     integer,
  jumlah_foto        integer,
  sisa_belum_didata  integer
)
language sql
stable
security definer
set search_path = public
as $$
  with lap as (
    select l.*
    from public._revisit_me() me
    join public.se2026_revisit_laporan l
      on me.role = 'admin' or l.petugas_id = me.petugas_id
    where me.petugas_id is not null
      and (p_petugas_id is null or l.petugas_id = p_petugas_id)
  ),
  harian as (
    select
      lap.tanggal,
      count(*)::integer as jumlah_laporan,
      coalesce(sum(lap.jumlah_dicek), 0)::integer as jumlah_didata,
      coalesce(sum(lap.jumlah_submit), 0)::integer as jumlah_submit,
      count(distinct lap.petugas_id)::integer as jumlah_petugas,
      coalesce(sum((
        select count(*) from public.se2026_revisit_foto f
        where f.laporan_id = lap.id
      )), 0)::integer as jumlah_foto
    from lap
    group by lap.tanggal
  )
  select
    h.tanggal,
    h.jumlah_laporan,
    h.jumlah_didata,
    h.jumlah_submit,
    h.jumlah_petugas,
    h.jumlah_foto,
    coalesce((
      select sum(x.jumlah_belum_didata)
      from (
        select distinct on (l2.kode_sls) l2.jumlah_belum_didata
        from lap l2
        where l2.tanggal <= h.tanggal
        order by l2.kode_sls, l2.tanggal desc, l2.updated_at desc
      ) x
    ), 0)::integer
  from harian h
  order by h.tanggal;
$$;

grant execute on function public.get_revisit_progres_harian(uuid) to authenticated;
