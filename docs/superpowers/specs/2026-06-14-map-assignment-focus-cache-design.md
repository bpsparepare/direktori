# Desain Cache Fokus Wilayah Tugas

## Latar Belakang

Fokus awal peta ke wilayah tugas petugas sudah dirancang berbasis polygon dari `final_sls_optimized_v2.json`. Namun, menghitung polygon tugas aktif dan bounds gabungannya setiap kali halaman peta dibuka dapat membuat fokus awal terasa terlambat atau tidak konsisten terlihat oleh pengguna.

Pengguna menginginkan perilaku yang lebih cepat: area fokus wilayah tugas disimpan lokal sehingga saat user login lagi dengan akun yang sama, peta dapat langsung mengarah ke wilayah tugas tanpa perlu menghitung ulang berulang kali. Perhitungan polygon tetap boleh berjalan di belakang untuk memperbarui cache bila ada perubahan.

## Tujuan

- Menyimpan fokus awal wilayah tugas secara lokal per user.
- Saat map dibuka, fokus awal memakai cache lokal terlebih dahulu bila tersedia.
- Cache tidak tercampur antar user saat login/logout.
- Perhitungan polygon wilayah tugas tetap bisa memperbarui cache di belakang.

## Di Luar Cakupan

- Mengubah mekanisme sync marker `places`.
- Mengubah struktur asset polygon.
- Menambahkan sinkronisasi cache fokus ke server.
- Membuat panel pengaturan baru untuk reset cache fokus.

## Pendekatan Yang Dipilih

Pendekatan yang dipilih adalah menyimpan focus cache per user aktif. Cache ini dibaca segera saat peta dibuka, lalu dipakai untuk mengarahkan kamera sebelum perhitungan polygon tugas selesai. Setelah `assignmentPolygons` berhasil dimuat, app menghitung bounds aktual dan memperbarui cache bila hasilnya berubah.

Ini dipilih karena:

- paling cepat dirasakan user saat membuka peta
- aman saat ganti akun karena key cache terpisah
- tidak memerlukan perubahan backend

## Data Yang Disimpan Lokal

Cache fokus wilayah tugas menyimpan data minimal berikut:

- `owner`
  - user aktif yang memiliki cache ini
- `south`
- `north`
- `west`
- `east`
- opsional `updated_at`

Penyimpanan bounds dipilih karena lebih fleksibel daripada hanya menyimpan center dan zoom. Dengan bounds, app bisa selalu memakai `fitCamera` yang menyesuaikan ukuran wilayah secara otomatis.

## Kunci Cache

Cache harus disimpan per user aktif. Kunci yang direkomendasikan:

- berdasarkan `auth.currentUser.id`

Alasan:

- stabil selama user login ke akun yang sama
- sederhana
- tidak bercampur saat login/logout akun berbeda

## Alur Produk

### Saat Map Dibuka

1. App memeriksa user aktif.
2. App membaca cache focus milik user itu.
3. Jika cache ada dan valid:
   - map langsung `fit` ke bounds cache
4. Sementara itu, polygon wilayah tugas tetap dimuat seperti biasa.
5. Setelah `assignmentPolygons` siap:
   - hitung bounds aktual
   - jika berbeda dari cache, simpan hasil baru

### Saat Login User Yang Sama

- Map memakai cache fokus yang sama.
- User mendapat pengalaman buka map yang langsung tertuju ke wilayah tugas.

### Saat Login User Berbeda

- Cache user sebelumnya tidak dipakai.
- App hanya memakai cache milik user yang sedang aktif.

### Saat Logout

- Tidak wajib menghapus cache, karena cache sudah dipisah per user.
- Namun state in-memory map harus bersih saat sesi berganti.

## Arsitektur Yang Direkomendasikan

### Service Cache Fokus

Tambahkan helper kecil khusus untuk focus cache, misalnya di layer service data map. Tanggung jawabnya:

- membentuk key cache per user
- menyimpan bounds wilayah tugas
- membaca bounds wilayah tugas
- memvalidasi data bounds sebelum dipakai

Service ini harus terpisah dari service polygon dan service assignment places agar tanggung jawab tetap jelas.

### Integrasi Ke BLoC / View

- Saat `MapBloc` atau alur peta selesai menentukan `assignmentPolygons`, hitung bounds gabungan lalu simpan ke cache.
- `MapView` atau layer inisialisasi peta membaca cache fokus lebih awal untuk auto-focus awal.
- Auto-focus dari cache hanya boleh diterapkan sekali per pembukaan map.
- Jika hasil polygon aktual datang setelahnya, kamera tidak perlu dipaksa lagi kecuali belum pernah fokus sama sekali atau cache ternyata invalid.

## Aturan Prioritas Fokus

Urutan prioritas yang dipilih:

1. cache fokus wilayah tugas user aktif
2. bounds aktual dari `assignmentPolygons`
3. config default map

Dengan prioritas ini:

- pengalaman awal terasa cepat
- hasil aktual tetap menjadi sumber koreksi
- fallback tetap aman jika cache tidak ada

## Validasi Cache

Cache dianggap valid bila:

- semua nilai `south`, `north`, `west`, `east` ada
- rentang latitude dan longitude valid
- `south <= north`
- `west <= east`

Jika tidak valid, cache diabaikan dan app kembali ke mekanisme normal berbasis polygon aktual atau config default.

## Perubahan Kode

### State / BLoC

- Tambah state atau flag untuk membedakan:
  - focus awal sudah diterapkan dari cache
  - focus aktual dari polygon sudah dihitung
- Hindari auto-focus berulang saat user sudah menggeser peta.

### MapView

- Tambah kemampuan menerima bounds fokus awal dari cache.
- Saat bounds cache ada, terapkan `fitCamera` lebih awal.
- Saat polygon tugas aktual siap, hanya perbarui fokus bila memang diperlukan menurut aturan prioritas.

### Service

- Tambah helper `MapAssignmentFocusCacheService` atau setara.
- Simpan cache menggunakan `SharedPreferences`, karena datanya ringan dan sederhana.

## Error Handling

- Jika pembacaan cache gagal:
  - abaikan cache
  - lanjut ke mekanisme polygon aktual
- Jika penyimpanan cache gagal:
  - jangan memblokir map
  - cukup log secara ringan
- Jika user belum punya wilayah tugas:
  - jangan simpan cache fokus wilayah tugas

## Pengujian

- Login user A, buka map pertama kali:
  - fokus dihitung dari polygon
  - cache tersimpan
- Tutup dan buka lagi dengan user A:
  - map langsung fokus dari cache
- Login user B:
  - map tidak memakai cache user A
- Cache invalid:
  - app fallback ke polygon aktual/default
- User geser peta lalu refresh marker:
  - kamera tidak terus dipaksa kembali ke cache

## Risiko Dan Mitigasi

- Fokus cache bisa stale bila wilayah tugas berubah.
  Mitigasi: setiap kali polygon tugas aktual berhasil dimuat, bounds aktual dibandingkan dan cache diperbarui.

- Fokus dari cache bisa diterapkan terlambat jika wiring dilakukan di tahap render yang salah.
  Mitigasi: baca cache sedini mungkin di alur inisialisasi map.

- Fokus bisa terasa lompat dua kali: sekali dari cache, sekali dari polygon aktual.
  Mitigasi: jika cache valid dan cukup dekat dengan hasil aktual, jangan fit ulang.

## Ringkasan Keputusan

- Fokus wilayah tugas disimpan lokal per user aktif.
- Data yang disimpan adalah bounds (`south`, `north`, `west`, `east`), bukan hanya center.
- Saat map dibuka, cache dipakai lebih dulu untuk auto-focus cepat.
- Polygon aktual tetap dihitung di belakang untuk memperbarui cache.
- Cache user berbeda tidak saling tercampur saat login/logout.
