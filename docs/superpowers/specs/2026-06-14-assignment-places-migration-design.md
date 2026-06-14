# Desain Migrasi Assignment Places

## Latar Belakang

Saat ini alur `places` untuk peta, pencarian, dan daftar marker masih bertumpu pada cache lokal `groundcheck_list` melalui `GroundcheckSupabaseService`. Sumber tersebut tidak lagi sesuai dengan kebutuhan baru karena daftar tempat yang ingin ditampilkan harus mengikuti penugasan aktif pengguna berdasarkan `fullcode_subsls`.

Sumber data baru yang akan dipakai adalah view `v_assignment_places`, yang sudah menyediakan data lokasi valid beserta kolom `fullcode_subsls`. Kode penugasan aktif pengguna berasal dari tabel `se2026_wilayah_tugas`. Data yang tampil di aplikasi harus dibatasi hanya untuk `places` dengan `fullcode_subsls` yang cocok dengan wilayah tugas aktif pengguna.

Pengguna juga menginginkan model akses yang hemat beban:

- cache lokal tetap menjadi sumber utama saat aplikasi dibuka,
- sinkronisasi dibagi menjadi dua mode, yaitu incremental dan full,
- data lama boleh tetap tersimpan di cache, tetapi UI hanya menampilkan data yang masih cocok dengan penugasan aktif,
- peta dan daftar `places` sementara bersifat read-only tanpa edit atau drag marker.

## Tujuan

- Memindahkan seluruh sumber `places` dari alur lama berbasis `groundcheck_list` ke `v_assignment_places`.
- Menentukan akses `places` berdasarkan `fullcode_subsls` yang berasal dari `se2026_wilayah_tugas`.
- Menjadikan cache lokal sebagai sumber utama saat startup dan saat offline.
- Menyediakan dua jenis sinkronisasi:
  - incremental untuk mengambil perubahan yang belum masuk cache,
  - full untuk mengambil ulang seluruh data assignment aktif.
- Menyederhanakan tampilan marker menjadi satu jenis marker read-only.

## Di Luar Cakupan

- Menghapus atau memigrasikan seluruh fitur operasional `groundcheck_list` di halaman lain yang belum dipindah.
- Menambahkan database lokal baru seperti `sqflite`, `isar`, atau `hive`.
- Menjaga fitur edit koordinat, drag marker, hapus marker, atau mutasi data tempat pada fase migrasi ini.
- Mendesain ulang tampilan UI besar-besaran di luar penyesuaian yang diperlukan untuk mode read-only.

## Pendekatan

Pendekatan yang dipilih adalah menambah source baru khusus `assignment places`, lalu memindahkan seluruh alur `places` ke source tersebut tanpa mengubah service lama secara total.

Alasan pemilihan:

- Risiko lebih kecil dibanding mengganti langsung `GroundcheckSupabaseService` yang saat ini dipakai banyak fitur lain.
- Batas tanggung jawab menjadi jelas antara data lama berbasis `groundcheck_list` dan data baru berbasis assignment.
- Migrasi dapat dilakukan bertahap pada domain `places` tanpa merusak halaman lain yang belum ikut dipindah.

## Perubahan Arsitektur

### Source Data Baru

- Tambah service baru, misalnya `AssignmentPlacesService`, yang bertanggung jawab untuk:
  - mengambil profil dan wilayah tugas aktif pengguna,
  - menurunkan daftar `fullcode_subsls` aktif,
  - mengambil data dari `v_assignment_places`,
  - membaca dan menulis cache lokal assignment places,
  - mengelola metadata sinkronisasi.

- Service lama `GroundcheckSupabaseService` tetap dipertahankan untuk fitur lain yang belum dimigrasikan.

### Model Baru

- Tambah model baru, misalnya `AssignmentPlaceRecord`, untuk memetakan kolom:
  - `id`
  - `idsbr`
  - `nama_usaha`
  - `alamat`
  - `kode_usaha`
  - `status_text`
  - `latitude`
  - `longitude`
  - `source_modified_at`
  - `last_seen_at`
  - `updated_at`
  - `fullcode_subsls`

- Model tersebut dikonversi ke entity `Place` agar layer `MapBloc`, `MapPage`, `MapView`, dan pencarian tetap memakai kontrak data yang sudah ada.

### Cache Lokal Baru

- Tambah cache lokal terpisah, misalnya file `assignment_places_cache.json`.
- Tambah metadata lokal terpisah, misalnya:
  - `assignment_places_last_sync_time`
  - `assignment_places_last_full_sync_time`
  - `assignment_places_assignment_codes_hash`
  - `assignment_places_last_assignment_codes`

Cache baru harus dipisahkan dari cache `groundcheck_list` lama agar migrasi aman dan tidak mencampur dua schema data yang berbeda.

### Repository

- `MapRepository.getPlaces()`, `refreshPlaces()`, dan `downloadFullPlaces()` dipindahkan untuk memakai source baru.
- `MapRepository.getPlacesInBounds()` tetap dipertahankan, tetapi bekerja di atas cache assignment places yang sudah aktif.
- Nama method lama dapat dipertahankan agar perubahan pada `MapBloc` dan use case tetap kecil, walau implementasi internalnya sudah berpindah source.

## Alur Data

### Saat aplikasi dibuka

1. Aplikasi membaca cache lokal assignment places.
2. Aplikasi membaca metadata penugasan terakhir yang tersimpan.
3. Aplikasi mengambil wilayah tugas aktif pengguna dari `se2026_wilayah_tugas`.
4. Aplikasi membentuk daftar `fullcode_subsls` aktif.
5. UI menampilkan hanya data cache yang `fullcode_subsls`-nya cocok dengan assignment aktif.
6. Jika cache kosong, UI dapat tetap kosong sampai pengguna melakukan sync atau fallback awal diputuskan di implementasi.

### Filter penugasan aktif

- Data yang tampil di UI tidak diambil dari seluruh cache, tetapi dari subset cache yang cocok dengan assignment aktif saat ini.
- Data cache lama yang tidak lagi match penugasan aktif tetap disimpan secara fisik.
- Bila assignment aktif berubah, UI langsung menyesuaikan hasil filter tanpa harus menghapus semua cache lama.

### Sync incremental

1. Ambil wilayah tugas aktif pengguna.
2. Bentuk daftar `fullcode_subsls` aktif.
3. Ambil `last_sync_time` dari metadata lokal.
4. Query `v_assignment_places` untuk `fullcode_subsls` aktif dengan filter perubahan sejak `last_sync_time`.
5. Merge hasil ke cache lokal berdasarkan key stabil, idealnya `id` atau `idsbr`.
6. Simpan metadata sync terbaru.
7. UI tetap hanya menampilkan item hasil filter assignment aktif.

Mode ini dipakai untuk mengambil data yang belum pernah masuk atau data yang sudah berubah, sehingga lebih ringan dari full download.

### Sync full

1. Ambil wilayah tugas aktif pengguna.
2. Bentuk daftar `fullcode_subsls` aktif.
3. Query `v_assignment_places` untuk seluruh assignment aktif tanpa filter waktu.
4. Bangun ulang set data aktif untuk assignment tersebut.
5. Perbarui cache lokal dan metadata sync.
6. UI menampilkan ulang subset aktif hasil sync penuh.

Mode ini dipakai saat pengguna ingin memastikan seluruh data assignment aktif diperbarui sepenuhnya.

## Aturan Cache

- Cache lokal menjadi sumber utama saat startup dan saat perangkat offline.
- Data lama di cache boleh tetap disimpan walau sudah tidak termasuk assignment aktif sekarang.
- UI tidak boleh menampilkan data lama yang tidak cocok dengan assignment aktif.
- Untuk menjaga implementasi tetap jelas, cache disarankan dipahami sebagai dua lapisan:
  - `raw cached places`: seluruh data yang pernah diunduh,
  - `active visible places`: hasil filter berdasarkan assignment aktif saat ini.

## Query Dan Akses Data

### Sumber penugasan

- Penugasan aktif pengguna diambil dari `se2026_wilayah_tugas`.
- Role pengguna tetap menentukan filter penugasan:
  - `pengawas` berdasarkan `pml_id`,
  - `pendata` berdasarkan `ppl_id`.

### Sumber places

- Daftar tempat diambil dari `v_assignment_places`.
- Query harus dibatasi hanya untuk `fullcode_subsls` yang termasuk penugasan aktif.
- Karena `v_assignment_places` sudah memfilter koordinat valid, client cukup tetap menjaga fallback aman untuk data rusak atau null yang lolos secara tak terduga.

### Pertimbangan performa

- Jika daftar `fullcode_subsls` aktif sedikit, filter `in` di client query masih dapat diterima.
- Jika daftar assignment aktif besar, lebih aman mempertimbangkan RPC atau view turunan agar join/filter wilayah tugas dilakukan di sisi database.
- Untuk tahap migrasi awal, implementasi boleh dimulai dari query langsung yang memanfaatkan daftar `fullcode_subsls`, lalu dioptimalkan bila ukuran data nyata menunjukkan beban tinggi.

## Dampak Ke UI

### Peta

- Peta menjadi read-only untuk marker assignment places.
- Marker tidak bisa digeser.
- Aksi edit koordinat, hapus marker, dan mutasi marker dinonaktifkan sementara.
- Tap marker tetap boleh dipakai untuk fokus lokasi atau menampilkan detail ringan.

### Marker

- Semua marker dianggap satu jenis data.
- Logika pemisahan marker `gc:` dan non-`gc:` di `MapView` dihapus atau dinonaktifkan.
- Tampilan marker disederhanakan menjadi satu warna/icon utama yang tidak bergantung pada `gcsResult`.

### Pencarian

- Pencarian di `MainPage` tetap memakai `Place`, tetapi sumber datanya berubah menjadi cache assignment places aktif.
- Hasil pencarian hanya boleh berasal dari assignment aktif yang sedang berlaku.

### Filter bounds

- `PlacesInBoundsRequested` tetap dipertahankan untuk membatasi marker yang ditampilkan sesuai area peta yang sedang terlihat.
- Filtering bounds tetap dilakukan di atas cache data aktif lokal agar render marker tetap efisien.

## Error Handling

- Jika gagal mengambil `se2026_wilayah_tugas`, aplikasi memakai assignment terakhir yang tersimpan di metadata lokal jika tersedia.
- Jika gagal sync `v_assignment_places`, aplikasi tetap menampilkan cache lokal terakhir.
- Jika pengguna tidak memiliki penugasan aktif, UI menampilkan state kosong yang jelas, bukan error teknis mentah.
- Jika parsing cache gagal, cache dianggap tidak valid dan diabaikan.
- Jika ada record dengan data penting tidak valid, record dilewati dan proses lain tetap berjalan.

## Tahap Migrasi

1. Tambah source baru `assignment places`, model baru, cache baru, dan metadata sync.
2. Pindahkan implementasi `MapRepository.getPlaces()`, `refreshPlaces()`, dan `downloadFullPlaces()` ke source baru.
3. Sederhanakan `MapView` dan alur marker menjadi satu jenis marker read-only.
4. Nonaktifkan aksi edit, drag, hapus, dan mutasi marker yang masih bergantung pada source lama.
5. Pindahkan pencarian dan daftar `places` agar seluruhnya memakai cache assignment aktif.
6. Audit fitur lain yang masih memakai `groundcheck_list` agar tidak ikut rusak selama migrasi.

## Pengujian

- Verifikasi user dengan assignment aktif hanya melihat marker dengan `fullcode_subsls` yang cocok.
- Verifikasi incremental sync hanya menambahkan atau memperbarui data yang berubah.
- Verifikasi full sync mengambil ulang seluruh data assignment aktif.
- Verifikasi perubahan assignment tidak menghapus cache lama, tetapi UI hanya menampilkan assignment aktif terbaru.
- Verifikasi aplikasi tetap bisa membuka peta dan pencarian saat offline dengan cache yang tersedia.
- Verifikasi marker tidak bisa digeser dan aksi edit tidak aktif.
- Verifikasi `getPlacesInBounds()` tetap memfilter marker lokal sesuai area peta.

## Risiko Dan Mitigasi

- Ketergantungan lama ke `GroundcheckSupabaseService` masih tersebar di beberapa halaman.
  Mitigasi: batasi migrasi hanya ke domain `places` dan audit setiap pemanggilan sebelum mengganti source global.

- Query berdasarkan daftar `fullcode_subsls` dapat menjadi berat bila assignment aktif terlalu banyak.
  Mitigasi: mulai dengan pendekatan query langsung, lalu siapkan opsi RPC atau view yang lebih spesifik bila dibutuhkan.

- Cache menyimpan data historis yang tidak lagi aktif sehingga ukuran file dapat membesar.
  Mitigasi: untuk tahap awal diterima; bila ukuran cache membesar signifikan, tambahkan strategi pruning pada fase berikutnya.

- Pengguna bisa melihat data cache lama saat assignment server gagal diambil.
  Mitigasi: tampilkan status sumber data dan gunakan metadata assignment terakhir secara eksplisit agar perilaku dapat dipahami.

## Ringkasan Keputusan

- Seluruh `places` pindah ke `v_assignment_places`.
- Filter akses berbasis `fullcode_subsls` dari `se2026_wilayah_tugas`.
- Cache lokal tetap menjadi sumber utama.
- Sync dibagi menjadi incremental dan full.
- Cache lama tetap boleh tersimpan, tetapi UI hanya menampilkan data yang cocok dengan assignment aktif.
- Peta dan marker sementara bersifat read-only.
