# Desain FAB Dokumentasi Di Tab Jelajah

## Latar Belakang

Saat ini upload dokumentasi hanya bisa dimulai dari `DokumentasiPage` melalui FAB yang ada di halaman tersebut. Pengguna ingin bisa mengeksekusi aksi yang sama langsung dari tab `Jelajah`, tanpa harus pindah dulu ke halaman dokumentasi.

Sesudah upload berhasil, alur yang diinginkan adalah berpindah ke halaman `Dokumentasi` agar hasil upload dapat langsung dilihat.

## Tujuan

- Menambahkan FAB dokumentasi yang dapat dipakai langsung dari tab `Jelajah`
- Membuka dialog upload dokumentasi secara langsung saat FAB ditekan
- Menghindari duplikasi logic upload antara `MainPage` dan `DokumentasiPage`
- Setelah upload sukses, otomatis berpindah ke halaman `Dokumentasi`

## Di Luar Cakupan

- Mengubah alur upload dokumentasi yang sudah ada di `DokumentasiPage`
- Menambahkan kategori atau field baru pada form upload
- Mengubah struktur penyimpanan atau backend dokumentasi
- Menambahkan state management baru seperti Bloc khusus dokumentasi

## Pendekatan

Pendekatan yang dipilih adalah menaruh FAB khusus di `MainPage` untuk kondisi tab `Jelajah`, lalu mengekstrak dialog upload dokumentasi ke helper bersama yang bisa dipanggil dari `MainPage` maupun `DokumentasiPage`.

Alasan pemilihan:

- Navigasi tab memang dikendalikan oleh `MainPage`
- Reuse dialog lebih aman daripada memanggil method widget lain melalui `GlobalKey`
- Perubahan tetap kecil dan tidak perlu menambah controller atau event bus baru

## Komponen Yang Diubah

### `MainPage`

`MainPage` akan menampilkan FAB dokumentasi hanya saat tab aktif adalah `Jelajah`.

Perilaku FAB:

- tekan FAB
- buka dialog upload dokumentasi
- jika upload sukses, ubah halaman aktif ke `Dokumentasi`
- jika user batal atau upload gagal, tetap di `Jelajah`

### `DokumentasiPage`

`DokumentasiPage` tetap mempertahankan FAB upload yang sudah ada, tetapi dialog upload tidak lagi ditulis eksklusif di halaman ini.

Perubahan:

- gunakan helper/dialog bersama untuk membuka form upload
- setelah upload sukses dari halaman ini, lakukan refresh data seperti perilaku saat ini

### Helper Dialog Upload

Logic UI untuk form upload dokumentasi dipindahkan ke komponen/helper yang dapat dipakai ulang.

Tanggung jawab helper:

- menampilkan dialog upload
- menangani input form
- menjalankan proses pemilihan file atau gambar
- memanggil `DocumentationUploadService`
- mengembalikan hasil `sukses`, `batal`, atau `gagal`

Dengan cara ini, `MainPage` tidak perlu mengetahui detail isi form upload.

## Alur Data

### Dari Tab Jelajah

1. User menekan FAB dokumentasi di `Jelajah`
2. `MainPage` membuka dialog upload bersama
3. User menyelesaikan upload
4. Jika sukses:
   - dialog ditutup
   - `MainPage` berpindah ke halaman `Dokumentasi`
5. Jika batal atau gagal:
   - tetap di `Jelajah`

### Dari Halaman Dokumentasi

1. User menekan FAB upload yang sudah ada
2. `DokumentasiPage` membuka dialog upload bersama
3. Jika sukses:
   - daftar dokumentasi di-refresh
   - user tetap berada di halaman `Dokumentasi`

## Perilaku UI

- FAB dokumentasi di `Jelajah` hanya tampil saat tab `Jelajah` aktif
- Ikon FAB mengikuti konteks dokumentasi, misalnya kamera atau tambah dokumen
- Tidak perlu menampilkan FAB dokumentasi tambahan di tab lain
- Setelah sukses dari `Jelajah`, halaman berpindah ke `Dokumentasi` agar hasil upload langsung terlihat

## Error Handling

- Jika user menutup dialog tanpa upload, tidak ada navigasi
- Jika upload gagal, tampilkan pesan error yang sama seperti alur dokumentasi saat ini
- Jangan pindah ke `Dokumentasi` bila operasi belum sukses
- Pastikan pengecekan `mounted` tetap dipakai sebelum update UI setelah async call

## Pengujian

- Verifikasi FAB dokumentasi muncul di tab `Jelajah`
- Verifikasi FAB tersebut tidak muncul di tab lain
- Verifikasi FAB membuka dialog upload dokumentasi
- Verifikasi upload sukses dari `Jelajah` memindahkan user ke halaman `Dokumentasi`
- Verifikasi upload batal dari `Jelajah` tidak mengubah tab aktif
- Verifikasi upload dari `DokumentasiPage` tetap berjalan seperti sebelumnya
- Verifikasi daftar dokumentasi tetap ter-refresh setelah upload dari halaman dokumentasi

## Risiko Dan Mitigasi

- Duplikasi logic upload jika dialog tidak benar-benar diekstrak
  Mitigasi: pusatkan form dan submit flow di helper tunggal

- Navigasi pindah tab terlalu dini sebelum upload selesai
  Mitigasi: pindah tab hanya setelah helper mengembalikan status sukses

- State halaman dokumentasi tidak menampilkan data terbaru saat baru dibuka
  Mitigasi: trigger refresh saat halaman dokumentasi menjadi tujuan setelah upload sukses, atau refresh saat resume/after-success callback

## Ringkasan Keputusan

- FAB dokumentasi baru ditambahkan di tab `Jelajah`
- FAB langsung membuka dialog upload dokumentasi
- Dialog upload dijadikan komponen/helper bersama
- Setelah upload sukses dari `Jelajah`, app otomatis berpindah ke halaman `Dokumentasi`
- Alur upload lama di `DokumentasiPage` tetap dipertahankan, tetapi memakai helper yang sama
