-- CREATE OR REPLACE FUNCTION tidak mengganti fungsi lama kalau daftar
-- parameter berubah (p_kategori -> p_kategori_besar/p_kategori_kode) --
-- Postgres membuat OVERLOAD baru, bukan replace. Akibatnya PostgREST bingung
-- pilih signature mana (PGRST203: Multiple Choices). Drop signature lama
-- secara eksplisit.

drop function if exists public.get_anomali_gabungan(
  text, text, text, text, text, integer, integer
);
