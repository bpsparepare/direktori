# Desain RPC Minimal Assignment Places

## Latar Belakang

RPC `get_assignment_places_for_current_user` saat ini masih mengembalikan banyak kolom yang tidak lagi dibutuhkan untuk kebutuhan peta assignment. Payload yang besar membuat transfer data dan proses parsing di Flutter lebih berat dari yang diperlukan.

Penggunaan nyata saat ini hanya membutuhkan identitas assignment dan koordinat dasar untuk menampilkan marker hasil penugasan pengguna. Karena satu pengguna dapat memiliki sekitar 700 assignment, alur sinkronisasi harus tetap hemat bandwidth dan tetap mendukung cache lokal dengan mekanisme incremental.

## Tujuan

- Menyederhanakan kontrak RPC assignment places menjadi hanya field yang benar-benar dibutuhkan.
- Tetap mempertahankan mode `full` dan `incremental` agar sinkronisasi efisien untuk data besar.
- Memindahkan sumber data RPC ke `mv_fasih_assignment_summary` agar query lebih ringan.
- Menyesuaikan Flutter agar model, cache, dan mapping marker mengikuti kontrak baru secara konsisten.

## Di Luar Cakupan

- Menambah field detail usaha seperti `alamat`, `status_text`, `kode_usaha`, atau `fullcode_subsls` ke UI peta.
- Mendesain ulang halaman lain yang tidak memakai `AssignmentPlacesService`.
- Menambah pagination atau batching baru untuk assignment places.
- Mengubah logika otorisasi dasar selain menyesuaikan query ke sumber yang lebih ringan.

## Pendekatan

Pendekatan yang dipilih adalah mempertahankan satu RPC dengan nama yang sama, tetapi menyederhanakan outputnya dan menyesuaikan client Flutter agar memakai kontrak baru tersebut secara penuh.

Alasan pemilihan:

- Payload jauh lebih kecil sehingga lebih cocok untuk pengguna dengan ratusan assignment.
- Query dari materialized view lebih ringan dibanding mengambil banyak kolom dari sumber lama.
- Kontrak baru menjadi lebih jelas: RPC hanya mengembalikan data minimum untuk marker assignment.
- Mekanisme incremental dan cache lokal tetap bisa dipertahankan tanpa harus mengunduh ulang seluruh data setiap kali refresh.

## Kontrak RPC Baru

### Nama

- `public.get_assignment_places_for_current_user`

### Input

- `p_sync_mode text`
  - nilai valid: `full`, `incremental`
- `p_modified_after timestamptz default null`
  - dipakai hanya saat mode `incremental`

### Output

RPC hanya mengembalikan kolom berikut:

- `assignment_id uuid`
- `no_bang integer`
- `nama_usaha text`
- `latitude numeric`
- `longitude numeric`

Kolom lain tidak lagi menjadi bagian dari kontrak RPC ini.

## Sumber Data Dan Filter

### Sumber Utama

- RPC mengambil data dari `public.mv_fasih_assignment_summary`.
- View tersebut dianggap sudah lebih ringan dan lebih sesuai untuk kebutuhan marker assignment.

### Filter Akses

- User aktif ditentukan dari `auth.uid()`.
- RPC tetap mencari `users.id` dari `public.users`.
- RPC tetap mencari `se2026_petugas` untuk mendapatkan:
  - `id`
  - `role`
  - `is_active`
- `admin` mendapat seluruh assignment dengan koordinat valid.
- `pengawas` dan `pendata` dibatasi berdasarkan `se2026_wilayah_tugas`.

### Filter Wilayah

- Sumber wilayah tugas diambil dari `public.se2026_wilayah_tugas`.
- Untuk `pengawas`, pakai `wt.pml_id = v_petugas_id`.
- Untuk `pendata`, pakai `wt.ppl_id = v_petugas_id`.
- Join wilayah dilakukan terhadap `mv.kode_wilayah = wt.kode_wilayah`.

### Filter Koordinat

- Hanya row dengan `latitude` dan `longitude` valid yang dikembalikan.
- Batas valid:
  - `latitude between -90 and 90`
  - `longitude between -180 and 180`

### Filter Incremental

- Saat `p_sync_mode = 'full'`, RPC mengembalikan seluruh row sesuai scope.
- Saat `p_sync_mode = 'incremental'`, RPC hanya mengembalikan row yang berubah setelah `p_modified_after`.
- Filter waktu tetap dilakukan di server memakai kolom modifikasi dari sumber data ringkas, misalnya `source_modified_at` atau kolom ekuivalen pada materialized view.
- Kolom waktu modifikasi tidak perlu dikembalikan ke client bila tidak dipakai di UI.

## Perubahan Flutter

### Model

`AssignmentPlaceRecord` disederhanakan agar hanya menyimpan:

- `assignmentId`
- `noBang`
- `namaUsaha`
- `latitude`
- `longitude`

Konversi `fromJson()` dan `toJson()` mengikuti nama field RPC baru.

### Service

`AssignmentPlacesService` tetap mempertahankan:

- `downloadFullData()`
- `syncRecords()`
- cache lokal JSON
- metadata `last_sync_time`
- fallback ke cache lokal saat RPC gagal

Perubahan utamanya:

- `_fetchRecords()` tetap mengirim `p_sync_mode` dan `p_modified_after`
- parsing hasil RPC mengikuti kontrak minimal
- merge cache menggunakan `assignmentId` sebagai key stabil
- `cacheVersion` dinaikkan agar cache lama yang berisi schema lama tidak dipakai lagi

### Repository Dan Mapping

`MapRepository` tetap memakai `AssignmentPlacesService`, tetapi mapping ke `Place` disederhanakan:

- `id` memakai `assignmentId`
- `name` memakai `namaUsaha`
- `position` memakai `latitude` dan `longitude`
- `description` diisi string kosong
- `address` diisi string kosong
- `statusPerusahaan` diisi string kosong

Dengan cara ini, kontrak `Place` tetap terpenuhi tanpa membawa field lama yang tidak dibutuhkan.

## Alur Data

### Full Sync

1. App memanggil RPC dengan `p_sync_mode = 'full'`.
2. Database menentukan user aktif, role, dan wilayah tugas yang berlaku.
3. Database mengembalikan seluruh assignment minimal yang sesuai scope.
4. Flutter menyimpan hasil ke cache lokal assignment places.
5. Flutter menyimpan waktu sync terbaru.

### Incremental Sync

1. App membaca `last_sync_time`.
2. App memanggil RPC dengan `p_sync_mode = 'incremental'` dan `p_modified_after`.
3. Database mengembalikan hanya assignment yang berubah setelah waktu tersebut.
4. Flutter melakukan merge ke cache berdasarkan `assignmentId`.
5. Flutter memperbarui `last_sync_time`.

## Error Handling

- Jika `p_sync_mode` invalid, RPC melempar error yang jelas.
- Jika user tidak login, tidak punya record `users`, tidak punya `se2026_petugas`, atau petugas tidak aktif, RPC mengembalikan hasil kosong.
- Jika RPC gagal, Flutter tetap menampilkan cache lokal terakhir.
- Jika parsing salah satu record gagal, implementasi Flutter sebaiknya melewati record rusak tanpa menggagalkan seluruh daftar.

## Keamanan

- Role tidak diambil dari parameter client.
- Identitas user tetap berasal dari `auth.uid()`.
- Filter wilayah tetap dilakukan di database.
- RPC tetap dapat memakai `security definer` dengan `search_path` eksplisit agar perilaku akses tetap terkendali.

## Dampak Ke UI

- Marker peta tetap dapat ditampilkan normal berdasarkan nama usaha dan koordinat.
- Informasi detail yang sebelumnya berasal dari `alamat`, `status`, atau field lain tidak lagi tampil dari source assignment places.
- Untuk kebutuhan peta saat ini, hal ini diterima karena targetnya memang hanya marker assignment minimal.

## Pengujian

- Verifikasi `admin` menerima seluruh assignment dengan koordinat valid.
- Verifikasi `pengawas` hanya menerima assignment dalam `kode_wilayah` tugasnya.
- Verifikasi `pendata` hanya menerima assignment dalam `kode_wilayah` tugasnya.
- Verifikasi user tidak aktif atau tanpa petugas menerima hasil kosong.
- Verifikasi full sync menulis cache baru dengan schema minimal.
- Verifikasi incremental sync menggabungkan update berdasarkan `assignmentId`.
- Verifikasi cache lama otomatis diabaikan setelah `cacheVersion` berubah.
- Verifikasi marker tetap tampil di peta setelah model dipangkas.

## Risiko Dan Mitigasi

- Ada kode Flutter yang masih mengasumsikan field lama tersedia.
  Mitigasi: audit seluruh pemakaian `AssignmentPlaceRecord` dan sederhanakan mapping ke `Place`.

- Materialized view mungkin belum menyediakan kolom modifikasi yang memadai untuk incremental sync.
  Mitigasi: pastikan ada satu kolom waktu perubahan yang stabil di view, atau tambahkan kolom tersebut ke view sebelum RPC dipakai.

- Pengguna kehilangan detail marker yang sebelumnya dibentuk dari field lama.
  Mitigasi: terima untuk tahap ini; bila nanti dibutuhkan, detail dapat ditambah kembali dengan kontrak yang disengaja, bukan membawa seluruh payload lama.

## Ringkasan Keputusan

- RPC tetap memakai nama yang sama.
- Input tetap `full` dan `incremental`.
- Output dipangkas menjadi 5 field: `assignment_id`, `no_bang`, `nama_usaha`, `latitude`, `longitude`.
- Flutter diubah agar mengikuti kontrak baru.
- Cache lokal tetap dipakai, tetapi key merge berubah ke `assignmentId`.
- `cacheVersion` dinaikkan agar schema lama tidak tercampur dengan schema baru.
