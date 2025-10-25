-- Script untuk mengubah presisi kolom koordinat
-- Mengatasi error "numeric field overflow" dengan meningkatkan presisi
-- Menangani dependency view v_direktori_lengkap

-- LANGKAH 1: Simpan definisi view (jika ada)
DO $$
DECLARE
    view_definition TEXT;
BEGIN
    -- Ambil definisi view jika ada
    SELECT pg_get_viewdef('v_direktori_lengkap', true) INTO view_definition
    WHERE EXISTS (SELECT FROM information_schema.views WHERE table_name = 'v_direktori_lengkap');
    
    -- Drop view sementara
    DROP VIEW IF EXISTS v_direktori_lengkap;
    
    -- LANGKAH 2: Ubah tipe kolom koordinat
    -- latitude: dari DECIMAL(10,8) ke DECIMAL(16,13) 
    -- longitude: dari DECIMAL(11,8) ke DECIMAL(16,13)
    ALTER TABLE direktori ALTER COLUMN latitude TYPE DECIMAL(16,13);
    ALTER TABLE direktori ALTER COLUMN longitude TYPE DECIMAL(16,13);
    
    -- LANGKAH 3: Recreate view v_direktori_lengkap
    CREATE OR REPLACE VIEW v_direktori_lengkap AS
    SELECT 
        -- Kolom direktori (tanpa kd_ untuk hindari duplikasi)
        d.id,
        d.id_sbr,
        d.nama_usaha,
        d.alamat,
        d.id_sls,
        d.keberadaan_usaha,
        d.kegiatan_usaha,
        d.skala_usaha,
        d.keterangan,
        d.nib,
        d.latitude,
        d.longitude,
        d.url_gambar,
        d.kode_pos,
        d.jenis_perusahaan,
        d.pemilik,
        d.nik_pemilik,
        d.nohp_pemilik,
        d.tenaga_kerja,
        d.created_at,
        d.updated_at,
        d.nama_komersial_usaha,
        d.nomor_telepon,
        d.nomor_whatsapp,
        d.email,
        d.website,
        d.sumber_data,
        d.jenis_kepemilikan_usaha,
        d.bentuk_badan_hukum_usaha,
        d.tahun_berdiri,
        d.jaringan_usaha,
        d.sektor_institusi,
        -- Kolom wilayah terselesaikan (coalesce)
        COALESCE(d.kd_prov, w.kd_prov) AS kd_prov,
        COALESCE(d.kd_kab, w.kd_kab) AS kd_kab,
        COALESCE(d.kd_kec, w.kd_kec) AS kd_kec,
        COALESCE(d.kd_desa, w.kd_desa) AS kd_desa,
        COALESCE(d.kd_sls, w.kd_sls) AS kd_sls,
        COALESCE(w.nm_prov, vk.nm_prov) AS nm_prov,
        COALESCE(w.nm_kab, vk.nm_kab) AS nm_kab,
        w.nm_kec,
        w.nm_desa,
        w.nm_sls,
        w.alamat_lengkap
    FROM direktori d
    LEFT JOIN wilayah w ON d.id_sls = w.id_sls
    LEFT JOIN (
        SELECT DISTINCT kd_prov, kd_kab, nm_prov, nm_kab FROM wilayah
    ) vk ON d.id_sls IS NULL AND d.kd_prov = vk.kd_prov AND d.kd_kab = vk.kd_kab;
    
    RAISE NOTICE 'Kolom koordinat berhasil diubah ke DECIMAL(16,13) dan view v_direktori_lengkap telah dibuat ulang';
END $$;

-- Opsi 2: Menggunakan DOUBLE PRECISION (alternatif)
-- Jika ingin presisi maksimal tanpa batasan digit
-- ALTER TABLE direktori 
-- ALTER COLUMN latitude TYPE DOUBLE PRECISION;

-- ALTER TABLE direktori 
-- ALTER COLUMN longitude TYPE DOUBLE PRECISION;

-- Verifikasi perubahan
SELECT 
    column_name, 
    data_type, 
    numeric_precision, 
    numeric_scale
FROM information_schema.columns 
WHERE table_name = 'direktori' 
AND column_name IN ('latitude', 'longitude');

-- Test insert dengan koordinat presisi tinggi (13 digit setelah koma)
-- INSERT INTO direktori (id_sbr, nama_usaha, latitude, longitude) 
-- VALUES ('TEST001', 'Test Koordinat', -5.1234567890123, 119.9876543210987);