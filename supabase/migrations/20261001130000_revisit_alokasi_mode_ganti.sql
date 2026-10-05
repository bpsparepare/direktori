-- Alokasi revisit: mode GANTI (tukar petugas) di samping mode tambah.
--   p_ganti = false (default) -> menambah petugas pada (SLS, hari) tsb.
--   p_ganti = true            -> petugas lain pada (SLS, hari) itu dilepas
--                                lebih dulu, sehingga jadwal itu bertukar.
-- Aturan lain tidak berubah: satu petugas tetap hanya boleh satu SLS per
-- hari, jadi jadwal lama petugas baru pada hari itu juga dilepas.
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
  v_ganti integer := 0;
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

  if v_hari > 0 and coalesce(array_length(p_kode_sls, 1), 0) > 1 then
    return jsonb_build_object(
      'ok', false,
      'error', 'Satu petugas hanya boleh 1 SLS per hari. Pilih satu SLS, '
               'atau kosongkan hari ke- untuk mengalokasikan banyak SLS.'
    );
  end if;

  -- Mode ganti: lepas petugas lain pada (SLS, hari) yang sama.
  if p_ganti then
    delete from public.se2026_revisit_alokasi
    where kode_sls = any(p_kode_sls)
      and hari_ke = v_hari
      and petugas_id <> p_petugas_id;
    get diagnostics v_lepas = row_count;
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

  return jsonb_build_object(
    'ok', true,
    'count', v_count,
    'diganti', v_ganti,
    'dilepas', v_lepas
  );
end;
$$;

grant execute on function public.set_revisit_alokasi(text[], uuid, integer, boolean, boolean) to authenticated;

-- Hindari ambiguitas pemanggilan: hanya versi 5 argumen yang dipakai.
drop function if exists public.set_revisit_alokasi(text[], uuid, integer, boolean);
