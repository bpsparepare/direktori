# Desain RPC Assignment Places

## Latar Belakang

Migrasi `places` ke `v_assignment_places` sudah berjalan, tetapi pembatasan wilayah tugas masih berisiko bila dikerjakan di sisi client. Aplikasi masih perlu mengetahui role pengguna, mengambil wilayah tugas, membangun prefix `fullcode_subsls`, lalu melakukan filter lokal. Pendekatan ini kurang ideal untuk performa dan keamanan karena client berpotensi mengambil data lebih luas dari yang semestinya.

Untuk mempercepat query dan memastikan pembatasan akses dilakukan langsung di database, logika filter akan dipindahkan ke Supabase dalam bentuk RPC Postgres. View `v_assignment_places` tetap dipertahankan sebagai sumber data dasar, lalu RPC akan menjadi lapisan final yang mengembalikan `places` sesuai role dan wilayah tugas pengguna yang sedang login.

## Tujuan

- Memindahkan filter role dan wilayah tugas dari client ke database.
- Membuat `admin`, `pengawas`, dan `pendata` mendapatkan daftar `places` yang benar langsung dari server.
- Menyediakan satu RPC yang mendukung mode `full` dan `incremental`.
- Mengurangi jumlah data yang diambil client agar sync lebih cepat dan cache lokal lebih efisien.

## Di Luar Cakupan

- Mendesain ulang struktur tabel `se2026_wilayah_tugas`.
- Menghapus `v_assignment_places` yang sudah ada.
- Menambahkan Edge Function untuk kasus ini.
- Mengubah domain UI selain penyesuaian client agar memanggil RPC baru.

## Pendekatan

Pendekatan yang dipilih adalah mempertahankan `v_assignment_places` sebagai view dasar, lalu menambahkan satu RPC baru di Supabase yang menjadi titik akses resmi untuk sync assignment places.

Alasan pemilihan:

- View tetap berguna untuk menyederhanakan bentuk data dasar.
- RPC lebih tepat untuk logika dinamis berbasis user, role, dan mode sync.
- Satu RPC dengan parameter mode lebih mudah dipelihara dibanding banyak endpoint/logika client.

## Komponen

### View Dasar

- `v_assignment_places` tetap dipakai sebagai sumber row `places` yang sudah valid koordinatnya.
- View ini tidak perlu mengetahui role pengguna.
- Semua pembatasan akses dilakukan di lapisan RPC.

### RPC Baru

- Tambah function Postgres, misalnya `get_assignment_places_for_current_user`.
- RPC berjalan berdasarkan user Supabase yang sedang login, sehingga app tidak perlu mengirim role secara manual.
- Parameter minimum:
  - `p_sync_mode text`
  - `p_modified_after timestamptz default null`

### Sumber Role dan Identitas

- RPC mencari `auth.uid()` dari session aktif.
- RPC mencari `users.id` berdasarkan `auth_uid`.
- RPC mencari `se2026_petugas` berdasarkan `user_id`.
- Dari `se2026_petugas`, RPC mengambil:
  - `id`
  - `role`
  - `is_active`

### Sumber Wilayah Tugas

- Untuk `pengawas`, wilayah tugas diambil dari `se2026_wilayah_tugas` dengan `pml_id = petugas.id`.
- Untuk `pendata`, wilayah tugas diambil dari `se2026_wilayah_tugas` dengan `ppl_id = petugas.id`.
- Untuk `admin`, tidak ada filter wilayah tugas.

## Aturan Role

### Admin

- Mengembalikan semua row dari `v_assignment_places`.
- Jika `p_sync_mode = 'incremental'`, tambahkan filter `source_modified_at > p_modified_after`.
- Jika `p_sync_mode = 'full'`, kembalikan semua row valid.

### Pengawas

- Mengembalikan hanya row dari `v_assignment_places` yang cocok dengan wilayah tugas berdasarkan `pml_id`.
- Matching dilakukan di SQL dengan membandingkan `fullcode_subsls` terhadap gabungan kode wilayah tugas yang relevan.
- Untuk mode incremental, tambahkan filter `source_modified_at > p_modified_after`.

### Pendata

- Mengembalikan hanya row dari `v_assignment_places` yang cocok dengan wilayah tugas berdasarkan `ppl_id`.
- Matching dilakukan di SQL dengan aturan yang sama seperti pengawas.
- Untuk mode incremental, tambahkan filter `source_modified_at > p_modified_after`.

### User Tidak Valid

- Jika user tidak login, tidak punya record `users`, tidak punya `se2026_petugas`, atau `is_active = false`, RPC mengembalikan hasil kosong.

## Aturan Matching Wilayah

- Sumber `places` memiliki `fullcode_subsls`.
- Sumber wilayah tugas memiliki komponen:
  - `kode_prov`
  - `kode_kab`
  - `kode_kec`
  - `kode_desa`
  - `kode_sls`
  - `kode_subsls`

RPC harus membangun kode wilayah tugas dari komponen tersebut di server, bukan di client. Matching dilakukan terhadap `fullcode_subsls` pada `v_assignment_places`.

Untuk tahap awal, aturan matching yang dipakai adalah prefix match dari gabungan komponen kode wilayah tugas yang tidak kosong. Bila nanti ditemukan format nyata `fullcode_subsls` berbeda dari asumsi ini, penyesuaian dilakukan di function SQL tanpa perlu mengubah client lagi.

## Kontrak RPC

### Input

- `p_sync_mode`
  - nilai valid: `full`, `incremental`
- `p_modified_after`
  - dipakai hanya saat mode `incremental`
  - boleh `null`

### Output

RPC mengembalikan shape data yang sama atau setara dengan `v_assignment_places`, minimal:

- `id`
- `workspace_key_hash`
- `survey_period_id`
- `assignment_id`
- `idsbr`
- `nama_usaha`
- `alamat`
- `kode_usaha`
- `status_text`
- `latitude`
- `longitude`
- `modified`
- `source_modified_at`
- `last_seen_at`
- `updated_at`
- `fullcode_subsls`

Dengan output ini, client dapat langsung memetakan hasil RPC ke `AssignmentPlaceRecord` tanpa transformasi besar.

## Alur Data

### Full Sync

1. App memanggil RPC dengan `p_sync_mode = 'full'`.
2. Database menentukan identitas user aktif.
3. Database menentukan role dan wilayah tugas yang relevan.
4. Database mengembalikan semua `places` sesuai scope role.
5. App menyimpan hasil ke cache lokal assignment places.

### Incremental Sync

1. App memanggil RPC dengan `p_sync_mode = 'incremental'` dan `p_modified_after`.
2. Database menentukan identitas user aktif.
3. Database menentukan role dan wilayah tugas yang relevan.
4. Database hanya mengembalikan `places` sesuai scope role yang berubah setelah waktu tersebut.
5. App melakukan merge ke cache lokal.

## Perubahan Client

### `AssignmentPlacesService`

- Hapus logika role dan scope yang saat ini dihitung di client.
- Hapus kebutuhan membangun prefix wilayah tugas di app.
- Ganti query ke `v_assignment_places` menjadi pemanggilan RPC.
- Metadata lokal tetap dipertahankan untuk `last_sync_time` dan cache.

### Cache Lokal

- Cache lokal tetap dipakai sebagai sumber utama saat offline.
- Karena hasil RPC sudah dibatasi di server, client tidak perlu lagi menahan banyak data lintas scope.
- Fallback cache tetap boleh dipakai, tetapi kini lebih kecil risiko salah scope karena data dari server sudah dibatasi sejak awal.

## Error Handling

- Jika RPC gagal, app tetap menampilkan cache lokal terakhir.
- Jika mode incremental dipanggil tanpa `p_modified_after`, RPC dapat memperlakukan sebagai full atau menganggap seluruh data eligible; implementasi harus memilih satu perilaku eksplisit.
- Jika `p_sync_mode` invalid, RPC harus melempar error yang jelas.
- Jika user tidak memiliki otorisasi atau petugas aktif, hasil harus kosong, bukan error internal yang bocor ke client.

## Keamanan

- Role tidak boleh dipercaya dari parameter client.
- Penentuan user dilakukan dari session database melalui `auth.uid()`.
- Filter wilayah tugas dilakukan di sisi database untuk mencegah client mengunduh data di luar scope.
- Bila diperlukan, RPC dapat dibuat `security definer` dengan pengamanan eksplisit agar hanya mengembalikan data yang semestinya.

## Pertimbangan Performa

- RPC mengurangi kebutuhan client untuk menjalankan banyak query per prefix wilayah.
- Untuk `pengawas` dan `pendata`, join/filter dilakukan langsung di database sehingga network payload lebih kecil.
- Untuk `admin`, mode full berpotensi besar, tetapi tetap lebih baik dikendalikan dari server dan bisa dioptimalkan kemudian dengan indeks atau pembatasan batch.

## Pengujian

- Verifikasi `admin` menerima semua `places`.
- Verifikasi `pengawas` hanya menerima `places` yang cocok dengan wilayah `pml_id`.
- Verifikasi `pendata` hanya menerima `places` yang cocok dengan wilayah `ppl_id`.
- Verifikasi user nonaktif atau tanpa petugas menerima hasil kosong.
- Verifikasi `incremental` hanya mengembalikan row yang berubah setelah `p_modified_after`.
- Verifikasi `full` mengembalikan seluruh row sesuai scope role.
- Verifikasi shape output tetap cocok dengan model client.

## Risiko dan Mitigasi

- Format `fullcode_subsls` mungkin tidak identik dengan asumsi gabungan kode wilayah tugas.
  Mitigasi: lakukan validasi dengan beberapa sampel data nyata dan sesuaikan matching di SQL.

- `Admin` full sync bisa menghasilkan payload besar.
  Mitigasi: terima untuk tahap awal, lalu evaluasi pagination atau batching jika diperlukan.

- Perpindahan logika dari client ke server dapat menimbulkan perbedaan hasil sementara.
  Mitigasi: jadikan RPC sebagai single source of truth dan sederhanakan client setelah RPC aktif.

## Ringkasan Keputusan

- `v_assignment_places` tetap dipakai sebagai view dasar.
- Filter role dan wilayah tugas dipindahkan ke RPC Postgres.
- Satu RPC mendukung mode `full` dan `incremental`.
- `admin` melihat semua, `pengawas` dan `pendata` dibatasi wilayah tugasnya.
- Client hanya menerima hasil yang sudah final dari server lalu menyimpannya ke cache lokal.
