# Debug Session: assignment-focus-cache [OPEN]

## Gejala

- Map tidak langsung fokus ke wilayah tugas setelah hot restart, login, dan logout.
- Polygon SLS sesuai wilayah tugas tidak terlihat.

## Ekspektasi

- Map langsung mengarah ke area wilayah tugas user aktif.
- Polygon wilayah tugas bisa dimunculkan sesuai data penugasan.

## Hipotesis

1. Cache fokus belum pernah tersimpan atau gagal dibaca untuk user aktif.
2. `assignmentPolygons` kosong karena `wilayah_tugas.id` tidak match dengan `idsls` polygon.
3. `MapView` menerima data fokus, tetapi `fitCamera` tidak pernah terpanggil.
4. State fokus/polygon tertimpa oleh urutan init event.
5. User/role yang dipakai saat fetch wilayah tugas tidak sesuai sesi auth saat ini.

## Rencana

1. Tambahkan instrumentation pada `MapBloc` dan `MapView`.
2. Reproduksi issue dan kumpulkan log runtime.
3. Tentukan hipotesis yang lolos/gugur.
4. Terapkan perbaikan minimum berbasis bukti.

## Progress

- Instrumentation HTTP sudah ada, tetapi file NDJSON di `.dbg` belum terbentuk.
- Ditambahkan log lokal `debugPrint` pada:
  - `MapAssignmentFocusCacheService`
  - `MapBloc`
  - `MapView`
  - `GroundcheckSupabaseService`
- Reproduksi berikutnya bisa dianalisis langsung dari output Flutter walaupun HTTP debug server tetap gagal.
- Bukti runtime menunjukkan profile dan wilayah tugas berhasil terbaca.
- Bukti statis menunjukkan mismatch format:
  - `se2026_wilayah_tugas.id` / `fullcode_subsls` memakai 16 digit
  - asset polygon `idsls` memakai 14 digit
  - `se2026_wilayah_tugas` menyediakan `id_sls` untuk kode 14 digit
- Perbaikan minimum diterapkan: matching polygon assignment kini memakai `id_sls` lebih dulu, fallback ke `id`.
