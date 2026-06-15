# Desain Layout Kategori Upload Dokumentasi

## Latar Belakang

Pada dialog upload dokumentasi, pilihan kategori saat ini terasa seperti grid kaku karena setiap card diberi lebar tetap. Akibatnya susunan kategori kurang fleksibel dan tidak mengikuti panjang isi label.

Kebutuhan perubahan ini adalah membuat card kategori lebih natural, dengan lebar yang mengikuti isi masing-masing kategori sehingga susunannya tidak lagi terlihat seperti grid paksa.

## Tujuan

- Mengubah card kategori agar lebar mengikuti isi
- Mempertahankan alur pilihan kategori yang sudah ada
- Menjaga tampilan selected state tetap jelas
- Menghindari perubahan besar pada dialog upload

## Di Luar Cakupan

- Mengubah daftar kategori
- Mengubah backend atau payload upload
- Mengganti komponen kategori menjadi grid atau list penuh
- Mengubah perilaku tombol upload, galeri, atau kamera

## Pendekatan

Pendekatan yang dipilih adalah tetap memakai `Wrap`, tetapi menghapus lebar tetap card kategori dan membiarkan setiap card mengukur dirinya sendiri berdasarkan icon, padding, dan panjang label.

Alasan pemilihan:

- Perubahan kecil dan aman
- Cocok untuk jumlah kategori yang sedikit
- Secara visual tetap rapi pada layar sempit
- Tidak memaksa semua kategori punya ukuran yang sama

## Perubahan Komponen

### Card Kategori

Card kategori akan diubah dari lebar tetap menjadi lebar dinamis.

Perubahan inti:

- hapus `width: 160`
- gunakan padding horizontal yang tetap
- ganti elemen teks agar tidak memaksa card memenuhi lebar tertentu
- pertahankan icon di kiri dan label di kanan
- pertahankan warna border dan background untuk state aktif

### Layout `Wrap`

`Wrap` tetap dipertahankan karena perilakunya sesuai dengan kebutuhan pilihan kategori yang mengalir ke baris berikutnya.

Perilaku yang diharapkan:

- kategori pendek memiliki card yang lebih kecil
- kategori panjang seperti `Bukti Paket Data` memiliki card yang lebih lebar
- ketika ruang horizontal habis, card pindah ke baris berikutnya
- tampilan keseluruhan tidak terasa seperti grid

## Perilaku UI

- tinggi card tetap konsisten antar item
- lebar card mengikuti isi
- selected state tetap terlihat jelas melalui warna background, border, dan icon
- urutan kategori tidak berubah

## Pengujian

- Verifikasi card kategori tidak lagi memakai lebar tetap
- Verifikasi setiap kategori memiliki lebar berbeda sesuai isi label
- Verifikasi `Wrap` tetap memindahkan item ke baris berikutnya saat ruang tidak cukup
- Verifikasi tap kategori tetap mengubah state selected
- Verifikasi kategori dengan label terpanjang tetap terbaca dengan baik

## Risiko Dan Mitigasi

- Card bisa terlalu sempit jika padding terlalu kecil
  Mitigasi: pertahankan padding horizontal dan vertical yang cukup

- Card panjang bisa terlihat terlalu dominan
  Mitigasi: biarkan lebar mengikuti isi, tetapi jaga tipografi dan padding tetap proporsional

- Alignment antar card bisa terasa kurang rapi jika tinggi berubah
  Mitigasi: jaga struktur internal card tetap satu baris dan tinggi konsisten

## Ringkasan Keputusan

- Tetap memakai `Wrap`
- Card kategori diubah menjadi lebar dinamis
- Tampilan kategori tidak lagi terasa seperti grid tetap
- State selected dan interaksi tap tetap sama
