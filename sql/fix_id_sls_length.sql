-- Script untuk memperbaiki panjang kolom id_sls dan kd_sls
-- Mengatasi error: value too long for type character varying(13)
-- Menangani dependency view v_direktori_lengkap
-- Memperbaiki kd_sls dari CHAR(3) ke CHAR(4)

DO $$
DECLARE
    view_definition TEXT;
BEGIN
    IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'wilayah') THEN
        -- Simpan definisi view jika ada
        SELECT pg_get_viewdef('v_direktori_lengkap', true) INTO view_definition
        WHERE EXISTS (SELECT FROM information_schema.views WHERE table_name = 'v_direktori_lengkap');
        
        -- Drop view yang bergantung pada kolom id_sls
        DROP VIEW IF EXISTS v_direktori_lengkap;
        
        -- Drop functions yang bergantung pada kd_sls
        DROP FUNCTION IF EXISTS get_daftar_sls(CHAR(2), CHAR(2), CHAR(3), CHAR(3));
        
        -- Ubah panjang kolom id_sls dari VARCHAR(13) ke VARCHAR(15)
        ALTER TABLE wilayah ALTER COLUMN id_sls TYPE VARCHAR(15);
        
        -- Ubah panjang kolom kd_sls dari CHAR(3) ke CHAR(4)
        ALTER TABLE wilayah ALTER COLUMN kd_sls TYPE CHAR(4);
        
        -- Juga update kolom id_sls di tabel direktori jika ada
        IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'direktori') THEN
            ALTER TABLE direktori ALTER COLUMN id_sls TYPE VARCHAR(15);
        END IF;
        
        -- Recreate function get_daftar_sls dengan parameter yang benar
        CREATE FUNCTION get_daftar_sls(p_kd_prov CHAR(2), p_kd_kab CHAR(2), p_kd_kec CHAR(3), p_kd_desa CHAR(3))
        RETURNS TABLE(kd_sls CHAR(4), nm_sls VARCHAR(100), id_sls VARCHAR(15)) AS $func$
        BEGIN
            RETURN QUERY
            SELECT DISTINCT w.kd_sls, w.nm_sls, w.id_sls
            FROM wilayah w 
            WHERE w.kd_prov = p_kd_prov 
                AND w.kd_kab = p_kd_kab 
                AND w.kd_kec = p_kd_kec 
                AND w.kd_desa = p_kd_desa
            ORDER BY w.nm_sls;
        END;
        $func$ LANGUAGE plpgsql;
        
        -- Recreate view v_direktori_lengkap
        CREATE VIEW v_direktori_lengkap AS
        SELECT 
            d.*,
            w.kd_prov,
            w.kd_kab,
            w.kd_kec,
            w.kd_desa,
            w.kd_sls,
            w.nm_prov,
            w.nm_kab,
            w.nm_kec,
            w.nm_desa,
            w.nm_sls,
            w.alamat_lengkap
        FROM direktori d
        JOIN wilayah w ON d.id_sls = w.id_sls;
        
        RAISE NOTICE 'Kolom id_sls berhasil diubah ke VARCHAR(15), kd_sls ke CHAR(4), dan view v_direktori_lengkap telah dibuat ulang';
    ELSE
        RAISE NOTICE 'Tabel wilayah belum ada. Jalankan create_single_wilayah_table.sql terlebih dahulu';
    END IF;
END $$;

-- Verifikasi perubahan
SELECT 
    column_name, 
    data_type, 
    character_maximum_length 
FROM information_schema.columns 
WHERE table_name = 'wilayah' 
    AND column_name = 'id_sls';