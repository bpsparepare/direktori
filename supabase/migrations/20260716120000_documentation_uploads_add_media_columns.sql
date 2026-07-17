-- Tambah kolom media agar thumbnail & metadata file ikut tersinkron ke semua
-- perangkat (bukan hanya cache lokal perangkat asal upload).
alter table public.documentation_uploads
  add column if not exists preview_url   text null,
  add column if not exists drive_file_id text null,
  add column if not exists file_size     bigint null;
