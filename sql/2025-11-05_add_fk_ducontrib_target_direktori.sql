-- Migration: Add FK on direktori_user_contributions.target_id -> direktori.id
-- Purpose:
--   - Ensure each contribution references a valid directory when provided
--   - Keep contributions history even if a directory is deleted (SET NULL)
-- Safety:
--   - Uses NOT VALID to avoid failing if historical data is not yet consistent
--   - You can validate the constraint after cleaning invalid rows

-- 1) Create index to speed up lookups by target_id
CREATE INDEX IF NOT EXISTS idx_ducontrib_target_id
  ON direktori_user_contributions (target_id);

-- 2) Add foreign key (not validated yet)
ALTER TABLE direktori_user_contributions
  ADD CONSTRAINT fk_ducontrib_target_direktori
  FOREIGN KEY (target_id)
  REFERENCES direktori (id)
  ON UPDATE CASCADE
  ON DELETE SET NULL
  NOT VALID;

-- 3) (Optional) Check invalid rows before validation
--    Run this SELECT to see how many rows have a non-null target_id
--    that does not exist in direktori:
--
--    SELECT COUNT(*) AS invalid_fk
--    FROM direktori_user_contributions duc
--    LEFT JOIN direktori d ON d.id = duc.target_id
--    WHERE duc.target_id IS NOT NULL AND d.id IS NULL;
--
-- 4) (Optional) Validate the FK once invalid rows are fixed (uncomment to run):
-- ALTER TABLE direktori_user_contributions
--   VALIDATE CONSTRAINT fk_ducontrib_target_direktori;