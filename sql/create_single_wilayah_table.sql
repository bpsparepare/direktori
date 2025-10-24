-- Script SQL Efisien: Satu Tabel Wilayah
-- Cocok untuk data Excel yang sudah lengkap
-- UPDATE: Menambahkan kolom baru dan menggunakan ALTER TABLE untuk tabel yang sudah ada

-- ========================================
-- DROP SEMUA OBJEK YANG ADA (CLEAN START)
-- ========================================

-- Drop view terlebih dahulu
DROP VIEW IF EXISTS v_direktori_lengkap;

-- Drop trigger
DROP TRIGGER IF EXISTS update_wilayah_updated_at ON wilayah;
DROP TRIGGER IF EXISTS update_direktori_updated_at ON direktori;

-- Drop function dengan CASCADE untuk menghapus semua dependency
DROP FUNCTION IF EXISTS update_updated_at_column() CASCADE;
DROP FUNCTION IF EXISTS get_daftar_provinsi() CASCADE;
DROP FUNCTION IF EXISTS get_daftar_kabupaten(CHAR(2)) CASCADE;
DROP FUNCTION IF EXISTS get_daftar_kecamatan(CHAR(2), CHAR(2)) CASCADE;
DROP FUNCTION IF EXISTS get_daftar_desa(CHAR(2), CHAR(2), CHAR(3)) CASCADE;
DROP FUNCTION IF EXISTS get_daftar_sls(CHAR(2), CHAR(2), CHAR(3), CHAR(3)) CASCADE;

-- Drop table (dengan CASCADE untuk menghapus semua dependency)
DROP TABLE IF EXISTS direktori CASCADE;
DROP TABLE IF EXISTS wilayah CASCADE;

-- ========================================
-- TABEL WILAYAH TUNGGAL (RECOMMENDED)
-- ========================================

-- Buat tabel wilayah jika belum ada
CREATE TABLE IF NOT EXISTS wilayah (
    -- ID SLS sebagai Primary Key (14 digit)
    id_sls VARCHAR(14) PRIMARY KEY,
    
    -- Kode Wilayah (untuk kompatibilitas dan index)
    kd_prov CHAR(2) NOT NULL,
    kd_kab CHAR(2) NOT NULL,
    kd_kec CHAR(3) NOT NULL,
    kd_desa CHAR(3) NOT NULL,
    kd_sls CHAR(4) NOT NULL,
    
    -- Nama Wilayah
    nm_prov VARCHAR(100) NOT NULL,
    nm_kab VARCHAR(100) NOT NULL,
    nm_kec VARCHAR(100) NOT NULL,
    nm_desa VARCHAR(100) NOT NULL,
    nm_sls VARCHAR(100) NOT NULL,
    
    -- Alamat lengkap untuk kemudahan
    alamat_lengkap TEXT GENERATED ALWAYS AS (
        nm_prov || ' - ' || nm_kab || ' - ' || nm_kec || ' - ' || nm_desa || ' - ' || nm_sls
    ) STORED,
    
    -- Timestamp
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    -- Constraint untuk memastikan id_sls sesuai dengan kode
    CONSTRAINT chk_id_sls CHECK (id_sls = kd_prov || kd_kab || kd_kec || kd_desa || kd_sls)
);

-- ========================================
-- TABEL DIREKTORI (SIMPLIFIED)
-- ========================================

-- Buat tabel direktori jika belum ada
CREATE TABLE IF NOT EXISTS direktori (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    
    -- Identifikasi Usaha
    id_sbr VARCHAR(50) UNIQUE NOT NULL,
    nama_usaha VARCHAR(255) NOT NULL,
    alamat TEXT,
    
    -- Relasi ke Wilayah: bisa SLS atau level kabupaten
    id_sls VARCHAR(14),
    kd_prov CHAR(2),
    kd_kab CHAR(2),
    kd_kec CHAR(3),
    kd_desa CHAR(3),
    kd_sls CHAR(4),
    
    -- Status dan Kategori
    keberadaan_usaha INTEGER CHECK (
        keberadaan_usaha IN (1, 2, 3, 4, 5, 6, 7, 8, 9, 10)
    ) DEFAULT 1,
    
    -- Kegiatan Usaha (JSON Array)
    kegiatan_usaha JSONB DEFAULT '[]'::jsonb,
    
    -- Skala Usaha
    skala_usaha VARCHAR(20) CHECK (
        skala_usaha IN ('mikro', 'kecil', 'menengah', 'besar')
    ),
    
    -- Informasi Tambahan
    keterangan VARCHAR(100) CHECK (
        keterangan IN ('duplikat bps', 'tambahan')
    ),
    nib VARCHAR(50),
    
    -- Koordinat
    latitude DECIMAL(10, 8),
    longitude DECIMAL(11, 8),
    
    -- Media dan Kontak
    url_gambar TEXT,
    kode_pos CHAR(5),
    jenis_perusahaan VARCHAR(50),
    
    -- Data Pemilik
    pemilik VARCHAR(255),
    nik_pemilik VARCHAR(16),
    nohp_pemilik VARCHAR(20),
    
    -- Tenaga Kerja
    tenaga_kerja INTEGER DEFAULT 0,
    
    -- Timestamp
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    -- Constraint konsistensi wilayah minimal
    CONSTRAINT chk_direktori_wilayah_minimal CHECK (
        (id_sls IS NULL AND kd_prov IS NOT NULL AND kd_kab IS NOT NULL)
        OR
        (id_sls IS NOT NULL AND kd_prov IS NOT NULL AND kd_kab IS NOT NULL AND kd_kec IS NOT NULL AND kd_desa IS NOT NULL AND kd_sls IS NOT NULL AND id_sls = kd_prov || kd_kab || kd_kec || kd_desa || kd_sls)
    ),
    
    -- Foreign Key ke tabel wilayah (opsional: hanya jika id_sls diisi)
    FOREIGN KEY (id_sls) REFERENCES wilayah(id_sls)
);

-- ========================================
-- ALTER TABLE: MENAMBAHKAN KOLOM BARU
-- ========================================

-- Tambahkan kolom baru ke tabel direktori jika belum ada
DO $$
BEGIN
    -- Ubah id_sls menjadi nullable jika saat ini NOT NULL
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='direktori' AND column_name='id_sls' AND is_nullable = 'NO') THEN
        ALTER TABLE direktori ALTER COLUMN id_sls DROP NOT NULL;
    END IF;

    -- kd_prov
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='direktori' AND column_name='kd_prov') THEN
        ALTER TABLE direktori ADD COLUMN kd_prov CHAR(2);
    END IF;
    -- kd_kab
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='direktori' AND column_name='kd_kab') THEN
        ALTER TABLE direktori ADD COLUMN kd_kab CHAR(2);
    END IF;
    -- kd_kec
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='direktori' AND column_name='kd_kec') THEN
        ALTER TABLE direktori ADD COLUMN kd_kec CHAR(3);
    END IF;
    -- kd_desa
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='direktori' AND column_name='kd_desa') THEN
        ALTER TABLE direktori ADD COLUMN kd_desa CHAR(3);
    END IF;
    -- kd_sls
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='direktori' AND column_name='kd_sls') THEN
        ALTER TABLE direktori ADD COLUMN kd_sls CHAR(4);
    END IF;

    -- nama_komersial_usaha
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='direktori' AND column_name='nama_komersial_usaha') THEN
        ALTER TABLE direktori ADD COLUMN nama_komersial_usaha VARCHAR(255);
    END IF;
    
    -- nomor_telepon
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='direktori' AND column_name='nomor_telepon') THEN
        ALTER TABLE direktori ADD COLUMN nomor_telepon VARCHAR(20);
    END IF;
    
    -- nomor_whatsapp
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='direktori' AND column_name='nomor_whatsapp') THEN
        ALTER TABLE direktori ADD COLUMN nomor_whatsapp VARCHAR(20);
    END IF;
    
    -- email
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='direktori' AND column_name='email') THEN
        ALTER TABLE direktori ADD COLUMN email VARCHAR(255);
    END IF;
    
    -- website
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='direktori' AND column_name='website') THEN
        ALTER TABLE direktori ADD COLUMN website TEXT;
    END IF;
    
    -- sumber_data
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='direktori' AND column_name='sumber_data') THEN
        ALTER TABLE direktori ADD COLUMN sumber_data VARCHAR(100) CHECK (
            sumber_data IN ('BPS', 'Lapangan', 'Online', 'Referensi', 'Lainnya')
        ) DEFAULT 'BPS';
    END IF;
    
    -- latitude (mengganti lat)
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='direktori' AND column_name='latitude') THEN
        ALTER TABLE direktori ADD COLUMN latitude DECIMAL(10, 8);
        -- Copy data dari lat ke latitude jika ada
        UPDATE direktori SET latitude = lat WHERE lat IS NOT NULL;
    END IF;
    
    -- longitude (mengganti long)
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='direktori' AND column_name='longitude') THEN
        ALTER TABLE direktori ADD COLUMN longitude DECIMAL(11, 8);
        -- Copy data dari long ke longitude jika ada
        UPDATE direktori SET longitude = long WHERE long IS NOT NULL;
    END IF;
    
    -- keberadaan_usaha (status keberadaan usaha)
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='direktori' AND column_name='keberadaan_usaha') THEN
        ALTER TABLE direktori ADD COLUMN keberadaan_usaha INTEGER CHECK (
            keberadaan_usaha IN (1, 2, 3, 4, 5, 6, 7, 8, 9, 10)
        ) DEFAULT 1;
    END IF;
    
    -- jenis_kepemilikan_usaha
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='direktori' AND column_name='jenis_kepemilikan_usaha') THEN
        ALTER TABLE direktori ADD COLUMN jenis_kepemilikan_usaha INTEGER CHECK (
            jenis_kepemilikan_usaha IN (1, 2, 3, 4)
        );
    END IF;
    
    -- bentuk_badan_hukum_usaha
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='direktori' AND column_name='bentuk_badan_hukum_usaha') THEN
        ALTER TABLE direktori ADD COLUMN bentuk_badan_hukum_usaha INTEGER CHECK (
            bentuk_badan_hukum_usaha IN (1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 99)
        );
    END IF;
    
    -- deskripsi_badan_usaha_lainnya (untuk bentuk_badan_hukum_usaha = 99)
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='direktori' AND column_name='deskripsi_badan_usaha_lainnya') THEN
        ALTER TABLE direktori ADD COLUMN deskripsi_badan_usaha_lainnya VARCHAR(255);
    END IF;
    
    -- tahun_berdiri
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='direktori' AND column_name='tahun_berdiri') THEN
        ALTER TABLE direktori ADD COLUMN tahun_berdiri INTEGER CHECK (
            tahun_berdiri >= 1900 AND tahun_berdiri <= EXTRACT(YEAR FROM NOW())
        );
    END IF;
    
    -- jaringan_usaha
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='direktori' AND column_name='jaringan_usaha') THEN
        ALTER TABLE direktori ADD COLUMN jaringan_usaha INTEGER CHECK (
            jaringan_usaha IN (1, 2, 3, 4, 5, 6)
        );
    END IF;
    
    -- sektor_institusi
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='direktori' AND column_name='sektor_institusi') THEN
        ALTER TABLE direktori ADD COLUMN sektor_institusi INTEGER CHECK (
            sektor_institusi IN (1, 2, 3, 4, 5)
        );
    END IF;

    -- Tambahkan constraint konsistensi wilayah minimal jika belum ada
    IF NOT EXISTS (SELECT 1 FROM information_schema.table_constraints WHERE table_name='direktori' AND constraint_name='chk_direktori_wilayah_minimal') THEN
        ALTER TABLE direktori ADD CONSTRAINT chk_direktori_wilayah_minimal CHECK (
            (id_sls IS NULL AND kd_prov IS NOT NULL AND kd_kab IS NOT NULL)
            OR
            (id_sls IS NOT NULL AND kd_prov IS NOT NULL AND kd_kab IS NOT NULL AND kd_kec IS NOT NULL AND kd_desa IS NOT NULL AND kd_sls IS NOT NULL AND id_sls = kd_prov || kd_kab || kd_kec || kd_desa || kd_sls)
        );
    END IF;
END $$;

-- ========================================
-- INDEX UNTUK PERFORMA OPTIMAL
-- ========================================

-- Index untuk tabel wilayah
CREATE INDEX IF NOT EXISTS idx_wilayah_prov ON wilayah(kd_prov);
CREATE INDEX IF NOT EXISTS idx_wilayah_kab ON wilayah(kd_prov, kd_kab);
CREATE INDEX IF NOT EXISTS idx_wilayah_kec ON wilayah(kd_prov, kd_kab, kd_kec);
CREATE INDEX IF NOT EXISTS idx_wilayah_desa ON wilayah(kd_prov, kd_kab, kd_kec, kd_desa);
CREATE INDEX IF NOT EXISTS idx_wilayah_nama_prov ON wilayah(nm_prov);
CREATE INDEX IF NOT EXISTS idx_wilayah_nama_kab ON wilayah(nm_kab);
CREATE INDEX IF NOT EXISTS idx_wilayah_search ON wilayah USING gin(to_tsvector('indonesian', alamat_lengkap));

-- Index untuk tabel direktori
CREATE INDEX IF NOT EXISTS idx_direktori_id_sbr ON direktori(id_sbr);
CREATE INDEX IF NOT EXISTS idx_direktori_id_sls ON direktori(id_sls);
CREATE INDEX IF NOT EXISTS idx_direktori_kab ON direktori(kd_prov, kd_kab);
CREATE INDEX IF NOT EXISTS idx_direktori_status ON direktori(keberadaan_usaha);
CREATE INDEX IF NOT EXISTS idx_direktori_skala ON direktori(skala_usaha);
CREATE INDEX IF NOT EXISTS idx_direktori_koordinat ON direktori(latitude, longitude);
CREATE INDEX IF NOT EXISTS idx_direktori_nama_usaha ON direktori USING gin(to_tsvector('indonesian', nama_usaha));

-- ========================================
-- FUNCTION DAN TRIGGER
-- ========================================

-- Function untuk update timestamp
CREATE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Trigger untuk tabel wilayah
CREATE TRIGGER update_wilayah_updated_at BEFORE UPDATE ON wilayah FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Trigger untuk tabel direktori
CREATE TRIGGER update_direktori_updated_at BEFORE UPDATE ON direktori FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ========================================
-- VIEW UNTUK KEMUDAHAN QUERY
-- ========================================

-- View direktori dengan nama wilayah (SIMPLE JOIN)
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

-- ========================================
-- FUNCTION HELPER UNTUK DROPDOWN
-- ========================================

-- Function untuk mendapatkan daftar provinsi
CREATE FUNCTION get_daftar_provinsi()
RETURNS TABLE(kd_prov CHAR(2), nm_prov VARCHAR(100)) AS $$
BEGIN
    RETURN QUERY
    SELECT DISTINCT w.kd_prov, w.nm_prov 
    FROM wilayah w 
    ORDER BY w.nm_prov;
END;
$$ LANGUAGE plpgsql;

-- Function untuk mendapatkan daftar kabupaten berdasarkan provinsi
CREATE FUNCTION get_daftar_kabupaten(p_kd_prov CHAR(2))
RETURNS TABLE(kd_kab CHAR(2), nm_kab VARCHAR(100)) AS $$
BEGIN
    RETURN QUERY
    SELECT DISTINCT w.kd_kab, w.nm_kab 
    FROM wilayah w 
    WHERE w.kd_prov = p_kd_prov
    ORDER BY w.nm_kab;
END;
$$ LANGUAGE plpgsql;

-- Function untuk mendapatkan daftar kecamatan berdasarkan kabupaten
CREATE FUNCTION get_daftar_kecamatan(p_kd_prov CHAR(2), p_kd_kab CHAR(2))
RETURNS TABLE(kd_kec CHAR(3), nm_kec VARCHAR(100)) AS $$
BEGIN
    RETURN QUERY
    SELECT DISTINCT w.kd_kec, w.nm_kec 
    FROM wilayah w 
    WHERE w.kd_prov = p_kd_prov AND w.kd_kab = p_kd_kab
    ORDER BY w.nm_kec;
END;
$$ LANGUAGE plpgsql;

-- Function untuk mendapatkan daftar desa berdasarkan kecamatan
CREATE FUNCTION get_daftar_desa(p_kd_prov CHAR(2), p_kd_kab CHAR(2), p_kd_kec CHAR(3))
RETURNS TABLE(kd_desa CHAR(3), nm_desa VARCHAR(100)) AS $$
BEGIN
    RETURN QUERY
    SELECT DISTINCT w.kd_desa, w.nm_desa 
    FROM wilayah w 
    WHERE w.kd_prov = p_kd_prov AND w.kd_kab = p_kd_kab AND w.kd_kec = p_kd_kec
    ORDER BY w.nm_desa;
END;
$$ LANGUAGE plpgsql;

-- Function untuk mendapatkan daftar SLS berdasarkan desa
CREATE FUNCTION get_daftar_sls(p_kd_prov CHAR(2), p_kd_kab CHAR(2), p_kd_kec CHAR(3), p_kd_desa CHAR(3))
RETURNS TABLE(kd_sls CHAR(4), nm_sls VARCHAR(100), id_sls VARCHAR(14)) AS $$
BEGIN
    RETURN QUERY
    SELECT w.kd_sls, w.nm_sls, w.id_sls
    FROM wilayah w 
    WHERE w.kd_prov = p_kd_prov AND w.kd_kab = p_kd_kab AND w.kd_kec = p_kd_kec AND w.kd_desa = p_kd_desa
    ORDER BY w.nm_sls;
END;
$$ LANGUAGE plpgsql;

-- ========================================
-- CONTOH DATA DUMMY
-- ========================================

-- Data wilayah (dari Excel Anda)
INSERT INTO wilayah (id_sls, kd_prov, kd_kab, kd_kec, kd_desa, kd_sls, nm_prov, nm_kab, nm_kec, nm_desa, nm_sls) VALUES 
('73710100010001', '73', '71', '010', '001', '0001', 'Sulawesi Selatan', 'Parepare', 'Bacukiki', 'Lumpue', 'Lumpue I'),
('73710100010002', '73', '71', '010', '001', '0002', 'Sulawesi Selatan', 'Parepare', 'Bacukiki', 'Lumpue', 'Lumpue II'),
('73710100020001', '73', '71', '010', '002', '0001', 'Sulawesi Selatan', 'Parepare', 'Bacukiki', 'Bacukiki', 'Bacukiki I'),
('73710200010001', '73', '71', '020', '001', '0001', 'Sulawesi Selatan', 'Parepare', 'Ujung', 'Labukkang', 'Labukkang I'),
('73710200020001', '73', '71', '020', '002', '0001', 'Sulawesi Selatan', 'Parepare', 'Ujung', 'Ujung Bulu', 'Ujung Bulu I'),
('73710300010001', '73', '71', '030', '001', '0001', 'Sulawesi Selatan', 'Parepare', 'Soreang', 'Bukit Harapan', 'Bukit Harapan I')
ON CONFLICT (id_sls) DO NOTHING;

-- Data direktori (dengan kolom baru)
INSERT INTO direktori (
    id_sbr, nama_usaha, alamat, id_sls,
    kd_prov, kd_kab, kd_kec, kd_desa, kd_sls,
    keberadaan_usaha, kegiatan_usaha, skala_usaha, keterangan, nib,
    latitude, longitude, url_gambar, kode_pos, jenis_perusahaan,
    pemilik, nik_pemilik, nohp_pemilik, tenaga_kerja,
    nama_komersial_usaha, nomor_telepon, nomor_whatsapp, email, website, sumber_data,
    jenis_kepemilikan_usaha, bentuk_badan_hukum_usaha, 
    tahun_berdiri, jaringan_usaha, sektor_institusi
) VALUES 
(
    'SBR001', 'Toko Sembako Berkah', 'Jl. Merdeka No. 123', '73710100010001',
    '73', '71', '010', '001', '0001',
    1,
    '[{"kegiatan_usaha": "Perdagangan Eceran", "kategori": "Perdagangan", "kbli": "47111"}]'::jsonb,
    'mikro', 'tambahan', '1234567890123456',
    -4.0095, 119.6204, 'https://example.com/image1.jpg', '91131', 'UD',
    'Budi Santoso', '7371012345678901', '081234567890', 3,
    'Berkah Store', '0411-123456', '081234567890', 'berkah@example.com', 'https://berkahstore.com', 'BPS',
    2, 12, 2015, 1, 2
),
(
    'SBR002', 'Warung Makan Sederhana', 'Jl. Ahmad Yani No. 45', '73710200010001',
    '73', '71', '020', '001', '0001',
    1,
    '[{"kegiatan_usaha": "Penyediaan Makanan dan Minuman", "kategori": "Akomodasi dan Penyediaan Makan Minum", "kbli": "56101"}]'::jsonb,
    'mikro', 'tambahan', '2345678901234567',
    -4.0123, 119.6234, 'https://example.com/image2.jpg', '91132', 'Perorangan',
    'Siti Aminah', '7371023456789012', '082345678901', 2,
    'RM Sederhana', '0411-234567', '082345678901', 'sederhana@example.com', NULL, 'Lapangan',
    2, 12, 2018, 1, 2
)
ON CONFLICT (id_sbr) DO NOTHING;

-- ========================================
-- CONTOH QUERY UNTUK TESTING
-- ========================================

-- Melihat semua wilayah
-- SELECT * FROM wilayah ORDER BY id_sls;

-- Melihat direktori dengan nama wilayah
-- SELECT * FROM v_direktori_lengkap ORDER BY created_at DESC;

-- Mendapatkan dropdown provinsi
-- SELECT * FROM get_daftar_provinsi();

-- Mendapatkan dropdown kabupaten untuk Sulawesi Selatan
-- SELECT * FROM get_daftar_kabupaten('73');

-- Mencari berdasarkan nama usaha
-- SELECT * FROM v_direktori_lengkap WHERE to_tsvector('indonesian', nama_usaha) @@ to_tsquery('indonesian', 'toko');

-- Import dari Excel: INSERT INTO wilayah (id_sls, kd_prov, kd_kab, kd_kec, kd_desa, kd_sls, nm_prov, nm_kab, nm_kec, nm_desa, nm_sls) VALUES (...);