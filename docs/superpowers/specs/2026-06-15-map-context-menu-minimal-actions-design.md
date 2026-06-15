# Desain Menu Hold Peta: Hanya Info Dan Navigasi

## Latar Belakang

Menu `Pilih Aksi` yang muncul saat pengguna menahan (hold) peta kosong sebelumnya berisi beberapa aksi tambahan seperti `Tambah Groundcheck` dan `Voice Groundcheck`. Untuk saat ini menu ingin dibuat lebih ringkas agar fokus pada kebutuhan utama.

## Tujuan

- Menyederhanakan menu hold peta kosong agar hanya berisi:
  - `Info`
  - `Navigasi`

## Di Luar Cakupan

- Menghapus fitur groundcheck atau voice dari codebase
- Mengubah dialog `Info`
- Mengubah alur `Navigasi`

## Perubahan

- Di `_showContextMenu(...)` pada `MapPage`:
  - Hapus `ListTile` untuk `Tambah Groundcheck`
  - Hapus `ListTile` untuk `Voice Groundcheck (Mode Berkendara)`
  - Hapus opsi lain yang bukan `Info` dan `Navigasi` jika masih ada pada menu ini

## Kriteria Sukses

- Hold di peta kosong menampilkan bottom sheet yang hanya memuat:
  - `Info`
  - `Navigasi`
- Memilih `Info` tetap membuka dialog informasi koordinat
- Memilih `Navigasi` tetap membuka dialog navigasi
