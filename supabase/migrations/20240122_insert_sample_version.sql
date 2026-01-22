-- Insert versi 1.1.4 (Build 6) ke database
-- Jalankan ini SETELAH Anda merilis aplikasi versi 1.1.4 ke server/store
INSERT INTO public.app_versions (
    version, 
    build_number, 
    force_update, 
    download_url, 
    android_url, 
    windows_url, 
    release_notes
) VALUES (
    '1.1.4', -- Version Name (harus > versi user saat ini agar terdeteksi update)
    6,       -- Build Number (harus > build number user saat ini)
    true,    -- Force Update: true (Wajib), false (Boleh nanti)
    'https://direktori.parepare.stat7300.net/', -- Link Web Default
    'https://drive.google.com/drive/folders/1FKERJht6MnOv3Fq-Ce0JWfWex6KH8DSL', -- Link Android
    'https://drive.google.com/drive/folders/1EzHo4luaR0-65aH8cFo00SEYGP6CEnAK', -- Link Windows
    'Perbaikan bug dan peningkatan performa.' -- Catatan rilis
);
