-- Script untuk membuat view dan tabel kabupaten
-- Untuk keperluan pemilihan data sampai level kabupaten saja

-- 1. Buat view untuk data kabupaten unik
CREATE OR REPLACE VIEW v_kabupaten AS
SELECT DISTINCT 
    kd_prov,
    kd_kab,
    nm_prov,
    nm_kab
FROM wilayah
ORDER BY kd_prov, kd_kab;

-- 2. Buat view untuk data kecamatan per kabupaten (opsional)
CREATE OR REPLACE VIEW v_kecamatan AS
SELECT DISTINCT 
    kd_prov,
    kd_kab,
    kd_kec,
    nm_prov,
    nm_kab,
    nm_kec
FROM wilayah
ORDER BY kd_prov, kd_kab, kd_kec;

-- 3. Buat view untuk data desa per kecamatan (opsional)
CREATE OR REPLACE VIEW v_desa AS
SELECT DISTINCT 
    kd_prov,
    kd_kab,
    kd_kec,
    kd_desa,
    nm_prov,
    nm_kab,
    nm_kec,
    nm_desa
FROM wilayah
ORDER BY kd_prov, kd_kab, kd_kec, kd_desa;

-- 4. Fungsi untuk mendapatkan daftar kabupaten
CREATE OR REPLACE FUNCTION get_daftar_kabupaten()
RETURNS TABLE (
    kd_prov CHAR(2),
    kd_kab CHAR(2),
    nm_prov VARCHAR(50),
    nm_kab VARCHAR(50)
) AS $$
BEGIN
    RETURN QUERY
    SELECT DISTINCT 
        w.kd_prov,
        w.kd_kab,
        w.nm_prov,
        w.nm_kab
    FROM wilayah w
    ORDER BY w.kd_prov, w.kd_kab;
END;
$$ LANGUAGE plpgsql;

-- 5. Fungsi untuk mendapatkan kecamatan berdasarkan kabupaten
CREATE OR REPLACE FUNCTION get_kecamatan_by_kabupaten(
    p_kd_prov CHAR(2),
    p_kd_kab CHAR(2)
)
RETURNS TABLE (
    kd_prov CHAR(2),
    kd_kab CHAR(2),
    kd_kec CHAR(3),
    nm_prov VARCHAR(50),
    nm_kab VARCHAR(50),
    nm_kec VARCHAR(50)
) AS $$
BEGIN
    RETURN QUERY
    SELECT DISTINCT 
        w.kd_prov,
        w.kd_kab,
        w.kd_kec,
        w.nm_prov,
        w.nm_kab,
        w.nm_kec
    FROM wilayah w
    WHERE w.kd_prov = p_kd_prov 
      AND w.kd_kab = p_kd_kab
    ORDER BY w.kd_kec;
END;
$$ LANGUAGE plpgsql;

-- 6. Fungsi untuk mendapatkan desa berdasarkan kecamatan
CREATE OR REPLACE FUNCTION get_desa_by_kecamatan(
    p_kd_prov CHAR(2),
    p_kd_kab CHAR(2),
    p_kd_kec CHAR(3)
)
RETURNS TABLE (
    kd_prov CHAR(2),
    kd_kab CHAR(2),
    kd_kec CHAR(3),
    kd_desa CHAR(3),
    nm_prov VARCHAR(50),
    nm_kab VARCHAR(50),
    nm_kec VARCHAR(50),
    nm_desa VARCHAR(50)
) AS $$
BEGIN
    RETURN QUERY
    SELECT DISTINCT 
        w.kd_prov,
        w.kd_kab,
        w.kd_kec,
        w.kd_desa,
        w.nm_prov,
        w.nm_kab,
        w.nm_kec,
        w.nm_desa
    FROM wilayah w
    WHERE w.kd_prov = p_kd_prov 
      AND w.kd_kab = p_kd_kab
      AND w.kd_kec = p_kd_kec
    ORDER BY w.kd_desa;
END;
$$ LANGUAGE plpgsql;

-- Contoh penggunaan:
-- SELECT * FROM v_kabupaten;
-- SELECT * FROM get_daftar_kabupaten();
-- SELECT * FROM get_kecamatan_by_kabupaten('73', '72');
-- SELECT * FROM get_desa_by_kecamatan('73', '72', '011');