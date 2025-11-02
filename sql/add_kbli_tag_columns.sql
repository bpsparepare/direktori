-- Add KBLI and Tag columns to direktori table
-- KBLI: exactly 5 digits
-- Tag: array of strings (can have multiple values)

-- Add the new columns
ALTER TABLE public.direktori 
ADD COLUMN IF NOT EXISTS kbli character(5) NULL,
ADD COLUMN IF NOT EXISTS tag text[] NULL DEFAULT '{}';

-- Add constraint to ensure KBLI is exactly 5 digits
ALTER TABLE public.direktori 
ADD CONSTRAINT direktori_kbli_check 
CHECK (kbli IS NULL OR (kbli ~ '^[0-9]{5}$'));

-- Add index for KBLI for better query performance
CREATE INDEX IF NOT EXISTS idx_direktori_kbli 
ON public.direktori USING btree (kbli) 
TABLESPACE pg_default;

-- Add GIN index for tag array for better search performance
CREATE INDEX IF NOT EXISTS idx_direktori_tag 
ON public.direktori USING gin (tag) 
TABLESPACE pg_default;

-- Add comments for documentation
COMMENT ON COLUMN public.direktori.kbli IS 'Kode KBLI (Klasifikasi Baku Lapangan Usaha Indonesia) - exactly 5 digits';
COMMENT ON COLUMN public.direktori.tag IS 'Array of tags/categories for the business - can have multiple values';