-- Impor Cepat alokasi: mode GANTI.
--   p_ganti = false (default) -> baris impor menambah petugas pada
--                                (SLS, hari) tsb.
--   p_ganti = true            -> petugas lain pada (SLS, hari) yang diimpor
--                                dilepas lebih dulu, sehingga jadwalnya
--                                bertukar.
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
  v_ganti integer := 0;
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
    'diganti', v_ganti,
    'dilepas', v_lepas
  );
end;
$$;

grant execute on function public.import_revisit_alokasi(jsonb, boolean) to authenticated;

-- Hindari ambiguitas: hanya versi dua argumen yang dipakai.
drop function if exists public.import_revisit_alokasi(jsonb);
