-- =====================================================
-- OPTIMASI TABEL DIREKTORI UNTUK SISTEM KONTRIBUSI
-- =====================================================
-- File: optimize_direktori_for_contributions.sql
-- Deskripsi: Mengoptimalkan constraint tabel direktori untuk mendukung sistem kontribusi
-- Catatan: Script ini OPSIONAL - tidak mengubah struktur tabel
-- =====================================================

-- 1. Update constraint sumber_data untuk mendukung kontribusi pengguna
ALTER TABLE direktori DROP CONSTRAINT IF EXISTS direktori_sumber_data_check;
ALTER TABLE direktori ADD CONSTRAINT direktori_sumber_data_check 
CHECK (
    sumber_data IN (
        'BPS', 
        'Lapangan', 
        'Online', 
        'Referensi', 
        'Lainnya', 
        'Kontribusi_User',
        'Verifikasi_User'
    )
);

-- 2. Update constraint keterangan untuk tracking jenis kontribusi
ALTER TABLE direktori DROP CONSTRAINT IF EXISTS direktori_keterangan_check;
ALTER TABLE direktori ADD CONSTRAINT direktori_keterangan_check 
CHECK (
    keterangan IN (
        'duplikat bps', 
        'tambahan', 
        'edit_user', 
        'verifikasi_user', 
        'koreksi_koordinat',
        'update_info',
        'validasi_lapangan'
    )
);

-- 3. Tambahkan index untuk performa query kontribusi
CREATE INDEX IF NOT EXISTS idx_direktori_sumber_kontribusi 
ON direktori(sumber_data) 
WHERE sumber_data IN ('Kontribusi_User', 'Verifikasi_User');

CREATE INDEX IF NOT EXISTS idx_direktori_keterangan_kontribusi 
ON direktori(keterangan) 
WHERE keterangan IN ('edit_user', 'verifikasi_user', 'koreksi_koordinat');

-- 4. Function untuk auto-update sumber_data saat ada kontribusi
CREATE OR REPLACE FUNCTION update_direktori_contribution_metadata()
RETURNS TRIGGER AS $$
BEGIN
    -- Jika ada perubahan dari sistem kontribusi, update metadata
    IF TG_OP = 'UPDATE' AND OLD.updated_at != NEW.updated_at THEN
        -- Cek apakah ini update dari kontribusi pengguna
        -- (bisa ditambahkan logic lebih kompleks sesuai kebutuhan)
        IF NEW.sumber_data = 'Kontribusi_User' THEN
            NEW.keterangan = 'edit_user';
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 5. Trigger untuk auto-update metadata kontribusi
DROP TRIGGER IF EXISTS trigger_direktori_contribution_metadata ON direktori;
CREATE TRIGGER trigger_direktori_contribution_metadata
    BEFORE UPDATE ON direktori
    FOR EACH ROW
    EXECUTE FUNCTION update_direktori_contribution_metadata();

-- =====================================================
-- QUERY HELPER UNTUK SISTEM KONTRIBUSI
-- =====================================================

-- View untuk melihat data yang berasal dari kontribusi pengguna
CREATE OR REPLACE VIEW v_direktori_kontribusi_user AS
SELECT 
    d.*,
    CASE 
        WHEN d.sumber_data IN ('Kontribusi_User', 'Verifikasi_User') THEN true
        ELSE false
    END as is_user_contribution
FROM direktori d
WHERE d.sumber_data IN ('Kontribusi_User', 'Verifikasi_User', 'Lapangan');

-- Function untuk mendapatkan statistik kontribusi per wilayah
CREATE OR REPLACE FUNCTION get_contribution_stats_by_region(
    p_kd_prov VARCHAR(2) DEFAULT NULL,
    p_kd_kab VARCHAR(2) DEFAULT NULL
)
RETURNS TABLE(
    total_direktori BIGINT,
    kontribusi_user BIGINT,
    verifikasi_user BIGINT,
    persentase_kontribusi NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        COUNT(*) as total_direktori,
        COUNT(*) FILTER (WHERE sumber_data = 'Kontribusi_User') as kontribusi_user,
        COUNT(*) FILTER (WHERE sumber_data = 'Verifikasi_User') as verifikasi_user,
        ROUND(
            (COUNT(*) FILTER (WHERE sumber_data IN ('Kontribusi_User', 'Verifikasi_User')) * 100.0) / 
            NULLIF(COUNT(*), 0), 
            2
        ) as persentase_kontribusi
    FROM direktori d
    WHERE 
        (p_kd_prov IS NULL OR d.kd_prov = p_kd_prov) AND
        (p_kd_kab IS NULL OR d.kd_kab = p_kd_kab);
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- CONTOH PENGGUNAAN
-- =====================================================

/*
-- Contoh 1: Update record sebagai hasil kontribusi pengguna
UPDATE direktori 
SET 
    nama_usaha = 'Nama Baru Hasil Kontribusi',
    sumber_data = 'Kontribusi_User',
    updated_at = NOW()
WHERE id = 'uuid-target';

-- Contoh 2: Lihat semua data hasil kontribusi pengguna
SELECT * FROM v_direktori_kontribusi_user 
WHERE is_user_contribution = true;

-- Contoh 3: Statistik kontribusi untuk Sulawesi Selatan
SELECT * FROM get_contribution_stats_by_region('73');

-- Contoh 4: Statistik kontribusi untuk Kab. Parepare
SELECT * FROM get_contribution_stats_by_region('73', '71');
*/

-- =====================================================
-- CATATAN PENTING
-- =====================================================
/*
1. Script ini OPSIONAL - tabel direktori sudah cukup baik tanpa perubahan
2. Constraint yang diupdate hanya menambah nilai baru, tidak mengubah yang lama
3. Index tambahan akan mempercepat query untuk data kontribusi
4. Function dan view membantu analisis kontribusi pengguna
5. Trigger otomatis akan membantu tracking metadata kontribusi
*/