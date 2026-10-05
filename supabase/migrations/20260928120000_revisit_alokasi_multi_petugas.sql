-- Alokasi revisit: satu SLS pada hari yang SAMA boleh dikerjakan lebih dari
-- satu petugas. Kunci menjadi (kode_sls, hari_ke, petugas_id).
--   * Menambahkan petugas lain pada hari yang sama = menambah jadwal,
--     bukan memindahkan.
--   * "Kunjungan terjadwal ke-n" dihitung dari HARI yang berbeda saja
--     (dense_rank), bukan dari jumlah baris, supaya dua petugas pada hari
--     yang sama tidak dianggap dua kunjungan.

alter table public.se2026_revisit_alokasi
  drop constraint if exists se2026_revisit_alokasi_pkey;
alter table public.se2026_revisit_alokasi
  add primary key (kode_sls, hari_ke, petugas_id);

create index if not exists idx_revisit_alokasi_petugas
  on public.se2026_revisit_alokasi (petugas_id);

-- ── Jadwal + penanda sudah/belum dikunjungi ─────────────────────────────────
create or replace view public.vw_revisit_jadwal as
select
  a.kode_sls,
  a.petugas_id,
  a.hari_ke,
  dense_rank() over (partition by a.kode_sls order by a.hari_ke) as urutan,
  lap.jumlah_laporan,
  lap.total_didata,
  lap.total_submit,
  lap.tanggal_terakhir,
  lap.status_terakhir,
  lap.belum_didata,
  (lap.jumlah_laporan >= dense_rank() over (
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
-- p_petugas_id null  -> lepas: satu hari tsb (semua petugas) bila p_hari_ke
--                       diisi, atau seluruh jadwal SLS bila p_hari_ke null.
-- p_lepas_petugas    -> true: hapus jadwal petugas ini saja.
create or replace function public.set_revisit_alokasi(
  p_kode_sls      text[],
  p_petugas_id    uuid,
  p_hari_ke       integer default null,
  p_lepas_petugas boolean default false
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

  if p_lepas_petugas and p_petugas_id is not null then
    delete from public.se2026_revisit_alokasi
    where kode_sls = any(p_kode_sls)
      and petugas_id = p_petugas_id
      and (p_hari_ke is null or hari_ke = v_hari);
    get diagnostics v_count = row_count;
    return jsonb_build_object('ok', true, 'count', v_count);
  end if;

  if p_petugas_id is null then
    delete from public.se2026_revisit_alokasi
    where kode_sls = any(p_kode_sls)
      and (p_hari_ke is null or hari_ke = v_hari);
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
  select k, p_petugas_id, v_hari, v_me.petugas_id, now()
  from unnest(p_kode_sls) as k
  where exists (select 1 from public.se2026_wilayah_tugas wt where wt.id = k)
  on conflict (kode_sls, hari_ke, petugas_id) do update
    set assigned_by = excluded.assigned_by,
        assigned_at = now();
  get diagnostics v_count = row_count;

  return jsonb_build_object('ok', true, 'count', v_count);
end;
$$;

grant execute on function public.set_revisit_alokasi(text[], uuid, integer, boolean) to authenticated;
drop function if exists public.set_revisit_alokasi(text[], uuid, integer);

-- ── Impor cepat ─────────────────────────────────────────────────────────────
create or replace function public._revisit_import_rows(p_rows jsonb)
returns table (kode_sls text, petugas_id uuid, hari_ke integer, tim text)
language sql
stable
security definer
set search_path = public
as $$
  select distinct on (x.kode_sls, coalesce(x.hari_ke, 0), x.petugas_id)
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
  order by x.kode_sls, coalesce(x.hari_ke, 0), x.petugas_id, x.ord desc;
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

  insert into public.se2026_revisit_alokasi as a
    (kode_sls, petugas_id, hari_ke, assigned_by, assigned_at)
  select i.kode_sls, i.petugas_id, i.hari_ke, v_me.petugas_id, now()
  from public._revisit_import_rows(p_rows) i
  on conflict (kode_sls, hari_ke, petugas_id) do update
    set assigned_by = excluded.assigned_by,
        assigned_at = now();

  return jsonb_build_object(
    'ok', true,
    'count', v_valid,
    'skipped', v_total - v_valid
  );
end;
$$;

grant execute on function public.import_revisit_alokasi(jsonb) to authenticated;

-- ── Progres per hari ke-: SLS dihitung unik walau dipegang 2 petugas ────────
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
      (array_agg(j.status_terakhir))[1]                  as status_terakhir,
      max(j.urutan)                                      as urutan,
      max(j.total_didata)                                as total_didata,
      max(j.total_submit)                                as total_submit,
      max(j.belum_didata)                                as belum_didata
    from j
    group by j.hari_ke, j.kode_sls
  )
  select
    nullif(per_sls.hari_ke, 0),
    count(*)::integer,
    count(*) filter (where per_sls.sudah)::integer,
    count(*) filter (where per_sls.status_terakhir = 'selesai')::integer,
    -- Nilai SLS dihitung sekali, pada hari jadwal pertamanya.
    coalesce(sum(per_sls.total_didata) filter (where per_sls.urutan = 1), 0)::integer,
    coalesce(sum(per_sls.total_submit) filter (where per_sls.urutan = 1), 0)::integer,
    coalesce(sum(per_sls.belum_didata) filter (where per_sls.urutan = 1), 0)::integer
  from per_sls
  group by per_sls.hari_ke
  order by per_sls.hari_ke;
$$;

grant execute on function public.get_revisit_progres_hari_ke() to authenticated;

-- ── Matriks petugas × hari ke- (SLS unik per petugas per hari) ──────────────
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
  ),
  per_sls as (
    select
      j.petugas_id,
      j.hari_ke,
      j.kode_sls,
      bool_or(j.sudah_dikunjungi)       as sudah,
      (array_agg(j.status_terakhir))[1] as status_terakhir,
      max(j.urutan)                     as urutan,
      max(j.total_didata)               as total_didata,
      max(j.total_submit)               as total_submit
    from j
    group by j.petugas_id, j.hari_ke, j.kode_sls
  )
  select
    per_sls.petugas_id,
    nullif(per_sls.hari_ke, 0),
    count(*)::integer,
    count(*) filter (where per_sls.sudah)::integer,
    count(*) filter (where per_sls.status_terakhir = 'selesai')::integer,
    coalesce(sum(per_sls.total_didata) filter (where per_sls.urutan = 1), 0)::integer,
    coalesce(sum(per_sls.total_submit) filter (where per_sls.urutan = 1), 0)::integer
  from per_sls
  group by per_sls.petugas_id, per_sls.hari_ke
  order by per_sls.petugas_id, per_sls.hari_ke;
$$;

grant execute on function public.get_revisit_matriks_hari() to authenticated;
