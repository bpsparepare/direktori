-- Alokasi revisit: pemilik melekat pada (kode_sls, hari_ke), BUKAN pada SLS.
-- Satu SLS boleh dikerjakan petugas berbeda pada hari berbeda, mis. H2 oleh
-- Hajrah dan H5 oleh Siti. Aturan lama "satu SLS satu petugas" dicabut:
-- mengalokasikan hari baru = menambah jadwal, bukan memindahkan SLS.

-- ── Alokasikan / lepas (tanpa penyamaan petugas antar hari) ─────────────────
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

-- ── Impor cepat (tanpa penyamaan petugas antar hari) ────────────────────────
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

-- ── Daftar alokasi: satu baris per SLS + jadwal (hari + petugasnya) ─────────
drop function if exists public.get_revisit_alokasi();
create function public.get_revisit_alokasi()
returns table (
  kode_sls text,
  nm_kec   text,
  nm_desa  text,
  nm_sls   text,
  pml_nama text,
  ppl_nama text,
  -- [{"hari_ke":2,"petugas_id":"...","nama":"Hajrah","tim":"1"}, ...]
  jadwal   jsonb
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
    coalesce(ag.jadwal, '[]'::jsonb)
  from public.vw_fasih_wilayah_scope_base sw
  left join lateral (
    select jsonb_agg(
             jsonb_build_object(
               'hari_ke', a.hari_ke,
               'petugas_id', a.petugas_id,
               'nama', n.nama,
               'tim', rp.tim
             ) order by a.hari_ke
           ) as jadwal
    from public.se2026_revisit_alokasi a
    left join public.vw_revisit_petugas_nama n on n.petugas_id = a.petugas_id
    left join public.se2026_revisit_petugas rp on rp.petugas_id = a.petugas_id
    where a.kode_sls = sw.kode_wilayah
  ) ag on true
  order by sw.nm_kec nulls last, sw.nm_desa nulls last, sw.kode_wilayah;
end;
$$;

grant execute on function public.get_revisit_alokasi() to authenticated;
