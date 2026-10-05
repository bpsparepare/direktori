-- Aturan '1 petugas = 1 SLS per hari' (mig 20260929120000) DICABUT:
-- satu petugas kini boleh dijadwalkan ke beberapa SLS pada hari yang sama.
-- Memberi SLS baru pada hari yang sudah terisi = MENAMBAH, bukan mengganti
-- jadwal lama. Mode ganti (tukar petugas lain pada SLS+hari) tetap ada.

drop index if exists public.uq_revisit_alokasi_petugas_hari;

-- ── Alokasikan / lepas ──────────────────────────────────────────────────────
create or replace function public.set_revisit_alokasi(
  p_kode_sls      text[],
  p_petugas_id    uuid,
  p_hari_ke       integer default null,
  p_lepas_petugas boolean default false,
  p_ganti         boolean default false
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
  v_lepas integer := 0;
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

  -- Mode ganti: lepas petugas lain pada (SLS, hari) yang sama.
  if p_ganti then
    delete from public.se2026_revisit_alokasi
    where kode_sls = any(p_kode_sls)
      and hari_ke = v_hari
      and petugas_id <> p_petugas_id;
    get diagnostics v_lepas = row_count;
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

  return jsonb_build_object(
    'ok', true,
    'count', v_count,
    'diganti', 0,
    'dilepas', v_lepas
  );
end;
$$;

grant execute on function public.set_revisit_alokasi(text[], uuid, integer, boolean, boolean) to authenticated;

-- ── Impor cepat ─────────────────────────────────────────────────────────────
-- Dedup per (SLS, hari, petugas) saja (baris terakhir menang), sehingga satu
-- petugas boleh punya beberapa baris SLS pada hari yang sama.
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

create or replace function public.import_revisit_alokasi(
  p_rows  jsonb,
  p_ganti boolean default false
)
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
  v_lepas integer := 0;
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

  -- Mode ganti: lepas petugas LAIN pada (SLS, hari) yang diimpor.
  if p_ganti then
    delete from public.se2026_revisit_alokasi a
    where exists (
      select 1 from public._revisit_import_rows(p_rows) i
      where i.kode_sls = a.kode_sls
        and i.hari_ke = a.hari_ke
        and i.petugas_id <> a.petugas_id
    );
    get diagnostics v_lepas = row_count;
  end if;

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
    'skipped', v_total - v_valid,
    'diganti', 0,
    'dilepas', v_lepas
  );
end;
$$;

grant execute on function public.import_revisit_alokasi(jsonb, boolean) to authenticated;
