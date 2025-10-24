# SQL Scripts untuk Direktori App

Folder ini berisi script SQL untuk membuat database Direktori Usaha di Supabase.

## File Utama

### `create_single_wilayah_table.sql` ⭐ **RECOMMENDED**
Script lengkap dan terbaru untuk membuat database dengan struktur single table wilayah:
- **Tabel wilayah**: Master data wilayah (provinsi, kabupaten, kecamatan, desa, SLS)
- **Tabel direktori**: Data usaha dengan foreign key ke wilayah
- **Functions**: Helper functions untuk dropdown (get_daftar_provinsi, get_daftar_kabupaten, dll)
- **Views**: v_direktori_lengkap untuk query dengan nama wilayah
- **Indexes**: Optimasi performa
- **Dummy data**: Contoh data untuk testing
- **Schema terbaru**: Menggunakan field `keberadaan_usaha` (integer) menggantikan `status_perusahaan` (string)

## Cara Penggunaan

### Setup Database
```sql
-- Jalankan script lengkap
-- File: create_single_wilayah_table.sql
-- Berisi semua yang dibutuhkan dalam satu file
```

### Verifikasi:
```sql
-- Cek semua tabel
SELECT table_name FROM information_schema.tables 
WHERE table_schema = 'public' 
ORDER BY table_name;

-- Cek data wilayah
SELECT * FROM wilayah ORDER BY id_sls LIMIT 10;

-- Cek data direktori dengan nama wilayah
SELECT * FROM v_direktori_lengkap ORDER BY created_at DESC LIMIT 5;
```

## Import Data dari Excel

### 1. Format Excel yang Dibutuhkan:
Pastikan Excel Anda memiliki kolom:
- `id_sls` (13 digit) atau bisa digenerate dari kode
- `kd_prov` (2 digit)
- `kd_kab` (2 digit) 
- `kd_kec` (3 digit)
- `kd_desa` (3 digit)
- `kd_sls` (4 digit)
- `nm_prov` (nama provinsi)
- `nm_kab` (nama kabupaten)
- `nm_kec` (nama kecamatan)
- `nm_desa` (nama desa)
- `nm_sls` (nama SLS)

### 2. Cara Import:
```sql
-- Contoh import dari Excel
INSERT INTO wilayah (id_sls, kd_prov, kd_kab, kd_kec, kd_desa, kd_sls, 
                     nm_prov, nm_kab, nm_kec, nm_desa, nm_sls) VALUES 
('7371010001001', '73', '71', '010', '001', '001', 
 'Sulawesi Selatan', 'Parepare', 'Bacukiki', 'Lumpue', 'Lumpue I'),
('7371010001002', '73', '71', '010', '001', '002', 
 'Sulawesi Selatan', 'Parepare', 'Bacukiki', 'Lumpue', 'Lumpue II');
-- ... tambahkan semua data dari Excel
```

## Konsep ID SLS

**ID SLS** adalah identifikasi unik 14 digit yang terbentuk dari:
- `kd_prov` (2 digit) + `kd_kab` (2 digit) + `kd_kec` (3 digit) + `kd_desa` (3 digit) + `kd_sls` (4 digit)

Contoh: `73720110010009`
- `73` = Sulawesi Selatan
- `72` = Parepare  
- `011` = Bacukiki Barat
- `001` = Lumpue
- `0009` = RT 002 RW 004

## Contoh Query Praktis

### Mendapatkan Daftar Wilayah untuk Dropdown:
```sql
-- Daftar Provinsi
SELECT * FROM get_daftar_provinsi();

-- Daftar Kabupaten berdasarkan Provinsi
SELECT * FROM get_daftar_kabupaten('73');

-- Daftar Kecamatan berdasarkan Kabupaten
SELECT * FROM get_daftar_kecamatan('73', '71');

-- Daftar Desa berdasarkan Kecamatan
SELECT * FROM get_daftar_desa('73', '71', '010');

-- Daftar SLS berdasarkan Desa
SELECT * FROM get_daftar_sls('73', '71', '010', '001');
```

### Insert Data Direktori Baru:
```sql
INSERT INTO direktori (
    id_sbr, nama_usaha, alamat, id_sls,
    keberadaan_usaha, kegiatan_usaha, skala_usaha
) VALUES (
    'SBR003', 'Bengkel Motor Jaya', 'Jl. Sudirman No. 67',
    '7371030001001',  -- Pilih dari dropdown SLS
    1,  -- 1 = Aktif
    '[{"kegiatan_usaha": "Reparasi Kendaraan Bermotor"}]'::jsonb,
    'mikro'
);
```

### Pencarian dan Filter:
```sql
-- Cari berdasarkan nama usaha
SELECT * FROM v_direktori_lengkap 
WHERE to_tsvector('indonesian', nama_usaha) @@ to_tsquery('indonesian', 'bengkel');

-- Filter berdasarkan wilayah
SELECT * FROM v_direktori_lengkap 
WHERE kd_prov = '73' AND kd_kab = '71';

-- Filter berdasarkan skala usaha
SELECT * FROM v_direktori_lengkap 
WHERE skala_usaha = 'mikro';
```

## Keuntungan Struktur Single Table

1. **Kesederhanaan**: Hanya 2 tabel utama (wilayah + direktori)
2. **Import Mudah**: Langsung dari Excel tanpa normalisasi
3. **Performa**: Query cepat dengan 1 JOIN saja
4. **Maintenance**: Mudah backup, update, dan troubleshoot
5. **Development**: Setup cepat, tidak perlu foreign key kompleks
6. **Dropdown Ready**: Functions siap pakai untuk UI

## Contoh Query

### Insert Data Baru
```sql
INSERT INTO direktori (
    id_sbr, nama_usaha, alamat, kd_prov, kd_kab, kd_kec, kd_desa, kd_sls,
    nm_prov, nm_kab, nm_kec, nm_desa, nm_sls, keberadaan_usaha,
    kegiatan_usaha, skala_usaha, lat, long, pemilik, tenaga_kerja
) VALUES (
    'SBR003',
    'Bengkel Motor Jaya',
    'Jl. Sudirman No. 78',
    '73', '71', '030', '003', '001',
    'Sulawesi Selatan', 'Parepare', 'Soreang', 'Bukit Harapan', 'Bukit Harapan I',
    1,  -- 1 = Aktif
    '[{"kegiatan_usaha": "Reparasi Kendaraan Bermotor", "kategori": "Jasa", "kbli": "45201"}]'::jsonb,
    'mikro',
    -4.0150, 119.6180,
    'Ahmad Rizki',
    4
);
```

### Search Berdasarkan Nama
```sql
SELECT * FROM direktori 
WHERE to_tsvector('indonesian', nama_usaha) @@ to_tsquery('indonesian', 'toko');
```

### Filter Berdasarkan Wilayah
```sql
SELECT * FROM direktori 
WHERE kd_prov = '73' AND kd_kab = '71' AND keberadaan_usaha = 1;  -- 1 = Aktif
```

### Update Data
```sql
UPDATE direktori 
SET keberadaan_usaha = 3, updated_at = NOW()  -- 3 = Tutup
WHERE id_sbr = 'SBR001';
```

## Catatan Penting

1. **File Utama**: Gunakan `create_single_wilayah_table.sql` untuk setup
2. **Data Excel**: Pastikan format sesuai dengan struktur tabel
3. **ID SLS**: Bisa auto-generate atau input manual dari Excel
4. **Functions**: Sudah tersedia untuk kebutuhan dropdown UI
5. **Performa**: Index sudah dioptimalkan untuk pencarian cepat

## Troubleshooting

Jika ada error saat menjalankan script:
1. Pastikan Anda memiliki permission untuk membuat tabel
2. Cek apakah tabel `direktori` sudah ada sebelumnya
3. Pastikan syntax SQL sesuai dengan PostgreSQL (Supabase menggunakan PostgreSQL)