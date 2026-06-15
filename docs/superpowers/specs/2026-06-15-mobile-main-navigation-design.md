# Mobile Main Navigation Design

## Latar Belakang

Halaman utama pada mobile saat ini memakai `BottomNavigationBar` dengan enam item:

- Jelajah
- Dashboard
- Wilayah
- Dokumentasi
- KBLI
- Usaha Organik

Jumlah item tersebut terlalu banyak untuk lebar layar mobile dan membuat navigasi utama terasa padat. Tujuan perubahan ini adalah menyederhanakan navigasi utama menjadi tiga tab inti dan memindahkan tiga menu tambahan ke side menu.

## Tujuan

- Menyisakan tiga item utama pada `BottomNavigationBar`
- Memindahkan `Dokumentasi`, `KBLI`, dan `Usaha Organik` ke `Drawer`
- Mempertahankan arsitektur halaman saat ini berbasis `_selectedIndex` dan `IndexedStack`
- Menjaga perilaku existing seperti reset selection peta saat berpindah menu

## Di Luar Scope

- Mengubah struktur halaman individual seperti `DokumentasiPage`, `KbliPage`, atau `UsahaOrganikPage`
- Mengganti pola navigasi menjadi named routes atau `Navigator.push`
- Mendesain ulang app bar/search bar di luar kebutuhan akses ke `Drawer`

## Pendekatan Terpilih

Pendekatan yang dipilih adalah mempertahankan `_selectedIndex` sebagai sumber state navigasi tunggal.

Perubahan inti:

- `BottomNavigationBar` hanya berisi `Jelajah`, `Dashboard`, dan `Wilayah`
- `Drawer` ditambahkan sebagai side menu untuk `Dokumentasi`, `KBLI`, dan `Usaha Organik`
- Pemilihan item `Drawer` akan mengubah `_selectedIndex` ke halaman yang sesuai

Pendekatan ini dipilih karena paling kecil risiko regresinya dan sesuai dengan pola halaman saat ini.

## Arsitektur Navigasi

Struktur halaman tetap:

- `MapPage` selalu menjadi base layer
- halaman non-`Jelajah` tetap ditampilkan melalui `IndexedStack`
- `_selectedIndex` tetap menjadi state aktif halaman

Mapping target halaman tetap konsisten:

- `0` = `Jelajah`
- `1` = `Dashboard`
- `2` = `Wilayah`
- `3` = `Dokumentasi`
- `4` = `KBLI`
- `5` = `Usaha Organik`

Dengan mapping ini, perubahan hanya terjadi pada kontrol navigasi, bukan pada susunan halaman.

## Komponen Yang Diubah

### Bottom Navigation

`BottomNavigationBar.items` dikurangi dari enam menjadi tiga item:

- `Jelajah`
- `Dashboard`
- `Wilayah`

### Drawer

`Scaffold.drawer` ditambahkan dan memuat tiga entry:

- `Dokumentasi`
- `KBLI`
- `Usaha Organik`

Setiap entry menggunakan handler yang:

1. menutup drawer
2. membersihkan selection peta
3. memperbarui `_selectedIndex`

### Akses Drawer

Karena halaman ini tidak memakai `AppBar` standar, akses drawer perlu disediakan lewat tombol hamburger pada area atas kiri yang konsisten dengan overlay yang sudah ada.

## Alur Interaksi

### Pindah tab utama

Saat user menekan item pada `BottomNavigationBar`:

1. `PlaceCleared()` dipanggil
2. `_selectedIndex` diperbarui ke tab terpilih

### Pilih menu dari drawer

Saat user memilih item dari `Drawer`:

1. drawer ditutup
2. `PlaceCleared()` dipanggil
3. `_selectedIndex` diubah ke index halaman target

## Error Handling Dan Konsistensi

- Handler drawer dan bottom nav harus memakai pola perpindahan yang sama agar state peta konsisten
- Index halaman tidak boleh diubah pada `IndexedStack.children`, agar mapping halaman existing tetap valid
- Tombol drawer harus tersedia tanpa mengganggu search bar yang sudah ada di tab `Jelajah`

## Verifikasi

Verifikasi manual yang diperlukan:

- `BottomNavigationBar` hanya menampilkan tiga item
- `Drawer` bisa dibuka pada mobile
- `Dokumentasi`, `KBLI`, dan `Usaha Organik` dapat dibuka dari `Drawer`
- `Dashboard` dan `Wilayah` tetap bekerja dari bottom tab
- `Jelajah` tetap menampilkan search bar seperti sebelumnya
- Perpindahan menu tetap membersihkan selection peta

## Risiko

- Posisi tombol drawer bisa berbenturan secara visual dengan search bar overlay
- Bila current index untuk halaman drawer tidak ditangani dengan benar, halaman aktif bisa tidak sinkron dengan `IndexedStack`

Risiko ini dikurangi dengan perubahan minimal dan reuse handler navigasi yang sama untuk semua entry.
