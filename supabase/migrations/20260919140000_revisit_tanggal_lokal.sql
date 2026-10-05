-- Perbaikan: laporan revisit ditolak "Tanggal tidak valid" di pagi hari.
-- Penyebab: current_date di server = tanggal UTC, sedangkan aplikasi mengirim
-- tanggal lokal (WITA = UTC+8). Sebelum pukul 08.00 WITA tanggal lokal sudah
-- "besok" menurut server. Batas atas kini memakai zona paling timur Indonesia
-- (WIT, Asia/Jayapura) agar tanggal lokal WIB/WITA/WIT selalu diterima.
create or replace function public.upsert_revisit_laporan(
  p_kode_sls     text,
  p_tanggal      date,
  p_status       text,
  p_jumlah_dicek integer default null,
  p_catatan      text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_me       record;
  v_id       uuid;
  v_owner    uuid;
begin
  select * into v_me from public._revisit_me();
  if v_me.petugas_id is null then
    return jsonb_build_object('ok', false, 'error', 'Petugas tidak aktif');
  end if;

  if not exists (
    select 1 from public.se2026_revisit_alokasi a
    where a.kode_sls = p_kode_sls and a.petugas_id = v_me.petugas_id
  ) then
    return jsonb_build_object('ok', false, 'error', 'SLS ini bukan alokasi revisit Anda');
  end if;

  if p_tanggal is null
     or p_tanggal > (now() at time zone 'Asia/Jayapura')::date then
    return jsonb_build_object('ok', false, 'error', 'Tanggal tidak boleh melewati hari ini');
  end if;

  select l.id, l.petugas_id into v_id, v_owner
  from public.se2026_revisit_laporan l
  where l.kode_sls = p_kode_sls and l.tanggal = p_tanggal;

  if v_id is not null and v_owner <> v_me.petugas_id then
    return jsonb_build_object('ok', false, 'error', 'Laporan tanggal ini sudah diisi petugas lain');
  end if;

  if v_id is null then
    insert into public.se2026_revisit_laporan
      (kode_sls, petugas_id, tanggal, status, jumlah_dicek, catatan)
    values
      (p_kode_sls, v_me.petugas_id, p_tanggal, p_status, p_jumlah_dicek,
       nullif(trim(p_catatan), ''))
    returning id into v_id;
  else
    update public.se2026_revisit_laporan
       set status       = p_status,
           jumlah_dicek = p_jumlah_dicek,
           catatan      = nullif(trim(p_catatan), ''),
           updated_at   = now()
     where id = v_id;
  end if;

  return jsonb_build_object('ok', true, 'id', v_id);
end;
$$;

grant execute on function public.upsert_revisit_laporan(text, date, text, integer, text) to authenticated;
