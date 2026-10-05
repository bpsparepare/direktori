-- Aturan baru: SATU PETUGAS hanya boleh punya SATU alokasi per hari.
-- (hari_ke = 0 "belum ditentukan" dikecualikan, boleh berapa pun.)
--
-- Konsekuensi: memberi petugas jadwal di hari yang sudah terisi = MENGGANTI
-- jadwal lamanya pada hari itu, bukan menambah. Satu SLS pada hari yang sama
-- tetap boleh dikerjakan beberapa petugas berbeda.

-- Bersihkan sisa data lama: sisakan satu baris terbaru per (petugas, hari).
delete from public.se2026_revisit_alokasi a
using (
  select kode_sls, petugas_id, hari_ke,
         row_number() over (
           partition by petugas_id, hari_ke
           order by assigned_at desc, kode_sls
         ) as rn
  from public.se2026_revisit_alokasi
  where hari_ke > 0
) d
where a.kode_sls = d.kode_sls
  and a.petugas_id = d.petugas_id
  and a.hari_ke = d.hari_ke
  and d.rn > 1;

create unique index if not exists uq_revisit_alokasi_petugas_hari
  on public.se2026_revisit_alokasi (petugas_id, hari_ke)
  where hari_ke > 0;

-- ── Alokasikan / lepas ──────────────────────────────────────────────────────
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
  v_me     record;
  v_count  integer;
  v_ganti  integer := 0;
  v_hari   integer := coalesce(p_hari_ke, 0);
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

  -- Satu petugas satu alokasi per hari: lepas jadwal lamanya di hari ini.
  if v_hari > 0 then
    delete from public.se2026_revisit_alokasi
    where petugas_id = p_petugas_id
      and hari_ke = v_hari
      and not (kode_sls = any(p_kode_sls));
    get diagnostics v_ganti = row_count;
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

  return jsonb_build_object('ok', true, 'count', v_count, 'diganti', v_ganti);
end;
$$;

grant execute on function public.set_revisit_alokasi(text[], uuid, integer, boolean) to authenticated;

-- ── Impor cepat ─────────────────────────────────────────────────────────────
-- Satu baris per (petugas, hari) bila hari > 0 (baris terakhir menang);
-- untuk hari 0 dedup per (SLS, petugas).
create or replace function public._revisit_import_rows(p_rows jsonb)
returns table (kode_sls text, petugas_id uuid, hari_ke integer, tim text)
language sql
stable
security definer
set search_path = public
as $$
  select t.kode_sls, t.petugas_id, t.hari_ke, t.tim
  from (
    select
      x.kode_sls,
      x.petugas_id,
      coalesce(x.hari_ke, 0) as hari_ke,
      nullif(trim(x.tim), '') as tim,
      row_number() over (
        partition by case
          when coalesce(x.hari_ke, 0) > 0
            then x.petugas_id::text || '|' || coalesce(x.hari_ke, 0)::text
          else x.kode_sls || '|' || x.petugas_id::text
        end
        order by x.ord desc
      ) as rn
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
  ) t
  where t.rn = 1;
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
  v_ganti integer := 0;
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

  -- Satu petugas satu alokasi per hari: lepas jadwal lama pada hari yang
  -- diimpor bila SLS-nya berbeda.
  delete from public.se2026_revisit_alokasi a
  where a.hari_ke > 0
    and exists (
      select 1 from public._revisit_import_rows(p_rows) i
      where i.petugas_id = a.petugas_id and i.hari_ke = a.hari_ke
    )
    and not exists (
      select 1 from public._revisit_import_rows(p_rows) i
      where i.petugas_id = a.petugas_id
        and i.hari_ke = a.hari_ke
        and i.kode_sls = a.kode_sls
    );
  get diagnostics v_ganti = row_count;

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
    'diganti', v_ganti
  );
end;
$$;

grant execute on function public.import_revisit_alokasi(jsonb) to authenticated;
