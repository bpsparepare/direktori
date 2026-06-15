# Usaha Organik Design

## Ringkasan

Fitur baru `Usaha Organik` ditambahkan sebagai tab utama baru pada aplikasi. Halaman ini menampilkan daftar usaha dari Google Sheets pada spreadsheet `1mYcv_13CRFRfeu5JE5tCnNFtzBK4NJpVVoEtI3ps_po`, worksheet `Sheet1`.

Untuk fase awal, akses data memakai `gsheets` dengan file service account pada asset `assets/sa/sa-account.json`. Target implementasi saat ini adalah Android, lalu data tetap disimpan ke cache lokal agar halaman bisa menampilkan data terakhir saat refresh gagal atau koneksi tidak stabil.

Kolom yang dipakai dari sheet:

- `Nama`
- `Alamat`
- `Keterangan`

## Struktur Navigasi

Tab baru `Usaha Organik` ditambahkan pada bottom navigation di [main_page.dart](file:///Users/nasrul/flutter/direktori/lib/features/map/presentation/pages/main_page.dart).

Urutan akhir navigasi menjadi:

- `Jelajah`
- `Dashboard`
- `Wilayah`
- `Dokumentasi`
- `KBLI`
- `Usaha Organik`

Halaman `Usaha Organik` berada di luar alur peta dan ditampilkan sebagai page overlay seperti `Dashboard`, `Wilayah`, `Dokumentasi`, dan `KBLI`.

## Sumber Data

Sumber data memakai Google Sheets dengan target:

- spreadsheet id: `1mYcv_13CRFRfeu5JE5tCnNFtzBK4NJpVVoEtI3ps_po`
- worksheet: `Sheet1`

Pendekatan utama:

- aplikasi memuat file service account dari asset `assets/sa/sa-account.json`
- aplikasi membuat client `GSheets` langsung di device Android
- aplikasi membuka spreadsheet id target lalu memilih worksheet `Sheet1`
- aplikasi membaca baris sebagai map berdasarkan header sheet
- aplikasi mencari header persis `Nama`, `Alamat`, dan `Keterangan`
- setiap baris berikutnya dipetakan menjadi satu item usaha
- baris yang tidak memiliki nilai `Nama` diabaikan

Prasyarat penting:

- file `assets/sa/sa-account.json` harus tersedia di project
- asset tersebut harus diaktifkan pada `pubspec.yaml`
- spreadsheet target harus dibagikan ke email service account sebagai viewer atau editor

Pendekatan ini dipilih karena saat ini fitur hanya ditargetkan untuk Android, dan project sudah memiliki pola `gsheets + service account asset` pada fitur lain.

## Model Data

Ditambahkan model ringan untuk list usaha organik, misalnya `UsahaOrganikItem`, dengan field:

- `nama`
- `alamat`
- `keterangan`

Model ini hanya fokus pada kebutuhan tampilan list saat ini dan tidak dicampur ke `DirektoriModel` agar batas tanggung jawab tetap jelas.

## Service Dan Cache

Ditambahkan service khusus, misalnya `UsahaOrganikSheetsService`, dengan tanggung jawab:

- memuat credential service account dari asset
- membuka spreadsheet melalui `gsheets`
- memetakan baris sheet menjadi list model
- menyimpan cache lokal hasil fetch terakhir
- membaca cache lokal saat halaman dibuka
- menyimpan waktu update terakhir

Cache lokal mengikuti pola sederhana yang sudah dipakai fitur `KBLI`, memakai `SharedPreferences` dengan dua nilai utama:

- payload daftar usaha organik
- timestamp update terakhir

Perilaku cache:

- saat halaman dibuka, aplikasi mencoba memuat cache terlebih dahulu
- jika cache ada, data langsung ditampilkan agar halaman terasa cepat
- refresh manual akan mengambil data terbaru dari sheet melalui `gsheets` lalu menimpa cache
- jika refresh gagal dan cache masih ada, halaman tetap menampilkan cache terakhir

## Struktur Halaman

Halaman `Usaha Organik` mengikuti pola visual yang sejalan dengan `KBLI`, tetapi lebih sederhana karena kebutuhan datanya berupa list ringkas.

Elemen utama halaman:

- header dengan judul `Usaha Organik`
- kolom pencarian berdasarkan `Nama`, `Alamat`, atau `Keterangan`
- tombol refresh
- informasi status sumber data atau waktu update terakhir
- daftar item usaha
- empty state saat tidak ada data
- error state saat gagal memuat dan cache tidak tersedia

## Tampilan List

Setiap item list menampilkan:

- `Nama` sebagai judul utama
- `Alamat` sebagai subtitle
- `Keterangan` sebagai teks catatan tambahan

Detail visual yang diharapkan:

- list berbentuk card ringan agar konsisten dengan gaya halaman referensi lain
- `Nama` tampil paling menonjol
- `Alamat` tampil satu blok ringkas
- `Keterangan` tampil di bawahnya dengan warna sekunder
- jika `Alamat` atau `Keterangan` kosong, field tersebut tidak perlu dipaksa tampil dengan placeholder

## Pencarian

Pencarian bersifat lokal terhadap data yang sudah dimuat ke aplikasi.

Perilakunya:

- pengguna mengetik pada kolom pencarian
- hasil difilter terhadap gabungan nilai `Nama`, `Alamat`, dan `Keterangan`
- pencarian tidak perlu memanggil Google Sheets ulang
- tombol clear menghapus query dan menampilkan ulang semua item

## Alur Data

1. Pengguna membuka tab `Usaha Organik`.
2. Aplikasi mencoba membaca cache lokal.
3. Jika cache tersedia, data langsung ditampilkan.
4. Jika cache belum ada, aplikasi memuat service account dari asset.
5. Aplikasi membuka spreadsheet dan worksheet `Sheet1` melalui `gsheets`.
6. Aplikasi memvalidasi header wajib `Nama`, `Alamat`, `Keterangan`.
7. Aplikasi memetakan setiap baris menjadi item usaha organik.
8. Aplikasi menyimpan hasil dan waktu update ke cache lokal.
9. Saat pengguna pull-to-refresh atau tekan refresh, aplikasi mengulang proses fetch dan memperbarui cache.

## Error Handling

- Jika sheet tidak bisa diakses dan cache kosong, halaman menampilkan error state dengan tombol `Coba Lagi`.
- Jika refresh gagal tetapi cache tersedia, halaman tetap menampilkan data cache terakhir dan memberi status bahwa refresh gagal.
- Jika header `Nama`, `Alamat`, atau `Keterangan` tidak ditemukan, halaman menampilkan pesan error yang jelas agar struktur sheet bisa segera diperbaiki.
- Jika ada baris yang hanya berisi data kosong, baris tersebut diabaikan.
- Jika file `assets/sa/sa-account.json` tidak ditemukan, halaman menampilkan error yang jelas bahwa credential asset belum tersedia.
- Jika spreadsheet belum dibagikan ke email service account, halaman menampilkan error akses agar izin sheet bisa diperbaiki.

## Batasan Awal

Ruang lingkup fitur awal dibatasi pada:

- menampilkan list usaha dari `Sheet1`
- pencarian lokal
- refresh manual
- cache lokal sederhana
- akses data langsung via `gsheets` untuk Android

Fitur berikut tidak masuk tahap awal:

- edit data ke Google Sheets
- filter lanjutan
- detail page terpisah
- sinkronisasi ke Supabase
- integrasi ke peta
- dukungan web untuk akses service account asset

## Pengujian

Verifikasi minimal setelah implementasi:

- tab `Usaha Organik` muncul di navigasi utama
- halaman berhasil memuat data dari Google Sheets via `gsheets`
- item list menampilkan `Nama`, `Alamat`, dan `Keterangan`
- pencarian lokal bekerja untuk ketiga field
- refresh memperbarui data
- cache lokal dipakai saat aplikasi dibuka ulang atau saat refresh gagal
- error state tampil dengan benar saat sheet tidak bisa diakses dan cache tidak ada
- error state tampil jelas saat asset service account belum tersedia atau izin spreadsheet belum diberikan
