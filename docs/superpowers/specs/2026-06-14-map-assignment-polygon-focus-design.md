# Desain Fokus Wilayah Tugas Dan Toggle Polygon

## Latar Belakang

Sumber `places` untuk peta sudah dipindahkan ke `assignment places` yang dibatasi server-side berdasarkan role dan wilayah tugas petugas. Namun, pengalaman membuka peta masih belum ideal untuk petugas lapangan karena:

- posisi awal peta belum otomatis diarahkan ke wilayah tugas petugas
- batas wilayah tugas dari polygon belum mudah dilihat saat dibutuhkan
- polygon sebenarnya sudah tersedia di aset `assets/geojson/final_sls_optimized_v2.json`, tetapi belum dimanfaatkan sebagai konteks wilayah tugas aktif

Tujuan perubahan ini adalah membuat peta langsung fokus ke area tugas petugas saat dibuka, sambil menyediakan tombol sederhana untuk menampilkan atau menyembunyikan polygon wilayah tugas aktif.

## Tujuan

- Saat halaman peta dibuka, posisi dan zoom awal mengikuti batas gabungan polygon wilayah tugas petugas.
- Polygon wilayah tugas aktif dapat ditampilkan atau disembunyikan lewat satu tombol `Wilayah Tugas`.
- Sumber polygon tetap menggunakan `assets/geojson/final_sls_optimized_v2.json`.
- Mapping wilayah tugas ke polygon menggunakan `se2026_wilayah_tugas.id = polygon.idsls`.
- Perilaku `admin` tetap aman dan tidak dipaksa ke wilayah tertentu.

## Di Luar Cakupan

- Mengubah struktur GeoJSON polygon.
- Menambahkan editor polygon atau fitur geometri baru.
- Membuat panel pemilih SLS baru untuk menyalakan polygon satu per satu.
- Mengubah mekanisme sync `places` yang sudah berjalan lewat RPC.

## Konteks Saat Ini

- `MapBloc` sudah memuat metadata polygon dan mendukung pemilihan polygon tunggal maupun banyak.
- `MapView` sudah memiliki logika `fit bounds` untuk polygon tunggal dan multi-polygon.
- Asset polygon tersedia di `assets/geojson/final_sls_optimized_v2.json`.
- `PolygonData` sudah memiliki `idsls`, yang dapat dipakai untuk dicocokkan ke `se2026_wilayah_tugas.id`.
- `places` sekarang dibatasi berdasarkan wilayah tugas di server melalui RPC Supabase.

Artinya, fondasi visual polygon sebenarnya sudah ada. Perubahan utama yang dibutuhkan adalah menentukan polygon aktif berdasarkan penugasan petugas, lalu menggunakannya untuk fokus awal peta dan overlay opsional.

## Pendekatan Yang Dipilih

Pendekatan yang dipilih adalah:

- posisi awal peta otomatis `fit` ke gabungan bounds semua polygon wilayah tugas aktif
- polygon wilayah tugas tidak langsung digambar saat map terbuka
- satu tombol `Wilayah Tugas` dipakai untuk menampilkan atau menyembunyikan overlay polygon tugas aktif

Alasan pemilihan:

- memenuhi kebutuhan utama agar peta langsung tertuju ke wilayah tugas
- tetap menjaga tampilan awal peta bersih dan ringan
- memanfaatkan arsitektur polygon yang sudah ada tanpa membuat UI baru yang rumit

## Perilaku Produk

### Petugas Pengawas Dan Pendata

- Saat halaman peta dibuka, app mencari semua `idsls` tugas aktif dari `se2026_wilayah_tugas`.
- App mencocokkan `idsls` itu ke polygon pada `final_sls_optimized_v2.json`.
- App menghitung gabungan bounds seluruh polygon tugas aktif.
- Peta langsung menyesuaikan center dan zoom agar seluruh wilayah tugas terlihat.
- Overlay polygon belum tampil di awal.
- Jika tombol `Wilayah Tugas` ditekan, seluruh polygon tugas aktif ditampilkan.
- Jika tombol ditekan lagi, overlay polygon disembunyikan.

### Admin

- `Admin` tidak diarahkan ke wilayah tugas tertentu.
- Posisi awal peta admin tetap mengikuti perilaku global/default yang ada sekarang.
- Tombol `Wilayah Tugas` dapat disembunyikan untuk admin, atau bila tetap tampil harus no-op yang jelas. Untuk tahap ini, rekomendasinya disembunyikan.

## Arsitektur Data

### Sumber Polygon

- Sumber polygon tetap `assets/geojson/final_sls_optimized_v2.json`.
- Asset ini tetap menjadi sumber geometri lokal, bukan diambil dari server.

### Sumber Wilayah Tugas Aktif

- Wilayah tugas aktif berasal dari data `se2026_wilayah_tugas`.
- Untuk kebutuhan UI map, data ini tidak perlu diambil ulang dari Supabase bila profil dan assignment aktif sudah tersedia melalui service yang ada.
- Mapping final:
  - `wilayah_tugas.id` cocok ke `PolygonData.idsls`

### Hasil Turunan

App perlu menghasilkan dua turunan data:

- `assignmentPolygons`
  - semua polygon aktif yang cocok dengan wilayah tugas petugas
- `assignmentBounds`
  - gabungan bounds dari semua polygon aktif

Kedua hasil ini khusus untuk konteks peta, bukan menggantikan `polygonsMeta` global yang sudah ada.

## Perubahan State

### `MapState`

Tambahkan state yang fokus pada wilayah tugas:

- `assignmentPolygons`
  - daftar polygon aktif milik petugas
- `showAssignmentPolygons`
  - boolean untuk menampilkan atau menyembunyikan overlay polygon tugas
- opsional `hasAssignmentFocusApplied`
  - penanda agar auto-focus awal tidak terus mengganggu saat user sudah menggeser peta

State polygon lama tetap dipertahankan karena masih dipakai untuk fitur seleksi polygon biasa.

## Perubahan Event Dan Alur BLoC

### Event Baru

Tambahkan event yang relevan:

- event untuk memuat polygon wilayah tugas aktif
- event untuk toggle overlay polygon tugas
- opsional event untuk menerapkan fokus awal wilayah tugas hanya sekali

### Alur Saat Map Dibuka

1. App memuat metadata polygon seperti biasa dari asset GeoJSON.
2. App menentukan daftar `idsls` wilayah tugas aktif user.
3. BLoC memfilter `polygonsMeta` menjadi `assignmentPolygons`.
4. Jika user bukan admin dan `assignmentPolygons` tidak kosong:
   - hitung bounds gabungan
   - terapkan fokus awal ke wilayah tugas
5. Overlay polygon tetap mati secara default.

### Alur Saat Tombol `Wilayah Tugas` Ditekan

1. Toggle `showAssignmentPolygons`.
2. Jika menjadi aktif:
   - tampilkan semua polygon wilayah tugas aktif
3. Jika menjadi nonaktif:
   - sembunyikan overlay polygon tugas

Toggle ini tidak boleh menghapus seleksi place atau mengubah hasil filter marker.

## Perubahan UI

### `MapControls`

- Tambahkan satu tombol `Wilayah Tugas`.
- Tombol hanya tampil untuk user yang punya wilayah tugas terdefinisi dan bukan admin.
- Status tombol harus jelas:
  - aktif saat polygon tugas ditampilkan
  - nonaktif saat polygon disembunyikan

### `MapView`

- Tambahkan dukungan untuk menggambar `assignmentPolygons` sebagai overlay terpisah.
- Overlay ini tidak menggantikan polygon seleksi manual yang sudah ada.
- Urutan rendering harus menjaga marker tetap mudah dibaca:
  - polygon tugas di bawah marker
  - marker tetap di atas overlay

### Fokus Awal Peta

- Gunakan logika `fit bounds` multi-polygon yang sudah ada atau bentuk ulang menjadi helper reusable.
- Fokus awal wilayah tugas hanya diterapkan saat load awal atau saat belum ada interaksi user yang mengubah view.
- Refresh marker tidak boleh memaksa kamera kembali ke wilayah tugas bila user sudah sedang eksplorasi peta.

## Detail Teknis Yang Direkomendasikan

### Reuse Polygon Metadata Yang Ada

- Hindari memuat ulang file GeoJSON dua kali bila `polygonsMeta` sudah tersedia.
- Gunakan `polygonsMeta` sebagai sumber utama untuk membangun `assignmentPolygons`.
- Jika points polygon belum dimuat penuh untuk item tertentu, isi points dengan helper yang sudah dipakai saat seleksi polygon.

### Matching Wilayah

- Matching harus exact:
  - `polygon.idsls == wilayah_tugas.id`
- Jangan memakai prefix matching untuk polygon.

### Perhitungan Bounds

- Bounds gabungan dihitung dari seluruh titik pada seluruh `assignmentPolygons`.
- Hasilnya dipakai untuk:
  - center awal
  - zoom awal
  - padding agar area tugas tidak menempel ke tepi layar

### Kinerja

- Karena polygon berasal dari asset lokal, filtering harus dilakukan sekali per sesi pembukaan map, lalu disimpan di state.
- Toggle overlay hanya mengubah rendering, bukan memproses ulang asset.

## Error Handling

- Jika wilayah tugas aktif kosong:
  - tombol `Wilayah Tugas` tidak tampil
  - posisi awal peta memakai perilaku default
- Jika polygon asset gagal dimuat:
  - map tetap tampil dengan marker
  - tombol polygon disembunyikan
  - tidak memblokir `places`
- Jika ada `wilayah_tugas.id` yang tidak punya polygon pasangan:
  - polygon itu dilewati
  - fokus awal tetap dihitung dari polygon yang berhasil ditemukan

## Pengujian

- User `pendata` dengan banyak wilayah:
  - peta awal fit ke gabungan polygon tugas
  - tombol `Wilayah Tugas` menampilkan semua polygon tugas aktif
- User `pengawas`:
  - perilaku sama seperti pendata, tetapi berdasarkan assignment pengawas
- User `admin`:
  - peta tetap memakai fokus default/global
  - tombol wilayah tugas tidak tampil
- Wilayah tugas kosong:
  - app tidak crash
  - map tetap membuka view default
- Toggle polygon:
  - on/off tidak mengubah marker yang tampil
  - on/off tidak menghapus seleksi tempat bila tidak perlu
- Refresh marker:
  - tidak memaksa kamera kembali ke focus awal setelah user berpindah view

## Risiko Dan Mitigasi

- Polygon points mungkin belum lengkap saat `polygonsMeta` pertama dimuat.
  Mitigasi: lengkapi points untuk polygon tugas aktif sebelum menghitung bounds.

- Auto-focus awal bisa terasa mengganggu bila terus dipanggil saat state berubah.
  Mitigasi: simpan penanda bahwa fokus awal sudah diterapkan.

- Sebagian `idsls` wilayah tugas mungkin tidak ada di asset polygon.
  Mitigasi: lewati item yang tidak cocok dan hitung bounds dari sisanya.

## Ringkasan Keputusan

- Polygon wilayah tugas berasal dari `assets/geojson/final_sls_optimized_v2.json`.
- Matching polygon memakai `idsls == wilayah_tugas.id`.
- Saat map dibuka, peta otomatis fit ke bounds gabungan polygon wilayah tugas petugas.
- Polygon wilayah tugas tidak tampil otomatis di awal.
- Satu tombol `Wilayah Tugas` dipakai untuk show/hide overlay polygon tugas.
- `Admin` tidak memakai fokus wilayah tugas dan tetap memakai perilaku default peta.
