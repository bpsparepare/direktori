-- =====================================================================
-- Tabel: se2026_per_kategori
-- Ringkasan data Sensus Ekonomi 2026 per kategori KBLI (A-T)
-- =====================================================================
create table if not exists public.se2026_per_kategori (
  id                        uuid primary key default gen_random_uuid(),
  kategori                  text not null unique,
  nama_kategori             text,
  jumlah_usaha              bigint not null default 0,
  total_pendapatan_bln      numeric default 0,
  rata2_pendapatan_bln      numeric default 0,
  total_pengeluaran_bln     numeric default 0,
  rata2_pengeluaran_bln     numeric default 0,
  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now()
);

comment on table  public.se2026_per_kategori                   is 'Ringkasan Sensus Ekonomi 2026 per kategori KBLI A-T';
comment on column public.se2026_per_kategori.kategori          is 'Kode kategori KBLI 1 huruf (A s/d T) atau kode lain untuk keseluruhan';
comment on column public.se2026_per_kategori.nama_kategori     is 'Nama panjang kategori (mis. A = Pertanian, Kehutanan, dan Perikanan)';
comment on column public.se2026_per_kategori.jumlah_usaha      is 'Jumlah unit usaha/usaha keluarga dalam kategori';
comment on column public.se2026_per_kategori.total_pendapatan_bln  is 'Jumlah total pendapatan (bulanan) seluruh unit pada kategori';
comment on column public.se2026_per_kategori.rata2_pendapatan_bln  is 'Rata-rata pendapatan (bulanan) per unit usaha pada kategori';
comment on column public.se2026_per_kategori.total_pengeluaran_bln is 'Jumlah total pengeluaran (bulanan) seluruh unit pada kategori';
comment on column public.se2026_per_kategori.rata2_pengeluaran_bln is 'Rata-rata pengeluaran (bulanan) per unit usaha pada kategori';

create index if not exists se2026_per_kategori_kategori_idx
  on public.se2026_per_kategori (kategori);

-- =====================================================================
-- Tabel: pdrb_2025_per_kategori
-- Data PDRB Tahun 2025 per lapangan usaha (disesuaikan agar dapat
-- di-join dengan kategori KBLI A-T pada tabel se2026_per_kategori).
-- =====================================================================
create table if not exists public.pdrb_2025_per_kategori (
  id                        uuid primary key default gen_random_uuid(),
  kategori                  text not null unique,
  nama_kategori             text,
  pdrb_berjalan_juta        numeric default 0,
  pdrb_konstan_juta         numeric default 0,
  pertumbuhan_persen        numeric default 0,
  pangsa_persen             numeric default 0,
  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now()
);

comment on table  public.pdrb_2025_per_kategori                is 'PDRB 2025 per kategori/lapangan usaha yang sepadan dengan KBLI A-T';
comment on column public.pdrb_2025_per_kategori.kategori       is 'Kode kategori KBLI 1 huruf (A s/d T) untuk join dengan se2026_per_kategori';
comment on column public.pdrb_2025_per_kategori.nama_kategori  is 'Nama lapangan usaha PDRB';
comment on column public.pdrb_2025_per_kategori.pdrb_berjalan_juta   is 'Nilai PDRB atas dasar harga berlaku (satuan juta rupiah)';
comment on column public.pdrb_2025_per_kategori.pdrb_konstan_juta    is 'Nilai PDRB atas dasar harga konstan (satuan juta rupiah)';
comment on column public.pdrb_2025_per_kategori.pertumbuhan_persen   is 'Pertumbuhan PDRB (persen y-on-y dibanding 2024)';
comment on column public.pdrb_2025_per_kategori.pangsa_persen        is 'Pangsa PDRB kategori terhadap total PDRB (persen)';

create index if not exists pdrb_2025_per_kategori_kategori_idx
  on public.pdrb_2025_per_kategori (kategori);

-- =====================================================================
-- View: vw_se_pdrb_perbandingan
-- Gabungkan SE 2026 dengan PDRB 2025 per kategori untuk dashboard.
-- =====================================================================
create or replace view public.vw_se_pdrb_perbandingan as
select
  coalesce(s.kategori, p.kategori)                                          as kategori,
  coalesce(s.nama_kategori, p.nama_kategori)                                as nama_kategori,
  coalesce(s.jumlah_usaha, 0)                                               as se_jumlah_usaha,
  coalesce(s.total_pendapatan_bln, 0)                                       as se_total_pendapatan_bln,
  coalesce(s.rata2_pendapatan_bln, 0)                                       as se_rata2_pendapatan_bln,
  coalesce(s.total_pengeluaran_bln, 0)                                      as se_total_pengeluaran_bln,
  coalesce(s.rata2_pengeluaran_bln, 0)                                      as se_rata2_pengeluaran_bln,
  coalesce(p.pdrb_berjalan_juta, 0)                                         as pdrb_berjalan_juta,
  coalesce(p.pdrb_konstan_juta, 0)                                          as pdrb_konstan_juta,
  coalesce(p.pertumbuhan_persen, 0)                                         as pdrb_pertumbuhan_persen,
  coalesce(p.pangsa_persen, 0)                                              as pdrb_pangsa_persen,
  case
    when s.jumlah_usaha > 0 and p.pdrb_berjalan_juta > 0
    then round(
      (
        (s.total_pendapatan_bln::numeric * 12 / 1000000)
        / p.pdrb_berjalan_juta
      ) * 100,
      2
    )
    else 0
  end                                                                       as se_vs_pdrb_coverage_persen,
  case
    when s.jumlah_usaha > 0
    then round(
      (p.pdrb_berjalan_juta * 1000000 / s.jumlah_usaha),
      0
    )
    else 0
  end                                                                       as pdrb_per_usaha_per_tahun_rupiah
from public.se2026_per_kategori s
full outer join public.pdrb_2025_per_kategori p
  on s.kategori = p.kategori
order by coalesce(s.kategori, p.kategori);

comment on view public.vw_se_pdrb_perbandingan is
'Perbandingan SE 2026 dan PDRB 2025 per kategori.
 - se_vs_pdrb_coverage_persen = (total_pendapatan SE per tahun / PDRB berjalan) x 100%
 - pdrb_per_usaha_per_tahun_rupiah = PDRB berjalan / jumlah usaha (perkiraan nilai PDRB per unit usaha/thn)';

-- =====================================================================
-- Row Level Security: semua yang login bisa baca (sesuai pola project).
-- =====================================================================
alter table public.se2026_per_kategori  enable row level security;
alter table public.pdrb_2025_per_kategori enable row level security;

drop policy if exists "se_pdrb authenticated read" on public.se2026_per_kategori;
create policy "se_pdrb authenticated read"
  on public.se2026_per_kategori for select
  using (auth.role() = 'authenticated');

drop policy if exists "pdrb_2025 authenticated read" on public.pdrb_2025_per_kategori;
create policy "pdrb_2025 authenticated read"
  on public.pdrb_2025_per_kategori for select
  using (auth.role() = 'authenticated');

-- Trigger auto updated_at
create or replace function public.set_timestamp()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end; $$;

drop trigger if exists set_timestamp_se2026_per_kategori
  on public.se2026_per_kategori;
create trigger set_timestamp_se2026_per_kategori
before update on public.se2026_per_kategori
for each row execute function public.set_timestamp();

drop trigger if exists set_timestamp_pdrb_2025_per_kategori
  on public.pdrb_2025_per_kategori;
create trigger set_timestamp_pdrb_2025_per_kategori
before update on public.pdrb_2025_per_kategori
for each row execute function public.set_timestamp();
