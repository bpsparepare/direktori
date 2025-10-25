-- ========================================
-- IMPORT BPS CSV DATA TO DIREKTORI TABLE
-- ========================================
-- Script untuk mengimpor data dari importbps.csv ke tabel direktori
-- File: import_bps_csv.sql
-- Created: $(date)

-- ========================================
-- PERSIAPAN IMPORT
-- ========================================

-- Buat temporary table untuk menampung data CSV
CREATE TEMP TABLE temp_bps_import (
    idsbr VARCHAR(50),
    nama_usaha VARCHAR(255),
    nama_komersial_usaha VARCHAR(255),
    alamat TEXT,
    nama_sls VARCHAR(100),
    kodepos VARCHAR(10),
    nomor_telepon VARCHAR(20),
    nomor_whatsapp VARCHAR(20),
    email VARCHAR(255),
    website TEXT,
    latitude VARCHAR(20),
    longitude VARCHAR(20),
    keberadaan_usaha VARCHAR(5),
    kdprov VARCHAR(5),
    kdkab VARCHAR(5),
    kdkec VARCHAR(5),
    kddesa VARCHAR(5)
);

-- ========================================
-- COPY DATA FROM CSV
-- ========================================
-- CATATAN: Ganti path file sesuai lokasi CSV Anda
-- Untuk Supabase, gunakan dashboard untuk upload CSV atau gunakan client library

-- Contoh untuk PostgreSQL lokal:
-- COPY temp_bps_import FROM '/path/to/importbps.csv' 
-- WITH (FORMAT csv, HEADER true, DELIMITER ',');

-- Untuk Supabase, Anda bisa menggunakan SQL Editor dan paste data manual
-- atau gunakan client library untuk bulk insert

-- ========================================
-- VALIDASI DATA
-- ========================================

-- Cek jumlah data yang akan diimpor
SELECT 'Total records in CSV' as info, COUNT(*) as count FROM temp_bps_import;

-- Cek data yang memiliki koordinat
SELECT 'Records with coordinates' as info, COUNT(*) as count 
FROM temp_bps_import 
WHERE latitude IS NOT NULL AND latitude != '' 
  AND longitude IS NOT NULL AND longitude != '';

-- Cek data dengan email
SELECT 'Records with email' as info, COUNT(*) as count 
FROM temp_bps_import 
WHERE email IS NOT NULL AND email != '';

-- Cek distribusi per kabupaten
SELECT kdprov, kdkab, COUNT(*) as jumlah_usaha
FROM temp_bps_import 
GROUP BY kdprov, kdkab 
ORDER BY kdprov, kdkab;

-- ========================================
-- TRANSFORM DAN INSERT DATA
-- ========================================

-- Insert data dari temp table ke direktori table
INSERT INTO direktori (
    id_sbr,
    nama_usaha,
    nama_komersial_usaha,
    alamat,
    nama_sls,
    kd_prov,
    kd_kab,
    kd_kec,
    kd_desa,
    kd_sls,
        id_sls,
    keberadaan_usaha,
    nomor_telepon,
    nomor_whatsapp,
    email,
    website,
    latitude,
    longitude,
    kode_pos,
    sumber_data,
    kegiatan_usaha,
    skala_usaha
)
SELECT 
    -- ID SBR (unique identifier dari BPS)
    idsbr,
    
    -- Nama usaha (required)
    COALESCE(NULLIF(TRIM(nama_usaha), ''), 'Usaha Tanpa Nama'),
    
    -- Nama komersial (optional)
    NULLIF(TRIM(nama_komersial_usaha), ''),
    
    -- Alamat (optional)
    NULLIF(TRIM(alamat), ''),
    
    -- Nama SLS (optional)
    NULLIF(TRIM(nama_sls), ''),
    
    -- Kode wilayah (required untuk mapping)
    LPAD(kdprov, 2, '0'),
    LPAD(kdkab, 2, '0'), 
    LPAD(kdkec, 3, '0'),
    LPAD(kddesa, 3, '0'),
    NULL, -- kd_sls tidak wajib, set NULL
    
    -- ID SLS tidak wajib, set NULL
    NULL,
    
    -- Keberadaan usaha (convert string to integer)
    CASE 
        WHEN keberadaan_usaha = '1' THEN 1
        WHEN keberadaan_usaha = '2' THEN 2
        WHEN keberadaan_usaha = '3' THEN 3
        ELSE 1 -- Default: aktif
    END,
    
    -- Kontak
    NULLIF(TRIM(nomor_telepon), ''),
    NULLIF(TRIM(nomor_whatsapp), ''),
    NULLIF(TRIM(email), ''),
    NULLIF(TRIM(website), ''),
    
    -- Koordinat (convert string to decimal)
    CASE 
        WHEN latitude IS NOT NULL AND latitude != '' AND latitude ~ '^-?[0-9]+\.?[0-9]*$'
        THEN latitude::DECIMAL(10,8)
        ELSE NULL
    END,
    CASE 
        WHEN longitude IS NOT NULL AND longitude != '' AND longitude ~ '^-?[0-9]+\.?[0-9]*$'
        THEN longitude::DECIMAL(11,8)
        ELSE NULL
    END,
    
    -- Kode pos
    NULLIF(TRIM(kodepos), ''),
    
    -- Sumber data
    'BPS',
    
    -- Kegiatan usaha (default JSON)
    '[{"kegiatan_usaha": "Belum Dikategorikan", "kategori": "Umum", "kbli": "00000"}]'::jsonb,
    
    -- Skala usaha (default)
    'mikro'

FROM temp_bps_import
WHERE idsbr IS NOT NULL 
  AND TRIM(idsbr) != ''
  AND nama_usaha IS NOT NULL 
  AND TRIM(nama_usaha) != '';

-- ========================================
-- VALIDASI HASIL IMPORT
-- ========================================

-- Cek jumlah data yang berhasil diimpor
SELECT 'Successfully imported' as info, COUNT(*) as count 
FROM direktori 
WHERE sumber_data = 'BPS';

-- Cek data dengan koordinat yang valid
SELECT 'Imported with coordinates' as info, COUNT(*) as count 
FROM direktori 
WHERE sumber_data = 'BPS' 
  AND latitude IS NOT NULL 
  AND longitude IS NOT NULL;

-- Cek distribusi per wilayah
SELECT kd_prov, kd_kab, COUNT(*) as jumlah_usaha
FROM direktori 
WHERE sumber_data = 'BPS'
GROUP BY kd_prov, kd_kab 
ORDER BY kd_prov, kd_kab;

-- Cek sample data yang diimpor
SELECT 
    id_sbr,
    nama_usaha,
    alamat,
    kd_prov || kd_kab || kd_kec || kd_desa as wilayah_code,
    latitude,
    longitude,
    nomor_telepon,
    email,
    created_at
FROM direktori 
WHERE sumber_data = 'BPS'
ORDER BY created_at DESC
LIMIT 10;

-- ========================================
-- CLEANUP
-- ========================================

-- Drop temporary table
DROP TABLE IF EXISTS temp_bps_import;

-- ========================================
-- CATATAN PENTING
-- ========================================

/*
MAPPING KOLOM CSV KE DATABASE:

CSV Column               -> Database Column           -> Status
=================================================================
idsbr                   -> id_sbr                    -> ✅ SESUAI
nama_usaha              -> nama_usaha                -> ✅ SESUAI  
nama_komersial_usaha    -> nama_komersial_usaha      -> ✅ SESUAI
alamat                  -> alamat                    -> ✅ SESUAI
nama_sls                -> (tidak digunakan)         -> ⚠️  TIDAK DIGUNAKAN
kodepos                 -> kode_pos                  -> ✅ SESUAI
nomor_telepon           -> nomor_telepon             -> ✅ SESUAI
nomor_whatsapp          -> nomor_whatsapp            -> ✅ SESUAI
email                   -> email                     -> ✅ SESUAI
website                 -> website                   -> ✅ SESUAI
latitude                -> latitude                  -> ✅ SESUAI
longitude               -> longitude                 -> ✅ SESUAI
keberadaan_usaha        -> keberadaan_usaha          -> ✅ SESUAI (converted to integer)
kdprov                  -> kd_prov                   -> ✅ SESUAI (padded to 2 digits)
kdkab                   -> kd_kab                    -> ✅ SESUAI (padded to 2 digits)
kdkec                   -> kd_kec                    -> ✅ SESUAI (padded to 3 digits)
kddesa                  -> kd_desa                   -> ✅ SESUAI (padded to 3 digits)
(tidak ada)             -> kd_sls                    -> ❌ TIDAK ADA (default '0000')

KOLOM DATABASE YANG TIDAK ADA DI CSV:
- kd_sls (default: '0000')
- id_sls (generated dari kode wilayah)
- kegiatan_usaha (default JSON)
- skala_usaha (default: 'mikro')
- sumber_data (default: 'BPS')
- semua kolom tambahan lainnya (nullable)

REKOMENDASI:
1. Pastikan data CSV sudah bersih (tidak ada karakter aneh)
2. Validasi koordinat sebelum import
3. Cek duplikasi id_sbr
4. Update kegiatan_usaha dan skala_usaha setelah import jika diperlukan
*/