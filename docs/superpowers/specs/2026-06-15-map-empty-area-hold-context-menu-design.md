# Desain Reaktivasi Hold Di Area Peta Kosong

## Latar Belakang

Di kode saat ini, menu konteks peta yang berisi aksi seperti `Info` masih tersedia, tetapi pemicu gesture `hold` di area peta kosong tidak lagi aktif. Akibatnya, dialog aksi yang dulu muncul saat menahan peta tidak bisa dipakai.

Kebutuhan perubahan ini adalah mengaktifkan kembali gesture `hold` hanya untuk area peta kosong, tanpa mengganggu interaksi marker yang sudah ada.

## Tujuan

- Mengaktifkan kembali `hold` di area peta kosong
- Menampilkan lagi bottom sheet `Pilih Aksi`
- Memastikan tombol `Info` dan aksi lain di context menu bisa dipakai lagi
- Menghindari konflik dengan tap marker

## Di Luar Cakupan

- Menambahkan aksi baru ke context menu
- Mengubah isi dialog `Info`
- Mengaktifkan hold di marker atau polygon
- Mengubah perilaku tap marker yang sudah ada

## Pendekatan

Pendekatan yang dipilih adalah menambahkan callback `onMapLongPress` di `MapView`, lalu menghubungkannya ke `MapPage` yang sudah memiliki fungsi `_showContextMenu`.

Alasan pemilihan:

- Perubahan kecil dan terlokalisasi
- `MapView` tetap bertanggung jawab atas gesture peta
- `MapPage` tetap bertanggung jawab atas aksi bisnis dan dialog
- Risiko konflik dengan struktur saat ini lebih rendah dibanding layer gesture tambahan

## Perubahan Komponen

### `MapView`

Tambahkan callback baru:

- `void Function(LatLng point)? onMapLongPress`

Di `FlutterMap > MapOptions`, aktifkan handler `onLongPress`.

Perilaku:

- saat user hold di area kosong peta, `MapView` mengirim koordinat ke parent
- marker tap tetap memakai alur yang sudah ada

### `MapPage`

`MapPage` akan meneruskan callback baru ke `MapView`.

Perilaku:

- menerima titik hasil long press
- memanggil `_showContextMenu(context, point)`
- context menu lama kembali muncul tanpa perlu menulis ulang isinya

## Alur Interaksi

1. User melakukan `hold` di area peta kosong
2. `MapView` menerima event `onLongPress`
3. `MapView` memanggil `onMapLongPress(point)`
4. `MapPage` menerima koordinat
5. `MapPage` memanggil `_showContextMenu(context, point)`
6. Bottom sheet `Pilih Aksi` tampil
7. User bisa memilih `Info` atau aksi lain yang sudah ada

## Perilaku UI

- Hold hanya berlaku untuk area peta kosong
- Tap marker tetap membuka interaksi marker seperti sekarang
- Context menu yang muncul tetap memakai tampilan bottom sheet yang sudah ada
- Tombol `Info` kembali bisa membuka dialog informasi koordinat dan SLS

## Pengujian

- Verifikasi hold di area kosong memunculkan bottom sheet `Pilih Aksi`
- Verifikasi aksi `Info` masih membuka dialog informasi koordinat
- Verifikasi tap marker tetap berfungsi seperti sebelumnya
- Verifikasi hold tidak menyebabkan marker tap rusak
- Verifikasi menu lain di context sheet tetap bisa dipilih

## Risiko Dan Mitigasi

- Gesture long press bisa bentrok dengan interaksi peta tertentu
  Mitigasi: gunakan handler bawaan `MapOptions.onLongPress`

- Context menu bisa muncul saat user bermaksud gesture lain
  Mitigasi: batasi hanya pada long press, bukan tap biasa

- Ada kemungkinan marker ikut terkena long press bila event bubbling berbeda
  Mitigasi: tahap awal targetnya area kosong, lalu verifikasi manual setelah implementasi

## Ringkasan Keputusan

- Reaktivasi hold dilakukan lewat `MapOptions.onLongPress`
- `MapView` hanya meneruskan koordinat melalui callback
- `MapPage` tetap memakai `_showContextMenu` yang sudah ada
- Hold hanya ditargetkan untuk area peta kosong
