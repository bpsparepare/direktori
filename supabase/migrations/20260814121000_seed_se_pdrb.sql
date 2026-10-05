-- =====================================================================
-- SEED DATA: se2026_per_kategori
-- Mengisi data Sensus Ekonomi 2026 per kategori KBLI (A-T)
-- dari data yang diberikan.
-- Catatan: kategori kosong (row 1 = TOTAL keseluruhan dan row 2 =
-- tanpa kategori) disimpan dengan kode 'ALL' dan 'ZZZ' agar unik.
-- =====================================================================

insert into public.se2026_per_kategori
  (kategori, nama_kategori, jumlah_usaha, total_pendapatan_bln, rata2_pendapatan_bln, total_pengeluaran_bln, rata2_pengeluaran_bln)
values
  ('ALL',  'TOTAL Seluruh Kategori',             12864, null,                                              null,                                               null,                                               null),
  ('ZZZ',  'Tidak Diketahui / Tanpa Kategori',    169, 0,                                                 0,                                                  4000000,                                            1333333.3333333333),
  ('A',    'Pertanian, Kehutanan, Perikanan',    1246, 82850000,                                          3602173.913043478,                                  107070000,                                          4655217.391304348),
  ('B',    'Pertambangan dan Penggalian',           2, null,                                              null,                                               null,                                               null),
  ('C',    'Industri Pengolahan',                1278, 408291000,                                         4919168.674698795,                                  260306001,                                          3136216.879518072),
  ('D',    'Pengadaan Listrik dan Gas',            18, null,                                              null,                                               null,                                               null),
  ('E',    'Pengadaan Air, Pengelolaan Sampah',    16, null,                                              null,                                               null,                                               null),
  ('F',    'Konstruksi',                           43, 123000000,                                         41000000,                                           73740000,                                           24580000),
  ('G',    'Perdagangan Besar dan Eceran',       4364, 2846887999,                                        10390102.186131386,                                 2177112057,                                         7945664.44160584),
  ('H',    'Transportasi dan Pergudangan',        987, 335089000,                                          7284543.478260869,                                  179232999,                                          3896369.5434782607),
  ('I',    'Penyediaan Akomodasi dan Makan Min',1527, 2198378008,                                        10418853.118483413,                                 5972264940,                                         28304573.17535545),
  ('J',    'Informasi dan Komunikasi',             11, 1000000,                                           1000000,                                            100000,                                            100000),
  ('K',    'Jasa Keuangan dan Asuransi',           93, 57100000,                                           7137500,                                            32325000,                                           4040625),
  ('L',    'Jasa Real Estat',                      97, 53840000,                                           4894545.454545454,                                  37539000,                                           3412636.3636363638),
  ('M',    'Jasa Perusahaan',                     157, 38934000,                                           4866750,                                            7873000,                                            984125),
  ('N',    'Jasa Administrasi Pemerintah',         40, 20500000,                                           6833333.333333333,                                  10347000,                                           3449000),
  ('O',    'Jasa Pendidikan',                     146, 38415000,                                           4801875,                                            22045000,                                           2755625),
  ('Q',    'Jasa Kesehatan dan Kegiatan Sosial',  111, 70500000,                                           14100000,                                           24015000,                                           4803000),
  ('R',    'Jasa Kesenian, Hiburan, dan Rekreasi',52, 3700000,                                            1850000,                                            750000,                                             375000),
  ('S',    'Jasa Perorangan dan Jasa Lainnya',     37, 2100000,                                            1050000,                                            5360000,                                            2680000),
  ('T',    'Jasa Lainnya',                        679, 240900000,                                          6691666.666666667,                                  227135000,                                          6309305.555555556)
on conflict (kategori) do update set
  nama_kategori          = excluded.nama_kategori,
  jumlah_usaha           = excluded.jumlah_usaha,
  total_pendapatan_bln   = excluded.total_pendapatan_bln,
  rata2_pendapatan_bln   = excluded.rata2_pendapatan_bln,
  total_pengeluaran_bln  = excluded.total_pengeluaran_bln,
  rata2_pengeluaran_bln  = excluded.rata2_pengeluaran_bln,
  updated_at             = now();
