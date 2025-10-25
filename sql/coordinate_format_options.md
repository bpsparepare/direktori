# Opsi Format Koordinat Database

## Masalah Saat Ini
1. **Error:** `numeric field overflow` - "A field with precision 10, scale 8 must round to an absolute value less than 10^2"
2. **Error:** `cannot alter type of a column used by a view or rule` - view `v_direktori_lengkap` menggunakan kolom `latitude`

**Penyebab:** 
- Data CSV memiliki koordinat dengan presisi lebih tinggi dari yang didukung database
- Database: `latitude DECIMAL(10,8)` - maksimal XX.XXXXXXXX (2 digit sebelum koma, 8 setelah koma)
- Data CSV: koordinat seperti `-5.123456789012` (lebih dari 8 digit setelah koma)
- View `v_direktori_lengkap` bergantung pada kolom `latitude` dan `longitude`

## Solusi: Ubah Format Database dengan Menangani View ✅

### Script yang Sudah Diperbaiki:
Script `fix_coordinate_precision.sql` sekarang menangani dependency view secara otomatis dan mendukung **13 digit setelah koma** (cocok untuk koordinat dari Google Maps):

1. **Drop view sementara** sebelum mengubah kolom
2. **Ubah tipe kolom** koordinat ke `DECIMAL(16,13)`
3. **Recreate view** dengan definisi yang sama

### Langkah Implementasi:

1. **Jalankan script lengkap** `fix_coordinate_precision.sql` di Supabase SQL Editor
2. **Script akan otomatis:**
   - Drop view `v_direktori_lengkap`
   - Ubah `latitude` dan `longitude` ke `DECIMAL(16,13)` 
   - Recreate view `v_direktori_lengkap`
3. **Verifikasi** dengan query yang ada di script

### Keuntungan Solusi Ini:
- ✅ **Tidak perlu mengubah data CSV**
- ✅ **Mempertahankan presisi koordinat asli**
- ✅ **Menangani dependency view otomatis**
- ✅ **Sekali jalankan, selesai**
- ✅ **View tetap berfungsi normal**
- ✅ **Mendukung koordinat Google Maps (13 digit setelah koma)**

## Hasil Akhir:
- Koordinat mendukung presisi hingga **13 digit setelah koma**
- View `v_direktori_lengkap` tetap berfungsi
- Data CSV bisa diimport tanpa error
- Aplikasi Flutter tetap normal
- **Cocok untuk koordinat copy-paste dari Google Maps**