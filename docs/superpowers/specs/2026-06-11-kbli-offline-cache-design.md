# Desain Cache Lokal KBLI

## Latar Belakang

Halaman `KbliPage` saat ini selalu mengambil data dari Supabase melalui `KbliSupabaseService.fetchEntries()`. Akibatnya halaman bergantung pada koneksi internet dan tidak dapat dipakai saat offline. Pengguna menginginkan perilaku `cache lokal + refresh manual`, sehingga data KBLI tetap tersedia tanpa internet dan sinkronisasi hanya dilakukan saat pengguna meminta.

## Tujuan

- Menampilkan data KBLI dari penyimpanan lokal jika data cache sudah pernah tersimpan.
- Menghindari fetch otomatis ke Supabase setiap kali halaman dibuka.
- Memperbarui data dari Supabase hanya saat pengguna menekan refresh.
- Tetap menampilkan data cache jika refresh gagal atau perangkat sedang offline.

## Di Luar Cakupan

- Menambah database lokal baru seperti `sqflite`, `isar`, atau `hive`.
- Menambahkan indikator sinkronisasi kompleks seperti versi data dari server.
- Mengubah struktur UI utama selain teks kecil yang membantu menjelaskan status sumber data.

## Pendekatan

Pendekatan yang dipilih adalah menyimpan payload KBLI sebagai JSON string di `shared_preferences`. Alasan pemilihan:

- Dependensi `shared_preferences` sudah tersedia dan sudah dipakai di project.
- Data KBLI di halaman ini bersifat referensi dan mayoritas dibaca, bukan dimutasi lokal.
- Implementasi paling kecil risikonya dan cukup untuk kebutuhan offline dasar.

## Perubahan Arsitektur

### `PanduanKbliEntry`

- Tambah metode `toJson()` agar object dapat diserialisasi kembali ke JSON untuk cache.

### `KbliSupabaseService`

- Tambah key cache lokal untuk data KBLI.
- Tambah method untuk membaca cache lokal dan mengubahnya menjadi `List<PanduanKbliEntry>`.
- Tambah method untuk menyimpan hasil fetch Supabase ke cache lokal.
- Tambah method publik untuk:
  - memuat cache lokal tanpa jaringan,
  - refresh dari Supabase lalu menyimpan hasilnya ke cache.

Method `fetchEntries()` lama bisa dipertahankan sebagai helper internal untuk fetch dari Supabase agar perubahan ke layer UI tetap sederhana.

### `KbliPage`

- Saat `initState`, halaman memuat cache lokal lebih dulu.
- Jika cache ada, tampilkan data tersebut langsung tanpa memanggil Supabase.
- Refresh manual tetap memanggil Supabase dan menyimpan hasil baru ke cache.
- Jika refresh gagal namun data lokal tersedia, UI tetap menampilkan data lama.
- Jika tidak ada cache sama sekali dan refresh/fetch gagal, tampilkan error state seperti sekarang.

## Alur Data

### Saat halaman dibuka

1. `KbliPage` memanggil load cache lokal.
2. Jika cache berisi data valid, tampilkan data dan selesai.
3. Jika cache kosong, coba ambil dari Supabase sekali sebagai fallback awal.
4. Jika fetch awal berhasil, simpan ke cache lalu tampilkan.
5. Jika fetch awal gagal dan cache kosong, tampilkan error.

### Saat pengguna menekan refresh

1. Halaman memanggil refresh dari Supabase.
2. Jika berhasil, data di UI diperbarui dan cache ditimpa dengan hasil terbaru.
3. Jika gagal:
   - jika UI sudah punya data cache, pertahankan data yang ada,
   - simpan pesan error ringan untuk feedback,
   - jangan kosongkan daftar.

## Error Handling

- Gagal parsing cache: cache diabaikan dan dianggap tidak tersedia.
- Gagal baca/tulis `shared_preferences`: log error, lalu tetap lanjut dengan fetch atau data in-memory yang ada.
- Gagal refresh online saat ada cache: jangan ubah `_entries`, cukup tampilkan pemberitahuan yang sesuai.
- Gagal load awal tanpa cache: tetap tampilkan state error penuh.

## Dampak UI

- Tombol refresh yang ada tetap dipakai sebagai trigger sinkronisasi manual.
- Teks status kecil opsional dapat ditambahkan untuk menjelaskan bahwa data berasal dari cache lokal.
- Tidak ada perubahan pada fitur pencarian, filter, grouping, atau dialog detail.

## Pengujian

- Verifikasi membuka halaman saat pernah online sebelumnya lalu perangkat offline: data cache tetap muncul.
- Verifikasi membuka halaman pertama kali tanpa internet: state error tetap muncul.
- Verifikasi refresh manual saat online: data baru muncul dan cache diperbarui.
- Verifikasi refresh manual saat offline dengan cache tersedia: data lama tetap tampil.

## Risiko dan Mitigasi

- Ukuran JSON terlalu besar untuk `shared_preferences`: untuk tahap ini diterima karena kebutuhan saat ini sederhana; bila nanti data membesar signifikan, cache dapat dipindah ke file storage.
- Cache usang: diterima karena pengguna memang memilih model refresh manual.
- Error parsing akibat perubahan schema: mitigasi dengan default value aman di `fromJson()` dan fallback mengabaikan cache yang rusak.
