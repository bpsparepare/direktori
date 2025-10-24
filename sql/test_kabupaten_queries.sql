-- Script untuk testing query kabupaten
-- Jalankan setelah create_kabupaten_view.sql

-- Test 1: Lihat semua kabupaten yang tersedia
SELECT 'Test 1: Daftar Kabupaten' as test_name;
SELECT * FROM v_kabupaten;

-- Test 2: Hitung jumlah kabupaten
SELECT 'Test 2: Jumlah Kabupaten' as test_name;
SELECT COUNT(*) as total_kabupaten FROM v_kabupaten;

-- Test 3: Test fungsi get_daftar_kabupaten()
SELECT 'Test 3: Fungsi get_daftar_kabupaten()' as test_name;
SELECT * FROM get_daftar_kabupaten();

-- Test 4: Lihat kecamatan untuk kabupaten Parepare (kd_kab = '72')
SELECT 'Test 4: Kecamatan di Parepare' as test_name;
SELECT * FROM get_kecamatan_by_kabupaten('73', '72');

-- Test 5: Lihat desa di kecamatan Bacukiki Barat (kd_kec = '011')
SELECT 'Test 5: Desa di Bacukiki Barat' as test_name;
SELECT * FROM get_desa_by_kecamatan('73', '72', '011');

-- Test 6: Verifikasi data hierarki
SELECT 'Test 6: Verifikasi Hierarki Data' as test_name;
SELECT 
    COUNT(DISTINCT kd_prov) as total_provinsi,
    COUNT(DISTINCT CONCAT(kd_prov, kd_kab)) as total_kabupaten,
    COUNT(DISTINCT CONCAT(kd_prov, kd_kab, kd_kec)) as total_kecamatan,
    COUNT(DISTINCT CONCAT(kd_prov, kd_kab, kd_kec, kd_desa)) as total_desa,
    COUNT(*) as total_sls
FROM wilayah;

-- Test 7: Contoh query untuk dropdown kabupaten
SELECT 'Test 7: Format untuk Dropdown Kabupaten' as test_name;
SELECT 
    CONCAT(kd_prov, kd_kab) as kode_kabupaten,
    CONCAT(nm_kab, ', ', nm_prov) as nama_lengkap
FROM v_kabupaten
ORDER BY nm_prov, nm_kab;