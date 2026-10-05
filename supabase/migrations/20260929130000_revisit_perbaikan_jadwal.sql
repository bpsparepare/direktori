-- Perbaikan lanjutan setelah aturan "1 petugas = 1 alokasi/hari":
--   1. set_revisit_alokasi menolak banyak SLS sekaligus bila hari > 0
--      (sebelumnya melanggar unique index dan gagal dengan error mentah).
--   2. get_revisit_reject_detail: cakupan petugas dicek atas SEMUA baris
--      alokasi SLS tsb. Sebelumnya hanya baris jadwal paling awal yang
--      dipakai, sehingga petugas kedua pada SLS yang sama tidak bisa
--      melihat isinya.

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

  -- Satu petugas hanya boleh satu SLS pada satu hari.
  if v_hari > 0 and coalesce(array_length(p_kode_sls, 1), 0) > 1 then
    return jsonb_build_object(
      'ok', false,
      'error', 'Satu petugas hanya boleh 1 SLS per hari. Pilih satu SLS, '
               'atau kosongkan hari ke- untuk mengalokasikan banyak SLS.'
    );
  end if;

  -- Lepas jadwal lama petugas ini pada hari yang sama (SLS berbeda).
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
  -- Tampilkan satu jadwal saja (paling awal) agar barisnya tidak berlipat,
  -- tetapi HAK AKSES dicek atas semua jadwal SLS ini.
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
    and (
      me.role = 'admin'
      or exists (
        select 1 from public.se2026_revisit_alokasi a3
        where a3.kode_sls = t.level_6_full_code
          and a3.petugas_id = me.petugas_id
      )
    )
  order by t.nama, t.assignment_id;
$$;

grant execute on function public.get_revisit_reject_detail(text) to authenticated;
