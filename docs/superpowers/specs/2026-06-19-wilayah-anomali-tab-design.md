# Wilayah Anomali Tab Design

## Latar Belakang

Tab `Wilayah` pada halaman utama saat ini menampilkan `WilayahTugasPage`, yaitu daftar wilayah kerja user berdasarkan `se2026_wilayah_tugas`.

Kebutuhan baru adalah menjadikan tab ini sebagai pusat monitoring dan tindak lanjut anomali wilayah. User dengan role `pendata` maupun `pengawas` perlu dapat:

- melihat seluruh temuan anomali pada wilayah tugasnya
- mencari dan memfilter anomali dengan cepat
- membuka detail anomali
- memperbarui status tindak lanjut dari tab ini

Sumber data utama berasal dari:

- `public.se2026_anomali_temuan`
- `public.se2026_anomali_kategori`
- `public.se2026_wilayah_tugas`

Aturan cakupan data yang disepakati adalah berbasis `kode_wilayah` wilayah tugas user, bukan berbasis `assignment_id` langsung.

## Tujuan

- Mengganti isi tab `Wilayah` dari daftar wilayah kerja menjadi daftar anomali wilayah
- Menampilkan anomali untuk `pendata` dan `pengawas` berdasarkan seluruh `kode_wilayah` pada wilayah tugas user login
- Menyediakan detail anomali yang cukup untuk pemeriksaan lapangan
- Memungkinkan user memperbarui `status_tindak_lanjut` dan `catatan_petugas`
- Mempertahankan pola arsitektur halaman utama yang sudah ada di `main_page.dart`

## Di Luar Scope

- Mendesain ulang struktur `BottomNavigationBar`
- Mengubah logika dasar `MapPage` sebagai base layer
- Mengubah skema database yang sudah diberikan
- Menambah workflow approval terpisah antara `pendata` dan `pengawas`
- Menambah sinkronisasi offline khusus untuk anomali pada tahap ini

## Pendekatan Terpilih

Pendekatan yang dipilih adalah mengganti `WilayahTugasPage` pada `IndexedStack` dengan halaman baru, misalnya `WilayahAnomaliPage`, yang langsung menampilkan daftar anomali.

Pendekatan ini dipilih karena:

- paling sesuai dengan kebutuhan user untuk melihat anomali secara langsung
- mengurangi satu langkah navigasi dibanding model wilayah lalu detail
- cocok untuk monitoring dan tindak lanjut cepat di lapangan
- perubahan terlokalisasi pada satu tab tanpa perlu mengubah struktur navigasi utama

## Arsitektur Data

### Identifikasi User Aktif

Halaman mengambil profil user aktif memakai service existing yang saat ini sudah digunakan oleh `WilayahTugasPage`, yaitu melalui `fetchCurrentSe2026Profile()`.

Informasi minimum yang dibutuhkan:

- `petugasId`
- `role`
- status aktif user

Jika profil tidak ditemukan atau tidak aktif, halaman menampilkan empty state atau informasi bahwa penugasan tidak tersedia.

### Resolusi Wilayah Tugas

Halaman mengambil seluruh wilayah tugas user melalui `fetchCurrentUserWilayahTugas()`.

Hasil ini dipakai untuk membentuk daftar `kode_wilayah` yang menjadi filter utama query anomali.

Aturan filtering:

- `pengawas`: mengikuti wilayah tugas yang terkait `pml_id`
- `pendata`: mengikuti wilayah tugas yang terkait `ppl_id`
- semua anomali yang `kode_wilayah`-nya termasuk dalam hasil wilayah tugas tersebut ditampilkan

### Query Anomali

Service baru ditambahkan untuk mengambil anomali dari `se2026_anomali_temuan` dengan karakteristik:

- filter `kode_wilayah IN (...)`
- urut default berdasarkan `created_at desc`
- dapat difilter lagi di level query atau client state untuk `status_tindak_lanjut` dan `scope`
- mengambil field inti:
  - `id`
  - `anomali_id`
  - `scope`
  - `assignment_id`
  - `kode_wilayah`
  - `nama`
  - `wilayah`
  - `keterangan`
  - `detail`
  - `status_tindak_lanjut`
  - `catatan_petugas`
  - `diperiksa_oleh`
  - `diperiksa_at`
  - `created_at`

Untuk menampilkan label kategori yang lebih ramah, query juga perlu menggabungkan atau melengkapi data dari `se2026_anomali_kategori` berdasarkan `anomali_id`, minimal:

- `kategori`
- `deskripsi_rule`

### Update Tindak Lanjut

Service baru juga menangani update anomali ketika user menyimpan perubahan dari detail.

Field yang diupdate:

- `status_tindak_lanjut`
- `catatan_petugas`
- `diperiksa_oleh`
- `diperiksa_at`

Asumsi operasional pada tahap ini:

- `pendata` dan `pengawas` sama-sama boleh memperbarui status
- identitas pemeriksa diisi dari identitas user aktif yang tersedia di aplikasi
- field `keterangan`, `detail`, `nama`, dan `wilayah` hanya dibaca, tidak diedit dari tab ini

## Struktur UI

### Komposisi Halaman

Halaman baru `WilayahAnomaliPage` menggantikan `WilayahTugasPage` pada `main_page.dart`.

Struktur utama halaman:

- hero/header ringkas
- kartu ringkasan statistik
- area pencarian dan filter
- daftar anomali
- detail sheet atau dialog aksi

### Header

Header menjelaskan bahwa halaman menampilkan anomali pada wilayah tugas user aktif.

Informasi yang ditampilkan:

- nama modul, misalnya `Anomali Wilayah`
- role user aktif
- jumlah anomali yang sedang dimuat

Header tetap ringan agar fokus utama tetap pada daftar anomali.

### Ringkasan

Bagian ringkasan menampilkan metrik cepat:

- total anomali
- jumlah wilayah terdampak
- jumlah `belum_diperiksa`
- jumlah anomali yang sudah memiliki status tindak lanjut selain default

Ringkasan ini membantu user memindai beban kerja tanpa perlu membuka filter lebih dulu.

### Pencarian dan Filter

Filter minimum yang didukung:

- pencarian teks bebas untuk `nama`, `wilayah`, `keterangan`, `detail`, dan `kode_wilayah`
- filter `status_tindak_lanjut`
- filter `scope`

Nilai status yang tersedia:

- `belum_diperiksa`
- `dikonfirmasi_valid`
- `dikonfirmasi_salah_entri`
- `sudah_diperbaiki`

Filter bekerja di state halaman dan dapat diterapkan kembali setiap refresh.

### Daftar Anomali

Setiap item daftar menampilkan informasi inti yang mudah dipindai:

- nama entitas (`nama`)
- wilayah
- kode wilayah
- kategori anomali
- ringkasan `keterangan`
- chip status tindak lanjut
- chip `scope`

Urutan visual:

1. nama dan status
2. wilayah dan kode wilayah
3. kategori / scope
4. keterangan singkat
5. metadata pemeriksaan terakhir bila ada

### Detail dan Aksi

Saat item dipilih, aplikasi membuka detail aksi. Bentuk default yang direkomendasikan adalah `showModalBottomSheet` full-height atau hampir full-height karena:

- konsisten dengan interaksi cepat di mobile
- menjaga konteks daftar
- cukup untuk menampilkan detail dan form ringan

Isi detail:

- kategori
- deskripsi rule
- keterangan
- detail tambahan
- nama
- wilayah
- kode wilayah
- assignment id bila diperlukan untuk referensi
- status tindak lanjut saat ini
- catatan petugas
- informasi pemeriksaan terakhir

Form aksi:

- dropdown atau pilihan status
- text area catatan petugas
- tombol simpan

Saat simpan:

1. validasi input minimum
2. kirim update ke Supabase
3. refresh item atau list
4. tampilkan status berhasil/gagal

## Komponen Yang Diubah

### `main_page.dart`

Perubahan hanya pada halaman yang dipasang untuk index `Wilayah` di `IndexedStack`.

Sebelumnya:

- `const WilayahTugasPage()`

Sesudahnya:

- `const WilayahAnomaliPage()`

Label bottom nav `Wilayah` tetap dipertahankan agar navigasi utama tidak berubah.

### Service Supabase

Service existing diperluas dengan method baru, misalnya:

- `fetchAnomaliTemuanByCurrentUserWilayah()`
- `updateAnomaliTemuanTindakLanjut(...)`

Tujuan pemisahan ini:

- menjaga query anomali tetap terenkapsulasi
- reuse logika profil dan wilayah tugas yang sudah ada
- memudahkan pengujian dan pemeliharaan

### Model Presentasi

Perlu model atau mapper baru untuk merepresentasikan gabungan data `se2026_anomali_temuan` dan `se2026_anomali_kategori`.

Model minimum perlu memuat:

- identitas anomali
- isi deskriptif untuk tampilan
- metadata status tindak lanjut

## Alur Interaksi

### Saat Halaman Dibuka

1. ambil profil user aktif
2. ambil wilayah tugas user
3. bentuk daftar `kode_wilayah`
4. ambil anomali untuk daftar wilayah tersebut
5. tampilkan ringkasan dan daftar

### Saat User Mencari atau Memfilter

1. state filter diperbarui
2. daftar terfilter dihitung ulang
3. jumlah hasil diperbarui di header daftar

### Saat User Memperbarui Status

1. user membuka detail item
2. user memilih status baru dan mengisi catatan bila perlu
3. aplikasi menyimpan perubahan
4. `diperiksa_at` dan `diperiksa_oleh` ikut diperbarui
5. daftar direfresh agar status terbaru langsung terlihat

## Error Handling

- Jika profil user tidak aktif, tampilkan state informatif dan jangan jalankan query anomali
- Jika wilayah tugas kosong, tampilkan empty state bahwa belum ada wilayah penugasan
- Jika query anomali gagal, tampilkan error state dengan tombol `Muat ulang`
- Jika update status gagal, tampilkan `SnackBar` error dan pertahankan input user selama sheet masih terbuka
- Jika data kategori tidak ditemukan untuk `anomali_id` tertentu, item tetap tampil dengan fallback label seperti `Kategori tidak tersedia`

## Verifikasi

Verifikasi manual minimum:

- tab `Wilayah` menampilkan halaman anomali, bukan daftar wilayah tugas lama
- `pendata` hanya melihat anomali pada wilayah tugasnya
- `pengawas` hanya melihat anomali pada wilayah tugasnya
- pencarian teks bekerja untuk nama dan wilayah
- filter status dan scope bekerja
- detail anomali dapat dibuka
- update status berhasil mengubah data di Supabase
- nilai `diperiksa_at` dan `diperiksa_oleh` ikut terisi saat update
- empty state dan error state tampil dengan benar

## Risiko

- Query `IN` terhadap banyak `kode_wilayah` bisa membesar bila user memiliki wilayah tugas sangat banyak
- Join atau pemetaan kategori bisa menambah kompleksitas parsing response
- Bila identitas pemeriksa tidak tersedia lengkap di client, field `diperiksa_oleh` perlu fallback yang konsisten
- Bila tidak ada pagination, daftar anomali besar dapat membuat UI berat

Mitigasi awal:

- urutkan dan batasi hasil jika diperlukan
- mulai dari filter dasar tanpa pagination kompleks
- simpan mapper data pada layer service agar UI tetap sederhana

## Keputusan Desain

- tab `Wilayah` berubah fungsi menjadi daftar anomali wilayah
- cakupan data berbasis `kode_wilayah` milik wilayah tugas user
- `pendata` dan `pengawas` sama-sama dapat melihat dan memperbarui status
- aksi edit dibatasi pada tindak lanjut, bukan perubahan isi anomali mentah
- interaksi detail menggunakan sheet mobile-friendly agar cepat dipakai di lapangan
