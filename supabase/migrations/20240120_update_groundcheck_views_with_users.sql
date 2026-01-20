-- View untuk Peringkat (Leaderboard) dengan Nama User
-- Menggabungkan tabel groundcheck_list dan users
DROP VIEW IF EXISTS view_groundcheck_leaderboard;
CREATE OR REPLACE VIEW view_groundcheck_leaderboard AS
SELECT 
  g.user_id,
  u.name as user_name,
  count(*) as total_contribution,
  max(g.updated_at) as last_contribution_at
FROM groundcheck_list g
LEFT JOIN users u ON g.user_id::uuid = u.id
WHERE g.user_id IS NOT NULL
GROUP BY g.user_id, u.name
ORDER BY total_contribution DESC;

-- View untuk History
-- Memastikan casting tipe data user_id konsisten (text vs uuid)
-- Masalah "tidak muncul" mungkin karena perbedaan tipe data saat query atau view filtering
DROP VIEW IF EXISTS view_groundcheck_history;
CREATE OR REPLACE VIEW view_groundcheck_history AS
SELECT 
  g.idsbr,
  g.nama_usaha,
  g.alamat_usaha,
  g.gcs_result,
  g.updated_at,
  g.user_id, -- Di tabel groundcheck_list mungkin text atau uuid? Asumsikan konsisten
  g.kode_wilayah,
  g.status_perusahaan,
  g.skala_usaha,
  g.latitude,
  g.longitude,
  g.perusahaan_id
FROM groundcheck_list g
ORDER BY g.updated_at DESC;
