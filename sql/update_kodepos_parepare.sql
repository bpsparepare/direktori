-- Update kode pos kelurahan di Kota Parepare (Sulawesi Selatan)
-- Jalankan setelah import_all_geojson_data.sql selesai.
-- Pastikan kolom kode_pos sudah ada: ALTER TABLE wilayah ADD COLUMN IF NOT EXISTS kode_pos CHAR(5);

BEGIN;

-- BACUKIKI BARAT
UPDATE wilayah SET kode_pos = '91123' WHERE nm_kab = 'PAREPARE' AND nm_kec = 'BACUKIKI BARAT' AND nm_desa = 'LUMPUE';
UPDATE wilayah SET kode_pos = '91121' WHERE nm_kab = 'PAREPARE' AND nm_kec = 'BACUKIKI BARAT' AND nm_desa = 'KAMPUNG BARU';
UPDATE wilayah SET kode_pos = '91121' WHERE nm_kab = 'PAREPARE' AND nm_kec = 'BACUKIKI BARAT' AND nm_desa = 'SUMPANG MINANGAE';
UPDATE wilayah SET kode_pos = '91122' WHERE nm_kab = 'PAREPARE' AND nm_kec = 'BACUKIKI BARAT' AND nm_desa = 'CAPPAGALUNG';
UPDATE wilayah SET kode_pos = '91121' WHERE nm_kab = 'PAREPARE' AND nm_kec = 'BACUKIKI BARAT' AND nm_desa = 'BUMI HARAPAN';
UPDATE wilayah SET kode_pos = '91125' WHERE nm_kab = 'PAREPARE' AND nm_kec = 'BACUKIKI BARAT' AND nm_desa = 'TIRO SOMPE';

-- UJUNG
UPDATE wilayah SET kode_pos = '91111' WHERE nm_kab = 'PAREPARE' AND nm_kec = 'UJUNG' AND nm_desa = 'LABUKKANG';
UPDATE wilayah SET kode_pos = '91113' WHERE nm_kab = 'PAREPARE' AND nm_kec = 'UJUNG' AND nm_desa = 'UJUNG BULU';
UPDATE wilayah SET kode_pos = '91114' WHERE nm_kab = 'PAREPARE' AND nm_kec = 'UJUNG' AND nm_desa = 'UJUNG SABBANG';
UPDATE wilayah SET kode_pos = '91112' WHERE nm_kab = 'PAREPARE' AND nm_kec = 'UJUNG' AND nm_desa = 'LAPADDE';
UPDATE wilayah SET kode_pos = '91111' WHERE nm_kab = 'PAREPARE' AND nm_kec = 'UJUNG' AND nm_desa = 'MALLUSETASI';

-- SOREANG
UPDATE wilayah SET kode_pos = '91131' WHERE nm_kab = 'PAREPARE' AND nm_kec = 'SOREANG' AND nm_desa = 'BUKIT HARAPAN';
UPDATE wilayah SET kode_pos = '91131' WHERE nm_kab = 'PAREPARE' AND nm_kec = 'SOREANG' AND nm_desa = 'BUKIT INDAH';
UPDATE wilayah SET kode_pos = '91131' WHERE nm_kab = 'PAREPARE' AND nm_kec = 'SOREANG' AND nm_desa = 'KAMPUNG PISANG';
UPDATE wilayah SET kode_pos = '91131' WHERE nm_kab = 'PAREPARE' AND nm_kec = 'SOREANG' AND nm_desa = 'UJUNG BARU';
UPDATE wilayah SET kode_pos = '91131' WHERE nm_kab = 'PAREPARE' AND nm_kec = 'SOREANG' AND nm_desa = 'UJUNG LARE';
UPDATE wilayah SET kode_pos = '91132' WHERE nm_kab = 'PAREPARE' AND nm_kec = 'SOREANG' AND nm_desa = 'WATTANG SOREANG';
UPDATE wilayah SET kode_pos = '91133' WHERE nm_kab = 'PAREPARE' AND nm_kec = 'SOREANG' AND nm_desa = 'LAKESSI';

-- BACUKIKI
UPDATE wilayah SET kode_pos = '91121' WHERE nm_kab = 'PAREPARE' AND nm_kec = 'BACUKIKI' AND nm_desa = 'LEMOE';
UPDATE wilayah SET kode_pos = '91121' WHERE nm_kab = 'PAREPARE' AND nm_kec = 'BACUKIKI' AND nm_desa = 'WATANG BACUKIKI';
UPDATE wilayah SET kode_pos = '91125' WHERE nm_kab = 'PAREPARE' AND nm_kec = 'BACUKIKI' AND nm_desa = 'LOMPOE';
UPDATE wilayah SET kode_pos = '91121' WHERE nm_kab = 'PAREPARE' AND nm_kec = 'BACUKIKI' AND nm_desa = 'GALUNG MALOANG';

COMMIT;