# Instruksi Penggunaan Data Kabupaten

## Masalah
Anda memiliki data lengkap sampai level SLS (Satuan Lingkungan Setempat) tetapi untuk keperluan tertentu hanya membutuhkan data sampai level kabupaten saja.

## Solusi
Saya telah membuat script SQL untuk mengekstrak data kabupaten dari tabel `wilayah` yang sudah ada.

## File yang Dibuat

### 1. `create_kabupaten_view.sql`
Script ini membuat:
- **View `v_kabupaten`**: Menampilkan data unik kabupaten
- **View `v_kecamatan`**: Menampilkan data unik kecamatan (opsional)
- **View `v_desa`**: Menampilkan data unik desa (opsional)
- **Fungsi `get_daftar_kabupaten()`**: Mengambil daftar kabupaten
- **Fungsi `get_kecamatan_by_kabupaten()`**: Mengambil kecamatan berdasarkan kabupaten
- **Fungsi `get_desa_by_kecamatan()`**: Mengambil desa berdasarkan kecamatan

### 2. `test_kabupaten_queries.sql`
Script untuk testing dan contoh penggunaan.

## Cara Penggunaan

### Langkah 1: Jalankan Script Utama
```sql
-- Jalankan di PostgreSQL
\i create_kabupaten_view.sql
```

### Langkah 2: Test Script (Opsional)
```sql
-- Jalankan untuk testing
\i test_kabupaten_queries.sql
```

## Contoh Query untuk Aplikasi

### 1. Mendapatkan Daftar Kabupaten untuk Dropdown
```sql
SELECT 
    CONCAT(kd_prov, kd_kab) as kode_kabupaten,
    CONCAT(nm_kab, ', ', nm_prov) as nama_lengkap
FROM v_kabupaten
ORDER BY nm_prov, nm_kab;
```

### 2. Mendapatkan Kecamatan Setelah Memilih Kabupaten
```sql
-- Contoh: Setelah user pilih Parepare (kd_prov='73', kd_kab='72')
SELECT * FROM get_kecamatan_by_kabupaten('73', '72');
```

### 3. Mendapatkan Desa Setelah Memilih Kecamatan
```sql
-- Contoh: Setelah user pilih Bacukiki Barat (kd_kec='011')
SELECT * FROM get_desa_by_kecamatan('73', '72', '011');
```

## Struktur Data yang Dihasilkan

### View `v_kabupaten`
| Kolom | Tipe | Deskripsi |
|-------|------|-----------|
| kd_prov | CHAR(2) | Kode Provinsi |
| kd_kab | CHAR(2) | Kode Kabupaten |
| nm_prov | VARCHAR(50) | Nama Provinsi |
| nm_kab | VARCHAR(50) | Nama Kabupaten |

## Implementasi di Flutter/Dart

Anda bisa menggunakan view dan fungsi ini untuk:

1. **Dropdown Kabupaten**: Query `v_kabupaten` untuk populate dropdown
2. **Cascading Dropdown**: Gunakan fungsi `get_kecamatan_by_kabupaten()` dan `get_desa_by_kecamatan()`
3. **Filter Data**: Filter data berdasarkan pilihan kabupaten user

## Keuntungan Solusi Ini

1. **Efisien**: Tidak perlu duplikasi data, menggunakan data yang sudah ada
2. **Fleksibel**: Bisa pilih level mana saja (kabupaten, kecamatan, atau desa)
3. **Konsisten**: Data selalu sinkron dengan tabel `wilayah` utama
4. **Mudah Digunakan**: View dan fungsi siap pakai untuk aplikasi

## Catatan

- Pastikan tabel `wilayah` sudah terisi data (jalankan `import_all_geojson_data.sql` terlebih dahulu)
- Script ini kompatibel dengan struktur data yang sudah ada
- Tidak mengubah data asli, hanya membuat view dan fungsi helper