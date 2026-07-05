-- Perbaikan PGRST203 (Multiple Choices) pada get_assignment_places_for_current_user.
--
-- Database masih menyimpan overload lama dengan tipe parameter (text, text) di
-- samping versi yang benar (text, timestamp with time zone). PostgREST mengirim
-- p_modified_after sebagai string JSON sehingga cocok ke keduanya dan gagal
-- memilih kandidat. Migrasi sebelumnya hanya men-drop overload (text, timestamptz),
-- jadi versi (text, text) tidak pernah ikut terhapus. Drop di sini.

drop function if exists public.get_assignment_places_for_current_user(text, text);
