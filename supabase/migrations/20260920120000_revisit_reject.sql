-- Fitur "Reject" pada menu Revisit: menandai assignment mana yang perlu
-- di-reject. Polanya sama dengan fitur Submit (se2026_tindak_lanjut), dengan
-- dua perbedaan:
--   1. Tabel sumber TERPISAH (se2026_revisit_reject_sumber), diisi ulang
--      penuh oleh ekstensi browser.
--   2. Hak baca/tandai mengikuti ALOKASI REVISIT (se2026_revisit_alokasi),
--      bukan se2026_wilayah_tugas. Admin bebas.
-- Tanda reject disimpan di tabel terpisah agar tidak hilang saat impor ulang.

-- ── Tabel sumber (diisi ekstensi; idempoten) ────────────────────────────────
create table if not exists public.se2026_revisit_reject_sumber (
  assignment_id            text primary key,
  assignment_status_alias  text,
  assignment_status_id     integer,
  level_6_full_code        text,
  level_6_name             text,
  nama                     text,
  alamat                   text,
  no_bang                  text,
  updated_at               timestamptz not null default now()
);

create index if not exists idx_revisit_reject_level6
  on public.se2026_revisit_reject_sumber (level_6_full_code);
create index if not exists idx_revisit_reject_status
  on public.se2026_revisit_reject_sumber (assignment_status_alias);

alter table public.se2026_revisit_reject_sumber enable row level security;

-- ── Tanda "perlu di-reject" (tidak tersentuh impor) ─────────────────────────
create table if not exists public.se2026_revisit_reject (
  assignment_id text primary key,
  alasan        text,
  flagged_by    uuid,          -- se2026_petugas.id
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

alter table public.se2026_revisit_reject enable row level security;

-- ── Helper: scope = alokasi revisit ─────────────────────────────────────────
-- Mengembalikan petugas_id + pesan error (null bila boleh menandai p_kode).
create or replace function public._revisit_reject_scope_error(
  p_kode         text,
  out petugas_id uuid,
  out err_msg    text
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_me record;
begin
  select * into v_me from public._revisit_me();
  petugas_id := v_me.petugas_id;

  if petugas_id is null then
    err_msg := 'Petugas tidak aktif';
    return;
  end if;
  if v_me.role = 'admin' then
    return;
  end if;
  if not exists (
    select 1 from public.se2026_revisit_alokasi a
    where a.kode_sls = p_kode and a.petugas_id = v_me.petugas_id
  ) then
    err_msg := 'SLS ini bukan alokasi revisit Anda';
  end if;
end;
$$;

revoke all on function public._revisit_reject_scope_error(text) from public, anon;

-- ── Baca daftar (scope alokasi revisit) + gabung tanda reject ───────────────
create or replace function public.get_revisit_reject()
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
    a.hari_ke,
    t.updated_at,
    (r.assignment_id is not null),
    r.alasan,
    coalesce(nullif(trim(ru.name), ''), ru.email)::text,
    r.updated_at
  from public._revisit_me() me
  cross join public.se2026_revisit_reject_sumber t
  -- LEFT JOIN: admin tetap melihat SLS yang belum dialokasikan untuk revisit.
  left join public.se2026_revisit_alokasi a on a.kode_sls = t.level_6_full_code
  left join public.vw_fasih_wilayah_scope_base sw
    on sw.kode_wilayah = t.level_6_full_code
  left join public.vw_revisit_petugas_nama n on n.petugas_id = a.petugas_id
  left join public.se2026_revisit_petugas rp on rp.petugas_id = a.petugas_id
  left join public.se2026_revisit_reject r on r.assignment_id = t.assignment_id
  left join public.se2026_petugas rpg on rpg.id = r.flagged_by
  left join public.users ru on ru.id = rpg.user_id
  where me.petugas_id is not null
    and (me.role = 'admin' or a.petugas_id = me.petugas_id)
  order by sw.nm_kec nulls last, sw.nm_desa nulls last,
           t.level_6_full_code, t.nama, t.assignment_id;
$$;

grant execute on function public.get_revisit_reject() to authenticated;

-- ── Tandai / batalkan reject ────────────────────────────────────────────────
create or replace function public.set_revisit_reject(
  p_assignment_id text,
  p_alasan        text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_kode  text;
  v_scope record;
begin
  if p_assignment_id is null or trim(p_assignment_id) = '' then
    return jsonb_build_object('ok', false, 'error', 'assignment_id kosong');
  end if;

  select t.level_6_full_code into v_kode
  from public.se2026_revisit_reject_sumber t
  where t.assignment_id = p_assignment_id;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Assignment tidak ditemukan');
  end if;

  select * into v_scope from public._revisit_reject_scope_error(v_kode);
  if v_scope.err_msg is not null then
    return jsonb_build_object('ok', false, 'error', v_scope.err_msg);
  end if;

  insert into public.se2026_revisit_reject as r
    (assignment_id, alasan, flagged_by, created_at, updated_at)
  values
    (p_assignment_id, nullif(trim(p_alasan), ''), v_scope.petugas_id, now(), now())
  on conflict (assignment_id) do update
    set alasan     = excluded.alasan,
        flagged_by = excluded.flagged_by,
        updated_at = now();

  return jsonb_build_object('ok', true, 'assignment_id', p_assignment_id);
end;
$$;

grant execute on function public.set_revisit_reject(text, text) to authenticated;

create or replace function public.unset_revisit_reject(p_assignment_id text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_kode  text;
  v_scope record;
begin
  select t.level_6_full_code into v_kode
  from public.se2026_revisit_reject_sumber t
  where t.assignment_id = p_assignment_id;

  -- Assignment yang sudah tidak ada di daftar: tanda yatim boleh dibersihkan
  -- petugas aktif mana pun; selain itu wajib dalam scope alokasi revisit.
  select * into v_scope from public._revisit_reject_scope_error(v_kode);
  if v_scope.petugas_id is null
     or (v_kode is not null and v_scope.err_msg is not null) then
    return jsonb_build_object('ok', false, 'error', coalesce(v_scope.err_msg, 'Tidak diizinkan'));
  end if;

  delete from public.se2026_revisit_reject where assignment_id = p_assignment_id;

  return jsonb_build_object('ok', true, 'assignment_id', p_assignment_id);
end;
$$;

grant execute on function public.unset_revisit_reject(text) to authenticated;

-- ── Impor daftar sumber (ekstensi / admin): REPLACE penuh ───────────────────
-- p_rows = [{assignment_id, assignment_status_alias, assignment_status_id,
--            level_6_full_code, level_6_name, nama, alamat, no_bang}, ...]
create or replace function public.import_revisit_reject_sumber(p_rows jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_role  text;
  v_count integer;
begin
  select me.role into v_role from public._revisit_me() me;
  if v_role is distinct from 'admin' and auth.role() <> 'service_role' then
    return jsonb_build_object('ok', false, 'error', 'Hanya admin');
  end if;

  delete from public.se2026_revisit_reject_sumber;

  insert into public.se2026_revisit_reject_sumber
    (assignment_id, assignment_status_alias, assignment_status_id,
     level_6_full_code, level_6_name, nama, alamat, no_bang, updated_at)
  select
    x.assignment_id, x.assignment_status_alias, x.assignment_status_id,
    x.level_6_full_code, x.level_6_name, x.nama, x.alamat, x.no_bang, now()
  from jsonb_to_recordset(coalesce(p_rows, '[]'::jsonb)) as x(
    assignment_id           text,
    assignment_status_alias text,
    assignment_status_id    integer,
    level_6_full_code       text,
    level_6_name            text,
    nama                    text,
    alamat                  text,
    no_bang                 text
  )
  where x.assignment_id is not null
  on conflict (assignment_id) do update
    set assignment_status_alias = excluded.assignment_status_alias,
        assignment_status_id    = excluded.assignment_status_id,
        level_6_full_code       = excluded.level_6_full_code,
        level_6_name            = excluded.level_6_name,
        nama                    = excluded.nama,
        alamat                  = excluded.alamat,
        no_bang                 = excluded.no_bang,
        updated_at              = now();
  get diagnostics v_count = row_count;

  return jsonb_build_object('ok', true, 'count', v_count);
end;
$$;

grant execute on function public.import_revisit_reject_sumber(jsonb) to authenticated;
