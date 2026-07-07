-- Migrasi kode respons lama agar cocok dengan kategori_kode berprefix.
--
-- Setelah import diubah memakai prefix UP/KP (migration 20260706120000),
-- anomali_pusat_temuan.kategori_kode jadi 'UP3'/'KP3'/'UPLAINNYA', dst.
-- Respons yang dibuat SEBELUM perubahan itu masih memakai kode angka mentah
-- ('3', 'lainnya') sehingga tidak lagi tersambung ke temuan di
-- get_anomali_gabungan. Migration ini menyelaraskannya.
--
-- Hanya menyentuh sumber 'pusat_baru' (respons 'kualitas' memakai kode
-- 'ANOM-xxx' dan tidak berubah). Baris yang sudah berprefix dilewati.
--
-- Catatan: jika untuk kombinasi (scope, assignment_id, nama_subjek, petugas)
-- yang sama sudah ada baris kode lama DAN kode baru sekaligus, update bisa
-- bentrok unique key. Kasus ini seharusnya langka; kalau terjadi, baris lama
-- dibiarkan (lihat guard NOT EXISTS di bawah) supaya migration tidak gagal.

update public.anomali_pusat_respons r
set
    kategori_kode = (case when r.scope = 'usaha' then 'UP' else 'KP' end)
      || (case when r.kategori_kode = 'lainnya' then 'LAINNYA' else r.kategori_kode end),
    updated_at = now()
where r.sumber = 'pusat_baru'
  and r.scope in ('usaha', 'keluarga')
  and r.kategori_kode !~ '^(UP|KP)'
  and not exists (
      select 1
      from public.anomali_pusat_respons x
      where x.sumber = r.sumber
        and x.scope = r.scope
        and x.assignment_id = r.assignment_id
        and x.nama_subjek = r.nama_subjek
        and x.petugas_id = r.petugas_id
        and x.kategori_kode =
            (case when r.scope = 'usaha' then 'UP' else 'KP' end)
            || (case when r.kategori_kode = 'lainnya' then 'LAINNYA' else r.kategori_kode end)
  );
