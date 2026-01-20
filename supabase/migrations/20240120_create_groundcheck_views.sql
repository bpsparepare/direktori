-- View untuk Peringkat (Leaderboard)
CREATE OR REPLACE VIEW view_groundcheck_leaderboard AS
SELECT 
  user_id,
  count(*) as total_contribution,
  max(updated_at) as last_contribution_at
FROM groundcheck_list
WHERE user_id IS NOT NULL
GROUP BY user_id
ORDER BY total_contribution DESC;

-- View untuk History (Opsional)
CREATE OR REPLACE VIEW view_groundcheck_history AS
SELECT 
  idsbr,
  nama_usaha,
  alamat_usaha,
  gcs_result,
  updated_at,
  user_id,
  kode_wilayah,
  status_perusahaan,
  skala_usaha,
  latitude,
  longitude,
  perusahaan_id
FROM groundcheck_list
ORDER BY updated_at DESC;

-- Index rekomendasi
CREATE INDEX IF NOT EXISTS idx_groundcheck_user_id ON groundcheck_list(user_id);
CREATE INDEX IF NOT EXISTS idx_groundcheck_updated_at ON groundcheck_list(updated_at);
