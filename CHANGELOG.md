# Catatan Rilis — Direktori BPS Parepare

## v3.3.0+32 — 2026-10-01

Rilis ini menghadirkan menu **Revisit**: kunjungan ulang SLS oleh tim khusus, lengkap dengan alokasi jadwal, laporan berfoto, rekap progres, dan penandaan reject.

### ✨ Fitur Baru
- **Menu Revisit.** Tim revisit dipilih dari petugas yang ada (PML/PPL) dan dikelompokkan per tim (2 orang per tim, sebagai informasi).
- **Alokasi jadwal per SLS.** Kunci jadwal = SLS + hari ke- + petugas. Satu SLS boleh dijadwalkan beberapa hari, satu hari boleh dikerjakan beberapa petugas, dan **satu petugas hanya boleh satu SLS per hari**.
- **Impor Cepat alokasi.** Tempel dari Excel/Sheets atau clipboard; petugas dikenali dari email (disarankan) atau nama. Setiap baris diverifikasi dan ditandai Tambah / Ganti / Sudah ada sebelum disimpan.
- **Laporan per jadwal.** Satu laporan untuk satu kunjungan terjadwal (SLS + petugas + hari ke-), berisi foto (wajib), status kunjungan, jumlah usaha/keluarga didata, jumlah submit, potensi belum didata, dan catatan. Foto tersimpan di Google Drive.
- **Rekap Revisit (admin).** Kumulatif per petugas dan per tim dengan progres "berapa dari berapa", grafik per hari ke-, serta tiga tampilan: Kartu, Tabel yang bisa diurutkan, dan Matriks petugas × hari untuk melihat siapa yang belum lapor.
- **Detail petugas.** Grafik progres, progres tiap jadwal, dan laporan per tanggal lengkap dengan foto.
- **Tab Reject.** Menandai assignment yang perlu di-reject, dengan cakupan mengikuti alokasi revisit. Daftar dimuat bertahap: ringkasan per SLS dulu, isinya menyusul saat SLS dibuka.

### 🔧 Peningkatan
- Batas tanggal laporan mengikuti waktu Indonesia, sehingga laporan pagi hari tidak lagi ditolak.
- Kolom angka pada form laporan terisi 0 sejak awal agar tidak tertukar dengan teks bantuan.
- Kamera terbuka lagi otomatis setelah setiap jepretan, dan galeri bisa memilih banyak foto sekaligus.

## v3.2.1+30 — 2026-09-13

Rilis ini menambahkan menu **Submit** untuk memantau assignment yang belum submit, lengkap dengan penandaan "Perlu Dihapus", serta dashboard FASIH yang kini bisa melihat kumulatif per tanggal.

### ✨ Fitur Baru
- **Menu Submit (side menu).** Daftar assignment berstatus REJECTED / DRAFT / OPEN hasil upload ekstensi, sesuai hak akses (admin semua, pengawas timnya, pendata wilayahnya). Dilengkapi pencarian (nama, alamat, no. bangunan, SLS) dan filter per status.
- **Tanda "Perlu Dihapus".** Petugas dapat menandai assignment yang perlu dihapus beserta alasannya, dan membatalkannya kembali. Tanda disimpan di tabel terpisah sehingga **tidak hilang** saat data di-upload ulang. Tanda ini hanya keterangan untuk tim, tidak menghapus data di FASIH.
- **Rekap per wilayah (SLS) yang bisa dibuka-tutup.** Setiap SLS menampilkan rekap Open, Draft, Reject, dan Perlu Dihapus. Defaultnya tertutup, dengan tombol Buka/Tutup semua. Kartu rekap berwarna oranye agar jelas berbeda dari daftar assignment.

### 🔧 Peningkatan
- **Dashboard FASIH per tanggal.** Total/Detail Kumulatif kini mengikuti tanggal snapshot yang dipilih, tidak hanya snapshot terbaru.
- **Menu Submit tidak lagi terbatas 1000 data.** Data diambil bertahap per 1000 baris sampai seluruhnya termuat.

### 🗄️ Basis Data (migrasi baru)
- `tindak_lanjut_hapus` — tabel `se2026_tindak_lanjut_hapus` + RPC `get_tindak_lanjut`, `set_tindak_lanjut_hapus`, `unset_tindak_lanjut_hapus`.
- `tindak_lanjut_order_stable` — urutan `get_tindak_lanjut` dibuat stabil (kunci akhir `assignment_id`) agar pengambilan bertahap tidak melewatkan/menggandakan baris.
- `fasih_rekap_target_date` — parameter `p_target_date` pada `get_fasih_rekap`.

### 📦 Versi
- Aplikasi: **3.2.1** (build **30**).
- Diperbarui di `pubspec.yaml`, `lib/core/config/app_version.dart`, `web/version.json`, dan `installer/direktori_installer.iss`.

> Catatan deploy: pastikan `version.json` (3.2.1 / build 30) juga terunggah ke server `https://direktori.bpsparepare.id/version.json`.

## v3.2.0+29 — 2026-09-03

Rilis ini fokus pada penyempurnaan peta (deteksi titik di luar batas SLS & pengaturan posisi marker), dashboard rekap FASIH berbasis snapshot harian, serta perapian halaman Lembar Kerja. Ditambah fondasi awal untuk perbandingan SE–PDRB.

### ✨ Fitur Baru
- **Deteksi Titik di Luar Batas SLS.** Peta kini menandai titik yang berada di luar batas SLS terpilih (termasuk yang benar-benar jauh, mis. di luar wilayah). Tersedia daftar "Titik di Luar Batas SLS" dan penyorotan titik langsung dari daftar tanpa membuka panel detail.
- **Pengaturan Posisi Marker (Koordinat Override).** Posisi marker dapat digeser/di-edit dan disimpan pada tabel override terpisah (keyed per assignment), tanpa mengubah data asli.
- **Halaman SE–PDRB (awal).** Menu perbandingan SE dengan PDRB ditambahkan sebagai kerangka awal, disiapkan bersama tabel & data seed di basis data.

### 🔧 Peningkatan
- **Dashboard FASIH berbasis snapshot harian.** Rekap dibaca dari snapshot `se2026_rekap_sls_harian` (hasil impor SQLLab), bukan lagi menghitung dari baris assignment — lebih cepat dan konsisten. Tampilan menampilkan Total Open, rekap per Petugas dan per Pengawas, serta filter "Hari Ini" / "7 Hari".
- **Peta lebih responsif** pada kontrol dan render marker (map controls & map view).

### 🧹 Perapian
- **Halaman Lembar Kerja disederhanakan** secara signifikan (pengurangan kode besar-besaran) agar lebih ringkas dan mudah dirawat.

### 🗄️ Basis Data (migrasi baru)
- `se_pdrb_tables` & `seed_se_pdrb` — tabel dan data awal SE–PDRB.
- `assignment_places_from_geotag` — turunan lokasi assignment dari geotag.
- `progres_sls_by_wilayah` & `progres_sls_tidak_ditemukan` — dukungan rekap progres SLS.

### 📦 Versi
- Aplikasi: **3.2.0** (build **29**).
- Diperbarui di `pubspec.yaml`, `lib/core/config/app_version.dart`, dan `web/version.json`.

> Catatan deploy: agar cek-versi otomatis di aplikasi bekerja, pastikan `version.json` (3.2.0 / build 29) juga terunggah ke server `https://direktori.bpsparepare.id/version.json`.
