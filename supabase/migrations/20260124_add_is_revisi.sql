-- Add is_revisi column to groundcheck_list table
ALTER TABLE public.groundcheck_list 
ADD COLUMN IF NOT EXISTS is_revisi boolean DEFAULT false;

-- Update view if necessary (if view selects * it might be auto updated, but good to check)
-- Recreating views to ensure new column is included if they select specific columns
-- In this project, views like view_groundcheck_history select specific columns.

CREATE OR REPLACE VIEW view_groundcheck_history AS
SELECT 
  g.idsbr,
  g.nama_usaha,
  g.alamat_usaha,
  g.gcs_result,
  g.updated_at,
  g.user_id,
  g.kode_wilayah,
  g.status_perusahaan,
  g.skala_usaha,
  g.latitude,
  g.longitude,
  g.perusahaan_id,
  g.is_revisi
FROM groundcheck_list g
ORDER BY g.updated_at DESC;
