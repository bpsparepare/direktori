-- Admin mengedit progres (laporan) milik petugas mana pun dari Rekap.
--
-- upsert_revisit_laporan selalu memakai petugas yang login, jadi tidak bisa
-- dipakai admin untuk laporan orang lain. Fungsi ini mengubah laporan yang
-- sudah ada berdasarkan id; SLS, petugas, dan hari ke- tidak berubah.

create or replace function public.update_revisit_laporan_admin(
  p_id            uuid,
  p_tanggal       date,
  p_status        text,
  p_jumlah_dicek  integer,
  p_jumlah_submit integer,
  p_jumlah_belum  integer,
  p_catatan       text
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
  if v_me.role is distinct from 'admin' then
    return jsonb_build_object('ok', false, 'error', 'Hanya admin yang boleh mengedit laporan');
  end if;

  if p_status is null
     or p_jumlah_dicek is null
     or p_jumlah_belum is null
     or p_jumlah_submit is null
     or nullif(trim(p_catatan), '') is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'Status, jumlah didata, jumlah submit, potensi belum didata, dan catatan wajib diisi'
    );
  end if;

  if p_tanggal is null
     or p_tanggal > (now() at time zone 'Asia/Jayapura')::date then
    return jsonb_build_object('ok', false, 'error', 'Tanggal tidak boleh melewati hari ini');
  end if;

  update public.se2026_revisit_laporan
     set tanggal             = p_tanggal,
         status              = p_status,
         jumlah_dicek        = p_jumlah_dicek,
         jumlah_submit       = p_jumlah_submit,
         jumlah_belum_didata = p_jumlah_belum,
         catatan             = nullif(trim(p_catatan), ''),
         updated_at          = now()
   where id = p_id;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Laporan tidak ditemukan');
  end if;

  return jsonb_build_object('ok', true, 'id', p_id);
end;
$$;

grant execute on function public.update_revisit_laporan_admin(
  uuid, date, text, integer, integer, integer, text) to authenticated;
