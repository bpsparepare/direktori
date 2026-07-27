-- Sumber baru dashboard FASIH: rekap agregat per-SLS (wide) hasil query SQLLab
-- atas base_table_assignment, didorong ke Supabase oleh ekstensi browser.
--
-- Menggantikan ketergantungan pada se2026_keterangan_umum / se2026_assignment_list
-- yang kini sulit diambil. Kolom mengikuti output query:
--   level_6_full_code (16 digit = se2026_wilayah_tugas.id), level_6_name,
--   approved_pengawas, submitted_pencacah, draft_awal (status_id=0),
--   draft_revisi (status_id=3), rejected_pengawas, edited_admin_kab,
--   rejected_admin_kab, revoked_pengawas, submitted_respondent, total.
--
-- snapshot_date memungkinkan penyimpanan per tanggal → progress harian dihitung
-- dari selisih antar snapshot. total = COUNT(assignment) (bisa > jumlah kolom
-- bila ada status lain di luar daftar; selisihnya dianggap "belum/lainnya").

create table if not exists public.se2026_rekap_sls_harian (
  snapshot_date          date    not null default (now() at time zone 'Asia/Jakarta')::date,
  level_6_full_code      text    not null,
  level_6_name           text,
  approved_pengawas      integer not null default 0,
  submitted_pencacah     integer not null default 0,
  draft_awal             integer not null default 0,
  draft_revisi           integer not null default 0,
  rejected_pengawas      integer not null default 0,
  edited_admin_kab       integer not null default 0,
  rejected_admin_kab     integer not null default 0,
  revoked_pengawas       integer not null default 0,
  submitted_respondent   integer not null default 0,
  total                  integer not null default 0,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  primary key (snapshot_date, level_6_full_code)
);

create index if not exists idx_rekap_sls_harian_kode
  on public.se2026_rekap_sls_harian (level_6_full_code);
create index if not exists idx_rekap_sls_harian_date
  on public.se2026_rekap_sls_harian (snapshot_date);

alter table public.se2026_rekap_sls_harian enable row level security;

-- Admin boleh baca/tulis langsung (mis. via PostgREST). Dashboard membaca lewat
-- RPC security definer sehingga tak bergantung policy ini.
drop policy if exists rekap_sls_harian_admin_all on public.se2026_rekap_sls_harian;
create policy rekap_sls_harian_admin_all
  on public.se2026_rekap_sls_harian
  for all
  to authenticated
  using (
    exists (
      select 1
      from public.se2026_petugas p
      join public.users u on u.id = p.user_id
      where u.auth_uid = auth.uid()
        and p.role = 'admin'
        and coalesce(p.is_active, false)
    )
  )
  with check (
    exists (
      select 1
      from public.se2026_petugas p
      join public.users u on u.id = p.user_id
      where u.auth_uid = auth.uid()
        and p.role = 'admin'
        and coalesce(p.is_active, false)
    )
  );

-- ── Impor massal (dipanggil ekstensi): kirim array JSON hasil query ───────────
-- Contoh elemen p_rows:
--   { "level_6_full_code": "7372010004000700", "level_6_name": "RT 001 RW 004",
--     "approved_pengawas": 0, "submitted_pencacah": 5, "draft_awal": 2,
--     "draft_revisi": 1, "rejected_pengawas": 0, "edited_admin_kab": 0,
--     "rejected_admin_kab": 0, "revoked_pengawas": 0, "submitted_respondent": 4,
--     "total": 12 }
-- p_snapshot_date opsional (default: tanggal WIB hari ini). Upsert per
-- (snapshot_date, level_6_full_code) → impor ulang tanggal sama menimpa.
create or replace function public.import_rekap_sls(
  p_rows          jsonb,
  p_snapshot_date date default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_auth_uid uuid := auth.uid();
  v_is_admin boolean := false;
  v_date     date := coalesce(
    p_snapshot_date,
    (now() at time zone 'Asia/Jakarta')::date
  );
  v_count    integer := 0;
begin
  -- Authenticated harus admin. service_role (uid null; anon tak di-grant) lolos.
  if v_auth_uid is not null then
    select (p.role = 'admin' and coalesce(p.is_active, false))
      into v_is_admin
    from public.users u
    join public.se2026_petugas p on p.user_id = u.id
    where u.auth_uid = v_auth_uid
    order by p.created_at desc nulls last
    limit 1;
    if not coalesce(v_is_admin, false) then
      return jsonb_build_object('ok', false, 'error', 'Hanya admin yang boleh impor');
    end if;
  end if;

  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then
    return jsonb_build_object('ok', false, 'error', 'p_rows harus array JSON');
  end if;

  insert into public.se2026_rekap_sls_harian as t (
    snapshot_date, level_6_full_code, level_6_name,
    approved_pengawas, submitted_pencacah, draft_awal, draft_revisi,
    rejected_pengawas, edited_admin_kab, rejected_admin_kab,
    revoked_pengawas, submitted_respondent, total, updated_at
  )
  select
    v_date,
    e->>'level_6_full_code',
    e->>'level_6_name',
    coalesce((e->>'approved_pengawas')::int, 0),
    coalesce((e->>'submitted_pencacah')::int, 0),
    coalesce((e->>'draft_awal')::int, 0),
    coalesce((e->>'draft_revisi')::int, 0),
    coalesce((e->>'rejected_pengawas')::int, 0),
    coalesce((e->>'edited_admin_kab')::int, 0),
    coalesce((e->>'rejected_admin_kab')::int, 0),
    coalesce((e->>'revoked_pengawas')::int, 0),
    coalesce((e->>'submitted_respondent')::int, 0),
    coalesce((e->>'total')::int, 0),
    now()
  from jsonb_array_elements(p_rows) e
  where coalesce(e->>'level_6_full_code', '') <> ''
  on conflict (snapshot_date, level_6_full_code) do update set
    level_6_name         = excluded.level_6_name,
    approved_pengawas    = excluded.approved_pengawas,
    submitted_pencacah   = excluded.submitted_pencacah,
    draft_awal           = excluded.draft_awal,
    draft_revisi         = excluded.draft_revisi,
    rejected_pengawas    = excluded.rejected_pengawas,
    edited_admin_kab     = excluded.edited_admin_kab,
    rejected_admin_kab   = excluded.rejected_admin_kab,
    revoked_pengawas     = excluded.revoked_pengawas,
    submitted_respondent = excluded.submitted_respondent,
    total                = excluded.total,
    updated_at           = now();

  get diagnostics v_count = row_count;
  return jsonb_build_object('ok', true, 'snapshot_date', v_date, 'rows', v_count);
end;
$$;

grant execute on function public.import_rekap_sls(jsonb, date) to authenticated, service_role;
