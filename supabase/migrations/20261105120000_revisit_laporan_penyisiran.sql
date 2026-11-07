-- Penyisiran SLS saat revisit: nama jalan/perumahan yang disisir dan perkiraan
-- jumlah bangunan. Diisi petugas di form laporan (atau admin lewat edit) dan
-- dicetak di Hasil Kegiatan laporan perjalanan dinas.
--
-- Sengaja memakai fungsi tersendiri (seperti pejabat) agar upsert/get laporan
-- yang sudah berjalan tidak berubah.

alter table public.se2026_revisit_laporan
  add column if not exists penyisiran_jalan text,
  add column if not exists jumlah_bangunan  integer;

-- Simpan nama jalan & jumlah bangunan untuk satu laporan (milik sendiri / admin).
create or replace function public.set_revisit_laporan_penyisiran(
  p_id        uuid,
  p_jalan     text,
  p_bangunan  integer
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
  if p_bangunan is not null and p_bangunan < 0 then
    return jsonb_build_object('ok', false, 'error', 'Jumlah bangunan tidak boleh negatif');
  end if;
  update public.se2026_revisit_laporan l
     set penyisiran_jalan = nullif(trim(p_jalan), ''),
         jumlah_bangunan  = p_bangunan
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
grant execute on function public.set_revisit_laporan_penyisiran(uuid, text, integer)
  to authenticated;

-- Baca nama jalan & jumlah bangunan untuk sekumpulan laporan (admin: semua;
-- selain admin: milik sendiri).
create or replace function public.get_revisit_laporan_penyisiran(p_ids uuid[])
returns table (
  id               uuid,
  penyisiran_jalan text,
  jumlah_bangunan  integer
)
language sql
stable
security definer
set search_path = public
as $$
  select l.id, l.penyisiran_jalan, l.jumlah_bangunan
  from public.se2026_revisit_laporan l
  cross join public._revisit_me() me
  where l.id = any(p_ids)
    and (me.role = 'admin' or l.petugas_id = me.petugas_id);
$$;
grant execute on function public.get_revisit_laporan_penyisiran(uuid[])
  to authenticated;
