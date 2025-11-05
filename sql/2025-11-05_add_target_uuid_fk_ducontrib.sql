-- Migration: Add target_uuid column and FK to direktori.id (uuid)
-- Rationale:
--   - Kolom `target_id` bertipe BIGINT tidak bisa direlasikan ke `direktori.id` (uuid)
--   - Tambahkan `target_uuid` untuk referensi yang konsisten ke direktori.id
--   - Tetap biarkan `target_id` untuk kasus target lain yang numerik (jika ada)

-- 1) Tambah kolom target_uuid (uuid)
ALTER TABLE public.direktori_user_contributions
  ADD COLUMN IF NOT EXISTS target_uuid uuid NULL;

-- 2) Index untuk mempercepat lookup
CREATE INDEX IF NOT EXISTS idx_ducontrib_target_uuid
  ON public.direktori_user_contributions (target_uuid);

-- 3) Tambah FK ke direktori(id) dengan ON DELETE SET NULL, aman untuk data lama
ALTER TABLE public.direktori_user_contributions
  ADD CONSTRAINT fk_ducontrib_target_uuid_direktori
  FOREIGN KEY (target_uuid)
  REFERENCES public.direktori (id)
  ON UPDATE CASCADE
  ON DELETE SET NULL
  NOT VALID;

-- 4) (Opsional) Backfill dari changes->>'target_uuid' jika ada dan valid
--    Baris di bawah ini akan mengisi target_uuid dari payload changes
--    hanya jika nilai tersebut ada di tabel direktori.
UPDATE public.direktori_user_contributions AS duc
SET target_uuid = (duc.changes->>'target_uuid')::uuid
FROM public.direktori AS d
WHERE duc.target_uuid IS NULL
  AND duc.changes ? 'target_uuid'
  AND d.id = (duc.changes->>'target_uuid')::uuid;

-- 5) (Opsional) Validasi FK setelah data dibersihkan
-- SELECT COUNT(*) AS invalid_fk
-- FROM public.direktori_user_contributions AS duc
-- LEFT JOIN public.direktori AS d ON d.id = duc.target_uuid
-- WHERE duc.target_uuid IS NOT NULL AND d.id IS NULL;
-- ALTER TABLE public.direktori_user_contributions
--   VALIDATE CONSTRAINT fk_ducontrib_target_uuid_direktori;