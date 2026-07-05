-- ============================================================
-- 2. Backfill best-effort dari se2026_anomali_temuan (riwayat lama)
--    petugas_id dicocokkan dari diperiksa_oleh (nama ATAU email) --
--    baris yang tidak match dilewati (tidak bisa masuk krn petugas_id NOT
--    NULL). Baris 'belum_diperiksa' dan yang melanggar constraint keterangan
--    wajib (konfirmasi_valid tanpa catatan) juga dilewati.
-- ============================================================
insert into public.anomali_pusat_respons (
  sumber, scope, assignment_id, nama_subjek, kategori_kode,
  petugas_id, jenis_respons, keterangan, created_at, updated_at
)
select
  'kualitas',
  t.kategori,
  t.assignment_id,
  '',
  'ANOM-' || lpad(t.no_anomali::text, 3, '0'),
  matched.petugas_id,
  case
    when t.status_tindak_lanjut = 'dikonfirmasi_valid' then 'konfirmasi_valid'
    when t.status_tindak_lanjut in ('dikonfirmasi_salah_entri', 'sudah_diperbaiki') then 'perbaikan'
  end,
  t.catatan_petugas,
  t.created_at,
  t.updated_at
from public.se2026_anomali_temuan t
cross join lateral (
  select p.id as petugas_id
  from public.se2026_petugas p
  left join public.users u on u.id = p.user_id
  where p.nama = t.diperiksa_oleh or u.email = t.diperiksa_oleh
  limit 1
) matched
where t.status_tindak_lanjut in ('dikonfirmasi_valid', 'dikonfirmasi_salah_entri', 'sudah_diperbaiki')
  and matched.petugas_id is not null
  and not (
    t.status_tindak_lanjut = 'dikonfirmasi_valid'
    and (t.catatan_petugas is null or length(trim(t.catatan_petugas)) = 0)
  )
on conflict do nothing;
