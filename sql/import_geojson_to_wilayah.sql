-- Script untuk import data GeoJSON ke tabel wilayah
-- Berdasarkan data dari final_sls.geojson

-- Pastikan tabel wilayah sudah dibuat terlebih dahulu
-- Jalankan create_single_wilayah_table.sql sebelum script ini

-- Insert data dari GeoJSON ke tabel wilayah
-- Hanya mengambil field yang dibutuhkan sesuai skema tabel wilayah

INSERT INTO wilayah (id_sls, kd_prov, kd_kab, kd_kec, kd_desa, kd_sls, nm_prov, nm_kab, nm_kec, nm_desa, nm_sls) VALUES
('73720110010009', '73', '72', '011', '001', '0009', 'SULAWESI SELATAN', 'PAREPARE', 'BACUKIKI BARAT', 'LUMPUE', 'RT 002 RW 004'),
('73720110010012', '73', '72', '011', '001', '0012', 'SULAWESI SELATAN', 'PAREPARE', 'BACUKIKI BARAT', 'LUMPUE', 'RT 001 RW 006')
ON CONFLICT (id_sls) DO UPDATE SET
    kd_prov = EXCLUDED.kd_prov,
    kd_kab = EXCLUDED.kd_kab,
    kd_kec = EXCLUDED.kd_kec,
    kd_desa = EXCLUDED.kd_desa,
    kd_sls = EXCLUDED.kd_sls,
    nm_prov = EXCLUDED.nm_prov,
    nm_kab = EXCLUDED.nm_kab,
    nm_kec = EXCLUDED.nm_kec,
    nm_desa = EXCLUDED.nm_desa,
    nm_sls = EXCLUDED.nm_sls,
    updated_at = NOW();

-- Verifikasi data yang telah diimport
SELECT 
    id_sls,
    kd_prov,
    kd_kab,
    kd_kec,
    kd_desa,
    kd_sls,
    nm_prov,
    nm_kab,
    nm_kec,
    nm_desa,
    nm_sls,
    alamat_lengkap,
    created_at,
    updated_at
FROM wilayah 
WHERE id_sls IN ('73720110010009', '73720110010012')
ORDER BY id_sls;