import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'revisit_translok_excel_service.dart';

/// Isian SPD yang sama untuk semua lembar.
class RevisitSpdPengaturan {
  final String nomor;
  final String ppkNama;
  final String ppkNip;
  final String kepalaNama;
  final String kepalaNip;

  const RevisitSpdPengaturan({
    required this.nomor,
    required this.ppkNama,
    required this.ppkNip,
    required this.kepalaNama,
    required this.kepalaNip,
  });
}

/// SPD (Surat Perjalanan Dinas) translok revisit SE2026, mengikuti format SPD
/// BPS Kota Parepare: 2 halaman per perjalanan (satu baris List Harian =
/// satu petugas, satu hari, satu kecamatan tujuan).
class RevisitSpdPdfService {
  static const String instansi = 'Badan Pusat Statistik Parepare';
  static const String maksud = 'Transport petugas revisit Sensus Ekonomi 2026';
  static const String asal = 'Kecamatan Bacukiki Barat';

  static const Map<String, String> _namaKecamatan = {
    '010': 'Bacukiki',
    '011': 'Bacukiki Barat',
    '020': 'Ujung',
    '030': 'Soreang',
  };

  static const List<String> _bulan = [
    'Januari',
    'Februari',
    'Maret',
    'April',
    'Mei',
    'Juni',
    'Juli',
    'Agustus',
    'September',
    'Oktober',
    'November',
    'Desember',
  ];

  /// "Kecamatan Soreang" dari kode tujuan "7372030" (atau "030").
  static String namaTujuan(String kode) {
    final kec = kode.length >= 3 ? kode.substring(kode.length - 3) : kode;
    return 'Kecamatan ${_namaKecamatan[kec] ?? kec}';
  }

  /// "08 Mei 2026" dari "2026-05-08" atau DateTime.
  static String tanggal(Object t) {
    final d = t is DateTime ? t : DateTime.parse(t.toString());
    return '${d.day.toString().padLeft(2, '0')} ${_bulan[d.month - 1]} ${d.year}';
  }

  /// Nomor SPD ke-[i] (mulai 0): angka di depan [awal] menjadi nomor urut
  /// pertama lalu bertambah per SPD dengan lebar digit yang sama, mis.
  /// "011/…/2026" → "011/…", "012/…", … Tanpa angka di depan: tetap.
  static String nomorKe(String awal, int i) {
    final m = RegExp(r'^(\d+)(.*)$', dotAll: true).firstMatch(awal.trim());
    if (m == null) return awal;
    final digit = m.group(1)!;
    final urut = (int.parse(digit) + i).toString().padLeft(digit.length, '0');
    return '$urut${m.group(2)}';
  }

  /// Nomor dipatahkan setelah "TRANSLOK-" seperti contoh SPD:
  /// "…/TRANSLOK-" di baris pertama, "2902/09/2026" di baris kedua.
  static List<String> barisNomor(String nomor) {
    const pemisah = 'TRANSLOK-';
    final i = nomor.indexOf(pemisah);
    if (i < 0 || i + pemisah.length >= nomor.length) return [nomor];
    final j = i + pemisah.length;
    return [nomor.substring(0, j), nomor.substring(j)];
  }

  /// Ganti bagian "/MM/YYYY" di akhir nomor dengan bulan & tahun perjalanan
  /// [tanggalPerjalanan] ("yyyy-mm-dd"), mis. "…/04/2026" → "…/09/2026".
  static String nomorBulan(String nomor, String tanggalPerjalanan) {
    final t = DateTime.tryParse(tanggalPerjalanan);
    if (t == null) return nomor;
    return nomor.replaceFirstMapped(
      RegExp(r'/\d{1,2}/\d{4}$'),
      (_) => '/${t.month.toString().padLeft(2, '0')}/${t.year}',
    );
  }

  /// Buat PDF di isolate terpisah lalu simpan; kembalikan path file.
  Future<String> simpan(
    List<RevisitTranslokBaris> baris,
    RevisitSpdPengaturan pengaturan, {
    required String periode,
    bool satuHalaman = false,
  }) async {
    final bytes = await compute(_buatPdfIsolate, (
      baris,
      pengaturan,
      satuHalaman,
    ));
    final dir = await getTemporaryDirectory();
    final aman = periode.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
    final jenis = satuHalaman ? 'spd1' : 'spd';
    final path = '${dir.path}/${jenis}_revisit_$aman.pdf';
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }

  static Future<Uint8List> _buatPdfIsolate(
    (List<RevisitTranslokBaris>, RevisitSpdPengaturan, bool) data,
  ) => buatPdf(data.$1, data.$2, satuHalaman: data.$3);

  /// Dokumen PDF: 2 halaman per baris, atau 1 halaman per baris bila
  /// [satuHalaman] (hanya lembar berangkat/tiba + nomor di kanan atas).
  static Future<Uint8List> buatPdf(
    List<RevisitTranslokBaris> baris,
    RevisitSpdPengaturan p, {
    bool satuHalaman = false,
  }) {
    final doc = pw.Document(
      theme: pw.ThemeData.withFont(
        base: pw.Font.times(),
        bold: pw.Font.timesBold(),
      ),
    );
    for (final (i, b) in baris.indexed) {
      final nomor = nomorBulan(nomorKe(p.nomor, i), b.berangkat);
      if (satuHalaman) {
        doc.addPage(
          _halaman(
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _blokNomor(nomor),
                pw.SizedBox(height: 28),
                _halaman2(b, p),
              ],
            ),
          ),
        );
      } else {
        doc
          ..addPage(_halaman(_halaman1(b, p, nomor)))
          ..addPage(_halaman(_halaman2(b, p)));
      }
    }
    return doc.save();
  }

  // ── Tata letak ────────────────────────────────────────────────────────────

  static const double _font = 11;
  static const double _baris = 14.5;
  static const double _lebarKiri = 271;
  static const _tipis = pw.BorderSide(width: 0.7);
  static const _tebal = pw.BorderSide(width: 1.4);
  static const _gaya = pw.TextStyle(fontSize: _font);
  static final _nama = pw.TextStyle(
    fontSize: _font,
    fontWeight: pw.FontWeight.bold,
    decoration: pw.TextDecoration.underline,
  );

  static pw.Page _halaman(pw.Widget isi) => pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(28, 30, 28, 30),
    build: (_) => isi,
  );

  static pw.Widget _t(String s, {pw.TextAlign? align, pw.TextStyle? gaya}) =>
      pw.Text(s, style: gaya ?? _gaya, textAlign: align);

  /// Satu baris teks setinggi [n] baris (agar kiri-kanan sejajar).
  static pw.Widget _slot(pw.Widget isi, [int n = 1]) => pw.SizedBox(
    height: _baris * n,
    child: pw.Align(alignment: pw.Alignment.topLeft, child: isi),
  );

  /// Label bernomor di kolom kiri: "1." lalu teks.
  static pw.Widget _label(String nomor, String teks) => pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.SizedBox(width: 17, child: _t(nomor)),
      pw.Expanded(child: _t(teks)),
    ],
  );

  /// Sub-label "a." di bawah nomor.
  static pw.Widget _sub(String huruf, String teks) => pw.Padding(
    padding: const pw.EdgeInsets.only(left: 17),
    child: pw.Row(
      children: [
        pw.SizedBox(width: 16, child: _t(huruf)),
        pw.Expanded(child: _t(teks)),
      ],
    ),
  );

  static pw.TableRow _item(List<pw.Widget> kiri, List<pw.Widget> kanan) =>
      pw.TableRow(
        children: [
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: kiri,
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.fromLTRB(2, 1.5, 0, 1.5),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: kanan,
            ),
          ),
        ],
      );

  /// Kode + uraian anggaran (2 baris).
  static pw.Widget _anggaran(String kode, String uraian) => _slot(
    pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(width: 52, child: _t(kode)),
        pw.Expanded(child: _t(uraian)),
      ],
    ),
    2,
  );

  static pw.Widget _labelAnggaran(String judul, String sub) => _slot(
    pw.Row(
      children: [
        pw.Expanded(child: judul.isEmpty ? pw.SizedBox() : _label('9.', judul)),
        pw.SizedBox(width: 56, child: _t(sub)),
      ],
    ),
    2,
  );

  /// Nomor & lembar di pojok kanan atas.
  static pw.Widget _blokNomor(String nomor) => pw.Padding(
    padding: const pw.EdgeInsets.only(left: 283),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(width: 38, child: _t('Nomor')),
            _t(': '),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [for (final b in barisNomor(nomor)) _t(b)],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Row(
          children: [
            pw.SizedBox(width: 38, child: _t('Lembar')),
            _t(':'),
          ],
        ),
      ],
    ),
  );

  static pw.Widget _halaman1(
    RevisitTranslokBaris b,
    RevisitSpdPengaturan p,
    String nomor,
  ) {
    final tgl = tanggal(b.berangkat);
    final tujuan = namaTujuan(b.tujuan);
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _blokNomor(nomor),
        pw.SizedBox(height: 10),
        _t(instansi),
        pw.SizedBox(height: 8),
        pw.Table(
          border: const pw.TableBorder(
            top: _tebal,
            bottom: _tebal,
            horizontalInside: _tipis,
            verticalInside: _tipis,
          ),
          columnWidths: const {
            0: pw.FixedColumnWidth(_lebarKiri),
            1: pw.FlexColumnWidth(),
          },
          children: [
            _item([_label('1.', 'Pejabat Pembuat Komitmen')], [_t(p.ppkNama)]),
            _item(
              [_label('2.', 'Nama pegawai yang melaksanakan perjalanan dinas')],
              [_t(b.nama)],
            ),
            _item(
              [
                _slot(_label('3.', 'a.  Pangkat dan golongan')),
                _slot(_sub('b.', 'Jabatan/ instansi')),
                _slot(_sub('c.', 'Tingkat Biaya Perjalanan Dinas')),
              ],
              [_slot(_t('-')), _slot(_t('-')), _slot(_t(''))],
            ),
            _item([_label('4.', 'Maksud perjalanan dinas')], [_t(maksud)]),
            _item(
              [_label('5.', 'Alat Angkutan yang dipergunakan')],
              [_t('Kendaraan Umum')],
            ),
            _item(
              [
                _slot(_label('6.', 'a.  Tempat keberangkatan')),
                _slot(_sub('b.', 'Tempat tujuan')),
              ],
              [_slot(_t(asal)), _slot(_t(tujuan))],
            ),
            _item(
              [
                _slot(_label('7.', 'a.  Lamanya perjalanan Dinas')),
                _slot(_sub('b.', 'Tanggal Berangkat')),
                _slot(
                  _sub('c.', 'Tanggal harus kembali/ tiba ditempat baru *)'),
                ),
              ],
              [_slot(_t('1 hari')), _slot(_t(tgl)), _slot(_t(tgl))],
            ),
            // 8. Pengikut: kolom kanan dibagi Umur | Hubungan keluarga.
            pw.TableRow(
              children: [
                pw.SizedBox(
                  height: _baris * 2.6,
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Expanded(child: _label('8.', 'Pengikut :')),
                      pw.SizedBox(width: 130, child: _t('Nama')),
                    ],
                  ),
                ),
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Container(
                      width: 52,
                      height: _baris * 2.6,
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(right: _tipis),
                      ),
                      child: _t('Umur', align: pw.TextAlign.center),
                    ),
                    pw.Expanded(
                      child: _t(
                        'Hubungan keluarga/keterangan',
                        align: pw.TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            _item(
              [
                _labelAnggaran('Pembebanan anggaran', 'Program'),
                _labelAnggaran('', 'Kegiatan'),
                _labelAnggaran('', 'Komponen'),
                _slot(_sub('a.', 'Instansi')),
                _slot(_sub('b.', 'Mata anggaran')),
              ],
              [
                _anggaran(
                  'GG',
                  'Program Penyediaan dan Pelayanan Informasi Statistik',
                ),
                _anggaran(
                  '2902',
                  'Penyediaan dan Pengembangan Statistik Distribusi',
                ),
                _anggaran(
                  '005',
                  'Dukungan Penyelenggaraan Tugas dan Fungsi Unit',
                ),
                _slot(_t(instansi)),
                _slot(_t('')),
              ],
            ),
            _item([_label('10.', 'Keterangan lain-lain')], [_t('')]),
          ],
        ),
        pw.SizedBox(height: 14),
        // Dikeluarkan & tanda tangan PPK di kanan.
        pw.Padding(
          padding: const pw.EdgeInsets.only(left: 302),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                children: [
                  pw.SizedBox(width: 80, child: _t('Dikeluarkan di')),
                  _t(': Parepare'),
                ],
              ),
              pw.SizedBox(height: 4),
              pw.Row(
                children: [
                  pw.SizedBox(width: 80, child: _t('Pada Tanggal')),
                  // Dikeluarkan pada tanggal perjalanan (translok) itu sendiri.
                  _t(': $tgl'),
                ],
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 18),
        pw.Padding(
          padding: const pw.EdgeInsets.only(left: 290),
          child: pw.Column(
            children: [
              _t('PEJABAT PEMBUAT KOMITMEN', align: pw.TextAlign.center),
              pw.SizedBox(height: 4),
              _t(
                'Program Penyediaan dan Pelayanan Informasi\nStatistik',
                align: pw.TextAlign.center,
              ),
              pw.SizedBox(height: 52),
              _t(p.ppkNama, gaya: _nama, align: pw.TextAlign.center),
              pw.SizedBox(height: 3),
              _t('NIP. ${p.ppkNip}', align: pw.TextAlign.center),
            ],
          ),
        ),
        pw.SizedBox(height: 12),
        _t('Tembusan disampaikan kepada :'),
        _t('1.'),
        _t('2.'),
      ],
    );
  }

  /// Label : nilai (halaman 2).
  static pw.Widget _kv(String label, String nilai, {String? lanjut}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 3),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(width: 72, child: _t(label)),
            pw.SizedBox(width: 26, child: _t(':')),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [_t(nilai), if (lanjut != null) _t(lanjut)],
              ),
            ),
          ],
        ),
      );

  static pw.Widget _ttd(String jabatan, String nama, String nip) => pw.Column(
    children: [
      _t(jabatan, align: pw.TextAlign.center),
      pw.SizedBox(height: 46),
      _t(nama, gaya: _nama, align: pw.TextAlign.center),
      pw.SizedBox(height: 2),
      _t('Nip. $nip', align: pw.TextAlign.center),
    ],
  );

  static pw.Widget _sel(List<pw.Widget> isi, {double minTinggi = 0}) =>
      pw.Container(
        constraints: pw.BoxConstraints(minHeight: minTinggi),
        padding: const pw.EdgeInsets.fromLTRB(2, 2, 2, 2),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: isi,
        ),
      );

  static pw.Widget _halaman2(RevisitTranslokBaris b, RevisitSpdPengaturan p) {
    final tgl = tanggal(b.berangkat);
    final tujuan = namaTujuan(b.tujuan);
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Table(
          border: const pw.TableBorder(
            horizontalInside: _tipis,
            verticalInside: _tebal,
            bottom: _tipis,
          ),
          columnWidths: const {
            0: pw.FixedColumnWidth(_lebarKiri),
            1: pw.FlexColumnWidth(),
          },
          children: [
            pw.TableRow(
              children: [
                pw.SizedBox(),
                _sel([
                  _kv('Berangkat dari', asal, lanjut: '(Tempat Kedudukan)'),
                  _kv('Pada Tanggal', tgl),
                  _kv('Ke', tujuan),
                  pw.SizedBox(height: 2),
                  pw.Center(
                    child: _ttd(
                      'Kepala BPS Kota Parepare',
                      p.kepalaNama,
                      p.kepalaNip,
                    ),
                  ),
                ]),
              ],
            ),
            pw.TableRow(
              children: [
                _sel([
                  _kv('Tiba di', tujuan),
                  _kv('Pada Tanggal', tgl),
                ], minTinggi: 106),
                _sel([
                  _kv('Berangkat dari', tujuan),
                  _kv('Ke', asal),
                  _kv('Pada Tanggal', tgl),
                ], minTinggi: 106),
              ],
            ),
            pw.TableRow(
              children: [
                _sel([
                  _kv('Tiba di', asal, lanjut: '(Tempat Kedudukan)'),
                  _kv('Pada Tanggal', tgl),
                  pw.SizedBox(height: 14),
                  pw.Center(
                    child: _ttd(
                      'Pejabat Pembuat Komitmen',
                      p.ppkNama,
                      p.ppkNip,
                    ),
                  ),
                ]),
                _sel([
                  _t(
                    'Telah diperiksa dengan keterangan bahwa perjalanan '
                    'tersebut atas perintahnya dan semata-mata untuk '
                    'kepentingan jabatan dalam waktu yang sesingkat '
                    'singkatnya',
                  ),
                  pw.SizedBox(height: 6),
                  pw.Center(
                    child: _ttd(
                      'Pejabat Pembuat Komitmen',
                      p.ppkNama,
                      p.ppkNip,
                    ),
                  ),
                ]),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 4),
        _t('CATATAN LAIN - LAIN'),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(width: 92, child: _t('PERHATIAN')),
            pw.SizedBox(width: 26, child: _t(':')),
            pw.Expanded(
              child: _t(
                'Pejabat yang berwenang menerbitkan SPD pegawai yang '
                'melakukan perjalanan dinas para pejabat yang mengesahkan '
                'tanggal berangkat/tiba serta bendaharawan bertanggung jawab '
                'berdasarkan peraturan-peraturan keuangan Negara apabila '
                'Negara menderita rugi akibat kesalahan, kelalaian dan '
                'kealpaannya.',
              ),
            ),
          ],
        ),
      ],
    );
  }
}
