-- Revisit: progres harian = total usaha/keluarga didata (kolom jumlah_dicek)
-- per tanggal, untuk grafik progres. Satu baris per tanggal yang ada laporan.
-- Admin: semua petugas (opsional filter p_petugas_id). Selain admin: milik
-- sendiri saja.
create or replace function public.get_revisit_progres_harian(
  p_petugas_id uuid default null
)
returns table (
  tanggal         date,
  jumlah_laporan  integer,
  jumlah_didata   integer,
  jumlah_petugas  integer,
  jumlah_foto     integer
)
language sql
stable
security definer
set search_path = public
as $$
  select
    l.tanggal,
    count(*)::integer,
    coalesce(sum(l.jumlah_dicek), 0)::integer,
    count(distinct l.petugas_id)::integer,
    coalesce(sum((
      select count(*) from public.se2026_revisit_foto f
      where f.laporan_id = l.id
    )), 0)::integer
  from public._revisit_me() me
  join public.se2026_revisit_laporan l
    on me.role = 'admin' or l.petugas_id = me.petugas_id
  where me.petugas_id is not null
    and (p_petugas_id is null or l.petugas_id = p_petugas_id)
  group by l.tanggal
  order by l.tanggal;
$$;

grant execute on function public.get_revisit_progres_harian(uuid) to authenticated;
