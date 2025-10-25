-- ========================================
-- IMPORT BPS CSV DATA TO DIREKTORI TABLE
-- ========================================
-- Script untuk mengimpor data dari importbps.csv ke tabel direktori
-- Dapat dijalankan langsung di Supabase SQL Editor
-- File: import_bps_csv_direct.sql

-- ========================================
-- STEP 1: INSERT DATA LANGSUNG
-- ========================================

-- Insert data BPS langsung ke tabel direktori
-- Data diambil dari importbps.csv dengan struktur:
-- idsbr,nama_usaha,nama_komersial_usaha,alamat,nama_sls,kodepos,nomor_telepon,nomor_whatsapp,email,website,latitude,longitude,keberadaan_usaha,kdprov,kdkab,kdkec,kddesa

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
) VALUES
-- Sample data dari CSV (ganti dengan data lengkap Anda)
(97447640, 'LPK SATRIA (MUHAMMAD FERY SATRIADI AZIS)', NULL, 'JL MUH ARSYAD NO 40', NULL, '73', '72', '030', '004', NULL, NULL, 1, '420640', NULL, 'HOMENETPARE@GMAIL.COM', NULL, NULL, NULL, NULL, 'BPS', '[{"kegiatan_usaha": "Belum Dikategorikan", "kategori": "Umum", "kbli": "00000"}]'::jsonb, 'mikro'),
(97446322, 'BIMBINGAN BELAJAR <MARDAWIAH>', NULL, 'JALAN AGUS SALIM', NULL, '73', '72', '011', '006', NULL, NULL, 1, '085242368429', NULL, NULL, NULL, NULL, NULL, NULL, 'BPS', '[{"kegiatan_usaha": "Belum Dikategorikan", "kategori": "Umum", "kbli": "00000"}]'::jsonb, 'mikro'),
(97446148, 'RUMAH MAKAN PALEKKO MANGGAU', NULL, 'JALAN MATTIRO NO99', NULL, '73', '72', '011', '006', NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'BPS', '[{"kegiatan_usaha": "Belum Dikategorikan", "kategori": "Umum", "kbli": "00000"}]'::jsonb, 'mikro'),
(97446128, 'WARNET SABRI', NULL, 'JL H AGUS SALIM', NULL, '73', '72', '011', '005', NULL, NULL, 1, '085397779494', NULL, NULL, NULL, NULL, NULL, NULL, 'BPS', '[{"kegiatan_usaha": "Belum Dikategorikan", "kategori": "Umum", "kbli": "00000"}]'::jsonb, 'mikro');

-- ========================================
-- STEP 2: ALTERNATIF - BULK INSERT TEMPLATE
-- ========================================

-- Jika Anda ingin menggunakan semua data CSV, gunakan template ini:
-- Ganti VALUES dengan semua data dari CSV Anda

/*
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
) VALUES
-- Paste semua data CSV di sini dalam format:
-- (id_sbr, 'nama_usaha', 'nama_komersial', 'alamat', 'nama_sls', 'kd_prov', 'kd_kab', 'kd_kec', 'kd_desa', NULL, NULL, keberadaan_usaha, 'nomor_telepon', 'nomor_whatsapp', 'email', 'website', latitude, longitude, 'kode_pos', 'BPS', '[{"kegiatan_usaha": "Belum Dikategorikan"}]'::jsonb, 'mikro'),
-- ... tambahkan semua baris lainnya
;
*/

-- ========================================
-- STEP 3: VALIDASI HASIL IMPORT
-- ========================================

-- Cek jumlah data yang berhasil diimpor
SELECT 'Total BPS records imported' as info, COUNT(*) as count 
FROM direktori 
WHERE sumber_data = 'BPS';

-- Cek data dengan koordinat
SELECT 'Records with coordinates' as info, COUNT(*) as count 
FROM direktori 
WHERE sumber_data = 'BPS' 
  AND latitude IS NOT NULL 
  AND longitude IS NOT NULL;

-- Cek distribusi per wilayah
SELECT 
    kd_prov,
    kd_kab,
    kd_kec,
    kd_desa,
    COUNT(*) as jumlah_usaha
FROM direktori 
WHERE sumber_data = 'BPS'
GROUP BY kd_prov, kd_kab, kd_kec, kd_desa
ORDER BY kd_prov, kd_kab, kd_kec, kd_desa;

-- Sample data yang berhasil diimpor
SELECT 
    id_sbr,
    nama_usaha,
    alamat,
    CONCAT(kd_prov, kd_kab, kd_kec, kd_desa) as kode_wilayah,
    nomor_telepon,
    email,
    created_at
FROM direktori 
WHERE sumber_data = 'BPS'
ORDER BY created_at DESC
LIMIT 10;

-- ========================================
-- STEP 4: SCRIPT GENERATOR UNTUK SEMUA DATA
-- ========================================

-- Untuk mengkonversi semua data CSV ke format SQL INSERT:
-- 1. Buka file importbps.csv
-- 2. Gunakan script Python/Excel untuk generate INSERT statements
-- 3. Atau gunakan tool online CSV to SQL converter
-- 4. Format setiap baris seperti contoh di atas

-- Template untuk setiap baris CSV:
-- (idsbr, 'nama_usaha', NULLIF('nama_komersial_usaha',''), NULLIF('alamat',''), NULLIF('nama_sls',''), 'kdprov', 'kdkab', 'kdkec', 'kddesa', NULL, NULL, keberadaan_usaha, NULLIF('nomor_telepon',''), NULLIF('nomor_whatsapp',''), NULLIF('email',''), NULLIF('website',''), CASE WHEN latitude != '' THEN latitude::decimal ELSE NULL END, CASE WHEN longitude != '' THEN longitude::decimal ELSE NULL END, NULLIF('kodepos',''), 'BPS', '[{"kegiatan_usaha": "Belum Dikategorikan", "kategori": "Umum", "kbli": "00000"}]'::jsonb, 'mikro')

-- ========================================
-- CATATAN PENTING
-- ========================================
-- 1. Script ini hanya berisi sample data (4 baris pertama)
-- 2. Untuk import semua 6,052 records, Anda perlu:
--    a. Convert CSV ke format INSERT VALUES
--    b. Atau gunakan client library (JavaScript/Python)
--    c. Atau gunakan Supabase dashboard untuk bulk upload
-- 3. Pastikan tidak ada duplikasi id_sbr
-- 4. Validasi data setelah import