-- Menyelaraskan alur "2 pilihan petugas" (perbaikan vs konfirmasi valid)
-- antara anomali wilayah (kualitas) dan anomali pusat, tanpa mengubah
-- data se2026_anomali_pusat (harus tetap, sumber dari BPS Pusat).
--
-- Aman dijalankan berkali-kali: semua ALTER pakai IF NOT EXISTS / cek manual
-- sebelum apply ke production, sesuaikan dulu nama constraint bila sudah ada.

-- ============================================================
-- 1. ANOMALI WILAYAH (se2026_anomali_temuan)
-- ============================================================
-- status_tindak_lanjut sudah py 4 nilai:
--   belum_diperiksa
--   dikonfirmasi_salah_entri / sudah_diperbaiki  -> pilihan "perbaiki", catatan OPSIONAL
--   dikonfirmasi_valid                            -> pilihan "data benar", catatan WAJIB
-- Constraint di bawah cuma menegakkan cabang kedua.
alter table public.se2026_anomali_temuan
  add constraint chk_anomali_temuan_keterangan_wajib
  check (
    status_tindak_lanjut <> 'dikonfirmasi_valid'
    or (catatan_petugas is not null and length(trim(catatan_petugas)) > 0)
  );

-- ============================================================
-- 2. ANOMALI PUSAT (se2026_anomali_pusat_keterangan)
-- ============================================================
-- Belum ada cabang "perbaikan vs konfirmasi_valid" sama sekali.
-- Default 'konfirmasi_valid' untuk 352 baris existing karena selama ini
-- fitur yang ada memang cuma "isi keterangan/penjelasan".
alter table public.se2026_anomali_pusat_keterangan
  add column jenis_respons text not null default 'konfirmasi_valid'
  check (jenis_respons in ('perbaikan', 'konfirmasi_valid'));

alter table public.se2026_anomali_pusat_keterangan
  add constraint chk_anomali_pusat_keterangan_wajib
  check (
    jenis_respons <> 'konfirmasi_valid'
    or (keterangan is not null and length(trim(keterangan)) > 0)
  );

-- Update RPC upsert supaya menerima jenis_respons dan menegakkan validasi
-- di server (bukan cuma di UI).
create or replace function public.upsert_anomali_pusat_keterangan(
  p_assignment_id text,
  p_nama_anomali text,
  p_keterangan text,
  p_jenis_respons text default 'konfirmasi_valid'
)
returns void
language plpgsql
security definer
as $function$
declare
    v_petugas_id uuid;
begin
    if p_jenis_respons not in ('perbaikan', 'konfirmasi_valid') then
        raise exception 'jenis_respons tidak valid: %', p_jenis_respons;
    end if;

    if p_jenis_respons = 'konfirmasi_valid'
       and (p_keterangan is null or length(trim(p_keterangan)) = 0) then
        raise exception 'Keterangan wajib diisi untuk konfirmasi data benar';
    end if;

    select p.id into v_petugas_id
    from public.se2026_petugas p
    join public.users u on u.id = p.user_id
    where u.auth_uid = auth.uid() and p.is_active = true
    limit 1;

    if v_petugas_id is null then
        raise exception 'Petugas tidak ditemukan';
    end if;

    insert into public.se2026_anomali_pusat_keterangan
        (assignment_id, nama_anomali, petugas_id, keterangan, jenis_respons, updated_at)
    values
        (p_assignment_id, p_nama_anomali, v_petugas_id, p_keterangan, p_jenis_respons, now())
    on conflict (assignment_id, nama_anomali, petugas_id)
    do update set
        keterangan    = excluded.keterangan,
        jenis_respons = excluded.jenis_respons,
        updated_at    = now();
end;
$function$;

-- Ikutkan jenis_respons saat membaca kembali keterangan tim.
create or replace function public.get_anomali_pusat_keterangan(
  p_assignment_id text,
  p_nama_anomali text
)
returns table(
  petugas_id uuid,
  nama_petugas text,
  role text,
  keterangan text,
  jenis_respons text,
  updated_at timestamptz
)
language plpgsql
security definer
as $function$
begin
    return query
    select
        k.petugas_id,
        p.nama as nama_petugas,
        p.role,
        k.keterangan,
        k.jenis_respons,
        k.updated_at
    from public.se2026_anomali_pusat_keterangan k
    join public.se2026_petugas p on p.id = k.petugas_id
    where k.assignment_id = p_assignment_id
      and k.nama_anomali  = p_nama_anomali
    order by k.updated_at desc;
end;
$function$;
