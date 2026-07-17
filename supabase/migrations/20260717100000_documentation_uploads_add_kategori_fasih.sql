-- Tambah kategori 'fasih' pada dokumentasi upload.
alter table public.documentation_uploads
  drop constraint if exists documentation_uploads_kategori_check;

alter table public.documentation_uploads
  add constraint documentation_uploads_kategori_check check (
    kategori in (
      'koordinasi',
      'pendataan',
      'pengawasan',
      'pertemuan',
      'lainnya',
      'bukti paket data',
      'fasih'
    )
  );
