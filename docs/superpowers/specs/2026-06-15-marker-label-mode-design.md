# Desain Mode Label Marker

## Latar Belakang

Tampilan marker pada peta saat ini selalu menampilkan nama usaha sebagai label. Untuk kebutuhan pengecekan visual di lapangan, pengguna ingin bisa mengganti label marker secara cepat antara `nama usaha` dan `nomor bangunan`.

Perubahan ini hanya dibutuhkan pada marker di peta. Hasil pencarian, daftar tempat, dan detail lain tetap memakai tampilan yang sudah ada.

## Tujuan

- Menambahkan tombol untuk mengganti mode label marker antara `nama` dan `nomor`.
- Mengubah ikon marker saat mode `nomor` aktif menjadi lingkaran hitam.
- Menjaga default tampilan peta tetap memakai mode `nama`.
- Membatasi perubahan hanya pada area peta agar implementasi tetap kecil dan aman.

## Di Luar Cakupan

- Mengubah hasil pencarian di `MainPage`.
- Menyimpan pilihan mode marker ke local storage.
- Menambah mode ketiga seperti `sembunyikan label`.
- Mengubah sumber data assignment places di luar kebutuhan `no_bang`.

## Pendekatan

Pendekatan yang dipilih adalah menaruh state mode label marker secara lokal di `MapView`, lalu menambahkan satu kontrol sederhana di `MapControls` untuk mengganti mode dari `nama` ke `nomor` dan sebaliknya.

Alasan pemilihan:

- Perubahan hanya memengaruhi peta.
- Tidak perlu menambah event atau state baru di `MapBloc`.
- Risiko regresi lebih rendah karena tidak menyentuh alur pencarian atau daftar data lain.

## Komponen Yang Diubah

### Entity `Place`

Entity `Place` perlu membawa informasi `noBang` agar `MapView` bisa merender nomor bangunan tanpa membaca model assignment secara langsung.

Perubahan:

- Tambah field opsional `int? noBang`
- Perbarui `toJson()` dan `fromJson()` agar field baru tetap konsisten

### Mapping Assignment Ke Place

Pada `MapRepositoryImpl`, data `AssignmentPlaceRecord` yang sudah memiliki `noBang` akan diteruskan ke `Place`.

Aturan mapping:

- `name` tetap diisi `namaUsaha`
- `noBang` diisi dari `record.noBang`
- field lain tetap mengikuti struktur sekarang

### `MapView`

`MapView` menjadi pemilik state mode label marker.

Tambahan:

- enum lokal sederhana, misalnya `MarkerLabelMode.nama` dan `MarkerLabelMode.nomor`
- state awal selalu `nama`
- callback baru dari `MapControls` untuk toggle mode

Aturan render:

- Mode `nama`
  - label marker memakai `p.name`
  - ikon marker tetap seperti sekarang
- Mode `nomor`
  - label marker memakai `p.noBang`
  - jika `noBang` kosong, fallback ke `p.name` atau string aman
  - ikon marker berubah menjadi lingkaran hitam

### `MapControls`

Tambahkan satu aksi kontrol baru untuk mengganti mode label marker.

Perilaku tombol:

- sekali tap mengubah dari `nama` ke `nomor`
- tap berikutnya mengubah kembali ke `nama`
- tombol menampilkan state aktif secara jelas, misalnya melalui icon, text, atau tooltip singkat

## Perilaku UI

### Default

- Saat halaman peta dibuka, mode awal selalu `nama`

### Mode Nama

- Marker tetap memakai ikon pin lokasi saat ini
- Label tetap nama usaha

### Mode Nomor

- Marker memakai ikon lingkaran hitam
- Label menampilkan nomor bangunan
- Tujuannya untuk memudahkan inspeksi visual kepadatan atau urutan bangunan di peta

## Fallback

- Jika `noBang` bernilai `null`, label marker pada mode nomor tidak boleh menyebabkan error render
- Fallback yang dipilih bisa:
  - tetap tampilkan `p.name`, atau
  - tampilkan label kosong

Untuk tahap awal, rekomendasi fallback adalah tetap tampilkan `p.name` agar marker tetap mudah dikenali.

## Error Handling

- Jika data `noBang` tidak tersedia pada sebagian marker, peta tetap harus bisa dirender normal
- Toggle mode tidak boleh mengubah selected marker, bounds, atau state peta lainnya

## Pengujian

- Verifikasi mode awal peta adalah `nama`
- Verifikasi tombol dapat mengubah mode `nama` ke `nomor` dan kembali lagi
- Verifikasi marker dalam mode `nama` tetap memakai ikon lama
- Verifikasi marker dalam mode `nomor` memakai ikon bulat hitam
- Verifikasi label marker dalam mode `nomor` menampilkan `noBang`
- Verifikasi marker tanpa `noBang` tetap tampil aman dengan fallback
- Verifikasi hasil pencarian dan layar lain tidak ikut berubah

## Risiko Dan Mitigasi

- `Place` dipakai di tempat lain sehingga penambahan field baru berpotensi menyentuh serialisasi
  Mitigasi: field dibuat opsional dan kompatibel ke belakang

- Tampilan nomor bangunan bisa kurang terbaca bila semua marker rapat
  Mitigasi: tetap gunakan outline teks yang sudah ada dan pertahankan kontrol ukuran font marker

- Perubahan ikon bisa membuat marker selected sulit dibedakan
  Mitigasi: pertahankan perlakuan selected state melalui ukuran, highlight, atau warna border yang tetap konsisten

## Ringkasan Keputusan

- Mode marker hanya berlaku untuk peta
- Default mode adalah `nama`
- Toggle hanya memiliki dua mode: `nama` dan `nomor`
- Saat mode `nomor`, ikon marker berubah menjadi lingkaran hitam
- `Place` ditambah field opsional `noBang` untuk mendukung render label nomor bangunan
