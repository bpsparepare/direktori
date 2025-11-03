-- =====================================================
-- SISTEM KONTRIBUSI DIREKTORI - DESAIN SEDERHANA
-- =====================================================
-- File: create_contribution_tables.sql
-- Deskripsi: Membuat tabel untuk sistem kontribusi sederhana
-- Tanggal: 2024
-- =====================================================

-- Tabel 1: direktori_user_contributions
-- Menyimpan semua kontribusi yang dilakukan pengguna
CREATE TABLE IF NOT EXISTS direktori_user_contributions (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    
    -- Informasi kontribusi
    action_type VARCHAR(20) NOT NULL CHECK (action_type IN ('add', 'edit', 'delete')),
    target_type VARCHAR(20) NOT NULL CHECK (target_type IN ('direktori', 'wilayah')),
    target_id TEXT, -- ID fleksibel: mendukung UUID (direktori.id) atau VARCHAR (wilayah.id_sls)
    
    -- Detail perubahan (JSON untuk fleksibilitas)
    changes JSONB, -- Menyimpan detail perubahan yang dilakukan
    
    -- Metadata
    points_earned INTEGER DEFAULT 0, -- Poin yang didapat dari kontribusi ini
    status VARCHAR(20) DEFAULT 'approved' CHECK (status IN ('pending', 'approved', 'rejected')),
    
    -- Informasi lokasi (opsional, untuk konteks geografis)
    latitude DECIMAL(10, 8),
    longitude DECIMAL(11, 8),
    
    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Tabel 2: direktori_user_stats
-- Menyimpan statistik dan level pengguna
CREATE TABLE IF NOT EXISTS direktori_user_stats (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID UNIQUE NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    
    -- Statistik kontribusi
    total_contributions INTEGER DEFAULT 0,
    total_points INTEGER DEFAULT 0,
    
    -- Breakdown berdasarkan aksi
    add_count INTEGER DEFAULT 0,
    edit_count INTEGER DEFAULT 0,
    delete_count INTEGER DEFAULT 0,
    
    -- Level dan ranking
    current_level INTEGER DEFAULT 1,
    level_progress INTEGER DEFAULT 0, -- Progress menuju level berikutnya (0-100)
    
    -- Streak dan aktivitas
    current_streak INTEGER DEFAULT 0, -- Hari berturut-turut berkontribusi
    longest_streak INTEGER DEFAULT 0,
    last_contribution_date DATE,
    
    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- =====================================================
-- INDEXES UNTUK PERFORMA
-- =====================================================

-- Index untuk direktori_user_contributions
CREATE INDEX IF NOT EXISTS idx_direktori_contributions_user_id ON direktori_user_contributions(user_id);
CREATE INDEX IF NOT EXISTS idx_direktori_contributions_action_type ON direktori_user_contributions(action_type);
CREATE INDEX IF NOT EXISTS idx_direktori_contributions_target_type ON direktori_user_contributions(target_type);
CREATE INDEX IF NOT EXISTS idx_direktori_contributions_created_at ON direktori_user_contributions(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_direktori_contributions_points ON direktori_user_contributions(points_earned DESC);

-- Index untuk direktori_user_stats
CREATE INDEX IF NOT EXISTS idx_direktori_stats_total_points ON direktori_user_stats(total_points DESC);
CREATE INDEX IF NOT EXISTS idx_direktori_stats_level ON direktori_user_stats(current_level DESC);
CREATE INDEX IF NOT EXISTS idx_direktori_stats_contributions ON direktori_user_stats(total_contributions DESC);

-- =====================================================
-- TRIGGERS UNTUK AUTO-UPDATE
-- =====================================================

-- Function untuk update timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Trigger untuk auto-update updated_at
CREATE TRIGGER update_direktori_contributions_updated_at 
    BEFORE UPDATE ON direktori_user_contributions 
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_direktori_stats_updated_at 
    BEFORE UPDATE ON direktori_user_stats 
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- =====================================================
-- FUNCTION UNTUK MENGHITUNG LEVEL
-- =====================================================

-- Function untuk menghitung level berdasarkan total poin
CREATE OR REPLACE FUNCTION calculate_user_level(total_points INTEGER)
RETURNS INTEGER AS $$
BEGIN
    -- Formula sederhana: Level = floor(sqrt(total_points / 100)) + 1
    -- Level 1: 0-99 poin
    -- Level 2: 100-399 poin  
    -- Level 3: 400-899 poin
    -- Level 4: 900-1599 poin
    -- dst...
    RETURN FLOOR(SQRT(total_points / 100.0)) + 1;
END;
$$ LANGUAGE plpgsql;

-- Function untuk menghitung progress level (0-100)
CREATE OR REPLACE FUNCTION calculate_level_progress(total_points INTEGER)
RETURNS INTEGER AS $$
DECLARE
    current_level INTEGER;
    points_for_current_level INTEGER;
    points_for_next_level INTEGER;
    progress INTEGER;
BEGIN
    current_level := calculate_user_level(total_points);
    
    -- Hitung poin minimum untuk level saat ini
    points_for_current_level := POWER(current_level - 1, 2) * 100;
    
    -- Hitung poin minimum untuk level berikutnya
    points_for_next_level := POWER(current_level, 2) * 100;
    
    -- Hitung progress (0-100)
    IF points_for_next_level = points_for_current_level THEN
        progress := 100;
    ELSE
        progress := ROUND(
            ((total_points - points_for_current_level)::FLOAT / 
             (points_for_next_level - points_for_current_level)::FLOAT) * 100
        );
    END IF;
    
    RETURN LEAST(100, GREATEST(0, progress));
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- FUNCTION UNTUK UPDATE STATISTIK USER
-- =====================================================

-- Function untuk update statistik user setelah kontribusi baru
CREATE OR REPLACE FUNCTION update_user_stats_after_contribution()
RETURNS TRIGGER AS $$
DECLARE
    new_total_points INTEGER;
    new_total_contributions INTEGER;
    new_level INTEGER;
    new_progress INTEGER;
BEGIN
    -- Hitung ulang statistik dari tabel contributions
    SELECT 
        COALESCE(SUM(points_earned), 0),
        COUNT(*)
    INTO new_total_points, new_total_contributions
    FROM direktori_user_contributions 
    WHERE user_id = NEW.user_id AND status = 'approved';
    
    -- Hitung level dan progress
    new_level := calculate_user_level(new_total_points);
    new_progress := calculate_level_progress(new_total_points);
    
    -- Update atau insert statistik user
    INSERT INTO direktori_user_stats (
        user_id, 
        total_points, 
        total_contributions,
        current_level,
        level_progress,
        add_count,
        edit_count,
        delete_count,
        last_contribution_date
    ) VALUES (
        NEW.user_id,
        new_total_points,
        new_total_contributions,
        new_level,
        new_progress,
        CASE WHEN NEW.action_type = 'add' THEN 1 ELSE 0 END,
        CASE WHEN NEW.action_type = 'edit' THEN 1 ELSE 0 END,
        CASE WHEN NEW.action_type = 'delete' THEN 1 ELSE 0 END,
        CURRENT_DATE
    )
    ON CONFLICT (user_id) DO UPDATE SET
        total_points = new_total_points,
        total_contributions = new_total_contributions,
        current_level = new_level,
        level_progress = new_progress,
        add_count = direktori_user_stats.add_count + 
            CASE WHEN NEW.action_type = 'add' THEN 1 ELSE 0 END,
        edit_count = direktori_user_stats.edit_count + 
            CASE WHEN NEW.action_type = 'edit' THEN 1 ELSE 0 END,
        delete_count = direktori_user_stats.delete_count + 
            CASE WHEN NEW.action_type = 'delete' THEN 1 ELSE 0 END,
        last_contribution_date = CURRENT_DATE,
        updated_at = NOW();
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger untuk auto-update statistik setelah kontribusi baru
CREATE TRIGGER update_stats_after_contribution
    AFTER INSERT ON direktori_user_contributions
    FOR EACH ROW EXECUTE FUNCTION update_user_stats_after_contribution();

-- =====================================================
-- COMPATIBILITAS/MIGRASI: UBAH TIPE KOLOM target_id MENJADI TEXT
-- =====================================================
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 
        FROM information_schema.columns 
        WHERE table_name='direktori_user_contributions' 
          AND column_name='target_id' 
          AND data_type IN ('bigint')
    ) THEN
        ALTER TABLE direktori_user_contributions
            ALTER COLUMN target_id TYPE TEXT USING target_id::text;
    END IF;
END;
$$;

-- =====================================================
-- SAMPLE DATA DAN TESTING
-- =====================================================

-- Contoh sistem poin sederhana:
-- ADD direktori baru: 10 poin
-- EDIT direktori: 5 poin  
-- DELETE direktori: 3 poin
-- ADD wilayah baru: 15 poin
-- EDIT wilayah: 8 poin
-- DELETE wilayah: 5 poin

-- Contoh query untuk insert kontribusi:
/*
INSERT INTO direktori_user_contributions (
    user_id, 
    action_type, 
    target_type, 
    target_id, 
    changes, 
    points_earned,
    latitude,
    longitude
) VALUES (
    'user-uuid-here',
    'add',
    'direktori',
    123,
    '{"nama_usaha": "Toko Baru", "alamat": "Jl. Contoh No. 1"}',
    10,
    -4.0543,
    119.6235
);
*/

-- Query untuk melihat leaderboard:
/*
SELECT 
    u.email,
    s.total_points,
    s.current_level,
    s.total_contributions,
    s.current_streak
FROM direktori_user_stats s
JOIN auth.users u ON s.user_id = u.id
ORDER BY s.total_points DESC
LIMIT 10;
*/