# Import Data BPS CSV ke Supabase

Panduan lengkap untuk mengimpor data dari file `importbps.csv` ke tabel `direktori` di Supabase.

## 📋 Analisis Data CSV

### Struktur File CSV
File `importbps.csv` berisi **6,052 records** dengan 17 kolom:

```csv
idsbr,nama_usaha,nama_komersial_usaha,alamat,nama_sls,kodepos,nomor_telepon,nomor_whatsapp,email,website,latitude,longitude,keberadaan_usaha,kdprov,kdkab,kdkec,kddesa
```

### Sample Data
```csv
97447640,LPK SATRIA (MUHAMMAD FERY SATRIADI AZIS),,JL MUH ARSYAD NO 40,,,420640,,HOMENETPARE@GMAIL.COM,,,,1,73,72,030,004
97446322,BIMBINGAN BELAJAR <MARDAWIAH>,,JALAN AGUS SALIM,,,085242368429,,,,,,1,73,72,011,006
```

## 🗺️ Mapping Kolom CSV ke Database

| CSV Column | Database Column | Status | Keterangan |
|------------|-----------------|--------|------------|
| `idsbr` | `id_sbr` | ✅ **SESUAI** | Unique identifier dari BPS |
| `nama_usaha` | `nama_usaha` | ✅ **SESUAI** | Nama usaha (required) |
| `nama_komersial_usaha` | `nama_komersial_usaha` | ✅ **SESUAI** | Nama komersial (optional) |
| `alamat` | `alamat` | ✅ **SESUAI** | Alamat usaha |
| `nama_sls` | `nama_sls` | ✅ **SESUAI** | Nama SLS (sudah ditambahkan ke database) |
| `kodepos` | `kode_pos` | ✅ **SESUAI** | Kode pos |
| `nomor_telepon` | `nomor_telepon` | ✅ **SESUAI** | Nomor telepon |
| `nomor_whatsapp` | `nomor_whatsapp` | ✅ **SESUAI** | Nomor WhatsApp |
| `email` | `email` | ✅ **SESUAI** | Email |
| `website` | `website` | ✅ **SESUAI** | Website |
| `latitude` | `latitude` | ✅ **SESUAI** | Koordinat latitude |
| `longitude` | `longitude` | ✅ **SESUAI** | Koordinat longitude |
| `keberadaan_usaha` | `keberadaan_usaha` | ✅ **SESUAI** | Status usaha (converted to integer) |
| `kdprov` | `kd_prov` | ✅ **SESUAI** | Kode provinsi (padded to 2 digits) |
| `kdkab` | `kd_kab` | ✅ **SESUAI** | Kode kabupaten (padded to 2 digits) |
| `kdkec` | `kd_kec` | ✅ **SESUAI** | Kode kecamatan (padded to 3 digits) |
| `kddesa` | `kd_desa` | ✅ **SESUAI** | Kode desa (padded to 3 digits) |

## ❌ Kolom Database yang Tidak Ada di CSV

| Database Column | Default Value | Keterangan |
|-----------------|---------------|------------|
| `kd_sls` | `NULL` | Kode SLS tidak wajib, tidak tersedia di CSV |
| `id_sls` | `NULL` | ID SLS tidak wajib, tidak tersedia di CSV |
| `kegiatan_usaha` | Default JSON | `[{"kegiatan_usaha": "Belum Dikategorikan"}]` |
| `skala_usaha` | `'mikro'` | Default skala usaha |
| `sumber_data` | `'BPS'` | Menandai data dari BPS |

## 🚀 Cara Import

### Metode 1: Menggunakan Supabase Dashboard

1. **Login ke Supabase Dashboard**
   - Buka [supabase.com](https://supabase.com)
   - Login ke project Anda

2. **Buka SQL Editor**
   - Pilih "SQL Editor" dari sidebar
   - Klik "New query"

3. **Jalankan Script Persiapan**
   ```sql
   -- Copy dan paste isi file import_bps_csv.sql
   -- Bagian CREATE TEMP TABLE dan struktur lainnya
   ```

4. **Upload Data CSV**
   - Gunakan Table Editor untuk upload CSV
   - Atau gunakan bulk insert melalui client library

### Metode 2: Menggunakan psql (PostgreSQL Client)

```bash
# 1. Connect ke database
psql "postgresql://[user]:[password]@[host]:[port]/[database]"

# 2. Jalankan script import
\i /path/to/import_bps_csv.sql

# 3. Upload CSV data
COPY temp_bps_import FROM '/path/to/importbps.csv' 
WITH (FORMAT csv, HEADER true, DELIMITER ',');
```

### Metode 3: Menggunakan Client Library (Recommended)

```javascript
// Contoh menggunakan JavaScript/Node.js
import { createClient } from '@supabase/supabase-js'
import fs from 'fs'
import csv from 'csv-parser'

const supabase = createClient(url, key)

const importData = async () => {
  const results = []
  
  fs.createReadStream('importbps.csv')
    .pipe(csv())
    .on('data', (data) => results.push(data))
    .on('end', async () => {
      // Transform data sesuai mapping
      const transformedData = results.map(row => ({
        id_sbr: row.idsbr,
        nama_usaha: row.nama_usaha || 'Usaha Tanpa Nama',
        nama_komersial_usaha: row.nama_komersial_usaha || null,
        alamat: row.alamat || null,
        nama_sls: row.nama_sls || null,
        kd_prov: row.kdprov.padStart(2, '0'),
        kd_kab: row.kdkab.padStart(2, '0'),
        kd_kec: row.kdkec.padStart(3, '0'),
        kd_desa: row.kddesa.padStart(3, '0'),
        kd_sls: null, // Tidak wajib
        id_sls: null, // Tidak wajib
        keberadaan_usaha: parseInt(row.keberadaan_usaha) || 1,
        nomor_telepon: row.nomor_telepon || null,
        nomor_whatsapp: row.nomor_whatsapp || null,
        email: row.email || null,
        website: row.website || null,
        latitude: row.latitude ? parseFloat(row.latitude) : null,
        longitude: row.longitude ? parseFloat(row.longitude) : null,
        kode_pos: row.kodepos || null,
        sumber_data: 'BPS',
        kegiatan_usaha: [{"kegiatan_usaha": "Belum Dikategorikan", "kategori": "Umum", "kbli": "00000"}],
        skala_usaha: 'mikro'
      }))
      
      // Bulk insert
      const { data, error } = await supabase
        .from('direktori')
        .insert(transformedData)
      
      if (error) console.error('Error:', error)
      else console.log('Success:', data.length, 'records imported')
    })
}
```

## ✅ Validasi Setelah Import

Jalankan query berikut untuk memvalidasi hasil import:

```sql
-- 1. Cek jumlah data yang diimpor
SELECT 'Total BPS records' as info, COUNT(*) as count 
FROM direktori 
WHERE sumber_data = 'BPS';

-- 2. Cek data dengan koordinat
SELECT 'Records with coordinates' as info, COUNT(*) as count 
FROM direktori 
WHERE sumber_data = 'BPS' 
  AND latitude IS NOT NULL 
  AND longitude IS NOT NULL;

-- 3. Cek distribusi per wilayah
SELECT kd_prov, kd_kab, COUNT(*) as jumlah_usaha
FROM direktori 
WHERE sumber_data = 'BPS'
GROUP BY kd_prov, kd_kab 
ORDER BY kd_prov, kd_kab;

-- 4. Sample data
SELECT 
    id_sbr,
    nama_usaha,
    alamat,
    kd_prov || kd_kab || kd_kec || kd_desa as wilayah_code,
    latitude,
    longitude,
    nomor_telepon,
    email
FROM direktori 
WHERE sumber_data = 'BPS'
ORDER BY created_at DESC
LIMIT 10;
```

## ⚠️ Hal yang Perlu Diperhatikan

### 1. **Data Cleaning**
- Pastikan tidak ada karakter aneh dalam CSV
- Cek encoding file (gunakan UTF-8)
- Validasi format email dan nomor telepon

### 2. **Koordinat**
- Beberapa record mungkin tidak memiliki koordinat
- Validasi range koordinat untuk Indonesia
- Latitude: -11 sampai 6
- Longitude: 95 sampai 141

### 3. **Duplikasi**
- Field `id_sbr` harus unique
- Cek duplikasi sebelum import:
```sql
SELECT idsbr, COUNT(*) 
FROM temp_bps_import 
GROUP BY idsbr 
HAVING COUNT(*) > 1;
```

### 4. **Kode Wilayah**
- Semua data menggunakan kode 73 (Sulawesi Selatan)
- Kode kabupaten 72 (Parepare)
- Pastikan kode wilayah valid

## 🔧 Troubleshooting

### Error: "duplicate key value violates unique constraint"
```sql
-- Cek duplikasi id_sbr
SELECT id_sbr, COUNT(*) 
FROM direktori 
GROUP BY id_sbr 
HAVING COUNT(*) > 1;

-- Hapus duplikasi jika perlu
DELETE FROM direktori 
WHERE id IN (
    SELECT id FROM (
        SELECT id, ROW_NUMBER() OVER (PARTITION BY id_sbr ORDER BY created_at) as rn
        FROM direktori
    ) t WHERE rn > 1
);
```

### Error: "invalid input syntax for type numeric"
```sql
-- Cek data koordinat yang tidak valid
SELECT * FROM temp_bps_import 
WHERE latitude !~ '^-?[0-9]+\.?[0-9]*$' 
   OR longitude !~ '^-?[0-9]+\.?[0-9]*$';
```

## 📊 Statistik Data

Berdasarkan analisis file CSV:
- **Total Records**: 6,052
- **Wilayah**: Sulawesi Selatan (73) - Parepare (72)
- **Kecamatan**: Berbagai kecamatan di Parepare
- **Data dengan Email**: ~10% dari total
- **Data dengan Koordinat**: Perlu dicek setelah import

## 🎯 Langkah Selanjutnya

Setelah import berhasil:

1. **Update Kegiatan Usaha**
   ```sql
   -- Kategorisasi berdasarkan nama usaha
   UPDATE direktori 
   SET kegiatan_usaha = '[{"kegiatan_usaha": "Perdagangan Eceran", "kategori": "Perdagangan"}]'::jsonb
   WHERE sumber_data = 'BPS' 
     AND UPPER(nama_usaha) LIKE '%TOKO%';
   ```

2. **Update Skala Usaha**
   ```sql
   -- Berdasarkan kriteria tertentu
   UPDATE direktori 
   SET skala_usaha = 'kecil'
   WHERE sumber_data = 'BPS' 
     AND tenaga_kerja > 5;
   ```

3. **Validasi Koordinat**
   ```sql
   -- Cek koordinat yang tidak masuk akal
   SELECT * FROM direktori 
   WHERE sumber_data = 'BPS'
     AND (latitude < -11 OR latitude > 6 
          OR longitude < 95 OR longitude > 141);
   ```

## 📞 Support

Jika mengalami masalah saat import:
1. Cek log error di Supabase Dashboard
2. Validasi format CSV
3. Pastikan database schema sudah sesuai
4. Hubungi tim development untuk bantuan lebih lanjut