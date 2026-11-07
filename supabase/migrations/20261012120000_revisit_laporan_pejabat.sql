-- Pejabat yang ditemui saat revisit (nama & jabatan), diisi petugas di form
-- laporan dan dicetak di bagian C laporan perjalanan dinas (untuk visum).
--
-- Sengaja memakai fungsi tersendiri (bukan mengubah upsert/get laporan) agar
-- penyimpanan laporan yang sudah berjalan tidak terganggu.

alter table public.se2026_revisit_laporan
  add column if not exists pejabat_nama    text,
  add column if not exists pejabat_jabatan text;

-- Simpan nama & jabatan pejabat untuk satu laporan (milik sendiri / admin).
create or replace function public.set_revisit_laporan_pejabat(
  p_id      uuid,
  p_nama    text,
  p_jabatan text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_me record;
begin
  select * into v_me from public._revisit_me();
  update public.se2026_revisit_laporan l
     set pejabat_nama    = nullif(trim(p_nama), ''),
         pejabat_jabatan = nullif(trim(p_jabatan), '')
   where l.id = p_id
     and (v_me.role = 'admin' or l.petugas_id = v_me.petugas_id);
  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'Laporan tidak ditemukan / tidak diizinkan'
    );
  end if;
  return jsonb_build_object('ok', true);
end;
$$;
grant execute on function public.set_revisit_laporan_pejabat(uuid, text, text)
  to authenticated;

-- Baca nama & jabatan pejabat untuk sekumpulan laporan (admin: semua;
-- selain admin: milik sendiri).
create or replace function public.get_revisit_laporan_pejabat(p_ids uuid[])
returns table (
  id              uuid,
  pejabat_nama    text,
  pejabat_jabatan text
)
language sql
stable
security definer
set search_path = public
as $$
  select l.id, l.pejabat_nama, l.pejabat_jabatan
  from public.se2026_revisit_laporan l
  cross join public._revisit_me() me
  where l.id = any(p_ids)
    and (me.role = 'admin' or l.petugas_id = me.petugas_id);
$$;
grant execute on function public.get_revisit_laporan_pejabat(uuid[])
  to authenticated;
