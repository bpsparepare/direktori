import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/revisit_models.dart';
import 'revisit_laporan_docx.dart';

/// "Laporan Perjalanan Dinas" revisit sebagai PDF lokal, isi & susunannya
/// sama dengan [RevisitLaporanDocx]. Dipakai bila unggah ke Google Docs
/// tidak bisa (mis. token Drive bermasalah): tidak perlu Drive sama sekali
/// selain untuk memuat foto.
class RevisitLaporanPdf {
  // A4, margin 43,2 pt (sama dengan DOCX).
  static const double _margin = 43.2;
  static const double _font = 11;
  static const double _spasi15 = 5; // jarak antarbaris setara spasi 1,5
  static const double _pad = 5.4;
  static const _garis = pw.BorderSide(width: 1);

  static const double _lebarFotoPt = 287.5;
  static const double _lebarFotoBerdampingPt = 236;

  static Future<Uint8List> build({
    required List<RevisitLaporanHalaman> halaman,
    required Map<String, RevisitDocxFoto> foto,
    required RevisitPejabatMengetahui mengetahui,
    Map<String, RevisitPejabat> pejabat = const {},
  }) {
    final doc = pw.Document(
      theme: pw.ThemeData.withFont(
        base: pw.Font.helvetica(),
        bold: pw.Font.helveticaBold(),
      ),
    );
    if (halaman.isEmpty) {
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (_) => _t('Tidak ada laporan pada periode ini.'),
        ),
      );
    }
    // Satu MultiPage per laporan: tiap laporan mulai di halaman baru.
    for (final h in halaman) {
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(_margin),
          build: (_) => _laporan(h, foto, mengetahui, pejabat),
        ),
      );
    }
    return doc.save();
  }

  static List<pw.Widget> _laporan(
    RevisitLaporanHalaman h,
    Map<String, RevisitDocxFoto> foto,
    RevisitPejabatMengetahui mengetahui,
    Map<String, RevisitPejabat> pejabat,
  ) {
    final tgl = RevisitLaporanDocx.tanggalTeks(h.tanggal);
    final lokasi = RevisitLaporanDocx.lokasi(h.laporan);
    final hari = h.hariKe > 0 ? ' hari ke-${h.hariKe}' : '';
    final (pembuka, butirHasil) = RevisitLaporanDocx.kalimatHasil(h.laporan);
    final submit = h.laporan.fold<int>(
      0,
      (s, l) => s + RevisitLaporanDocx.submitDianggap(l),
    );

    // Foto siap tanam & yang gagal dimuat.
    final siap = <RevisitDocxFoto>[];
    final gagal = <String>[];
    for (final l in h.laporan) {
      for (final f in l.foto) {
        final data = foto[f.driveFileId];
        if (data == null) {
          gagal.add(f.namaFile);
        } else {
          siap.add(data);
        }
      }
    }
    final lebarFoto = siap.length == 1 ? _lebarFotoPt : _lebarFotoBerdampingPt;

    final daftarPejabat = RevisitLaporanDocx.pejabatHalaman(h, pejabat);
    final adaNip = mengetahui.nip.trim().isNotEmpty;

    final cd = <pw.Widget>[
      _kotak(
        pw.Center(child: _t('C. PEJABAT DAN TEMPAT YANG DIKUNJUNGI')),
        28.8,
        atas: true,
        tengah: true,
      ),
      _kotak(
        _kolom([
          if (daftarPejabat.isEmpty) ...[
            _isianVisum('Nama'),
            _isianVisum('Jabatan'),
          ] else
            for (final p in daftarPejabat) ...[
              _isianVisum('Nama', p.nama),
              _isianVisum('Jabatan', p.jabatan),
            ],
        ]),
        50,
      ),
      _kotak(pw.Center(child: _t('D. LEGALITAS')), 28.8, tengah: true),
      pw.Table(
        border: const pw.TableBorder(
          left: _garis,
          right: _garis,
          bottom: _garis,
          horizontalInside: _garis,
          verticalInside: _garis,
        ),
        columnWidths: const {
          0: pw.FlexColumnWidth(5114),
          1: pw.FlexColumnWidth(4914),
        },
        children: [
          pw.TableRow(
            verticalAlignment: pw.TableCellVerticalAlignment.middle,
            children: [
              _sel(
                _kolom([
                  _t('Mengetahui,'),
                  _t(mengetahui.jabatan),
                ], tengah: true),
                37,
                tengah: true,
              ),
              _sel(_t('PELAKSANA TUGAS'), 37, tengah: true),
            ],
          ),
          pw.TableRow(
            verticalAlignment: pw.TableCellVerticalAlignment.bottom,
            children: [
              _sel(
                _kolom([
                  _t(mengetahui.nama, garisBawah: true),
                  if (adaNip) _t('NIP. ${mengetahui.nip.trim()}'),
                ], tengah: true),
                85,
                bawah: true,
              ),
              _sel(
                _kolom([
                  _t(h.petugasNama, garisBawah: true),
                  if (adaNip) _t(''),
                ], tengah: true),
                85,
                bawah: true,
              ),
            ],
          ),
        ],
      ),
    ];

    return [
      pw.Center(child: _t('LAPORAN PERJALANAN DINAS')),
      pw.SizedBox(height: 2),

      // ── Tabel A: Data umum ─────────────────────────────────────────────
      _kotak(
        pw.Center(child: _t('A. DATA UMUM')),
        21.6,
        atas: true,
        tengah: true,
      ),
      pw.Table(
        border: const pw.TableBorder(
          bottom: _garis,
          left: _garis,
          right: _garis,
          horizontalInside: _garis,
          verticalInside: _garis,
        ),
        columnWidths: const {
          0: pw.FlexColumnWidth(2122),
          1: pw.FlexColumnWidth(2982),
          2: pw.FlexColumnWidth(2534),
          3: pw.FlexColumnWidth(2530),
        },
        defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
        children: [
          _barisA(
            '1. Nama Pelaksana',
            h.petugasNama,
            '4. Jadwal Pelaksanaan',
            tgl,
            49.9,
          ),
          _barisA(
            '2. Kegiatan',
            RevisitLaporanDocx.kegiatan,
            '5. Program yang membiayai',
            RevisitLaporanDocx.program,
            80.5,
          ),
          _barisA(
            '3. Tujuan',
            RevisitLaporanDocx.tujuan,
            '6. Komponen',
            RevisitLaporanDocx.komponen,
            82.2,
          ),
        ],
      ),
      pw.SizedBox(height: 14),

      // ── Tabel B: Uraian pekerjaan ──────────────────────────────────────
      _kotak(
        pw.Center(child: _t('B. URAIAN PEKERJAAN (RINGKASAN HASIL)')),
        28.8,
        atas: true,
        tengah: true,
      ),
      _kotak(
        _kolom([
          _t('1.   Tujuan Utama Transport Lokal:'),
          _menjorok(_t('Melakukan revisit Sensus Ekonomi 2026$hari'), 16),
        ]),
        73.6,
        tengah: true,
      ),
      _kotak(
        _kolom([
          _t(
            '2.  Kegiatan dilaksanakan di $lokasi, '
            '${RevisitLaporanDocx.kota}:',
          ),
          _menjorok(_t('Tanggal berangkat : $tgl'), 16.5),
          _menjorok(_t('Tanggal pulang      : $tgl'), 16.5),
        ]),
        70.2,
        tengah: true,
      ),
      _kotak(
        _kolom([
          _t('3.  Hasil Kegiatan:'),
          for (final p in _potong(pembuka))
            _menjorok(_t(p, align: pw.TextAlign.justify), 14.2),
          for (final b in butirHasil) ..._butirPanjang(b),
        ]),
        85.5,
        tengah: true,
      ),
      _kotak(
        _kolom([
          _t('4. Permasalahan yang Ditemui'),
          for (final m in RevisitLaporanDocx.permasalahan(h.laporan))
            ..._butirPanjang(m),
        ]),
        70.9,
      ),
      _kotak(
        _kolom([
          _t('5.  Rekomendasi yang Disampaikan:'),
          for (final r in RevisitLaporanDocx.rekomendasi(h.laporan))
            ..._butirPanjang(r),
        ]),
        49.2,
        tengah: true,
      ),
      _kotak(
        _kolom([
          _t('6.    Progress Kegiatan:'),
          _menjorok(
            _t(
              'Progress revisit Sensus Ekonomi 2026$hari ($tgl) telah '
              'disubmit ke aplikasi FASIH sebanyak $submit usaha/keluarga.',
              align: pw.TextAlign.justify,
            ),
            21.3,
          ),
        ]),
        56.7,
        tengah: true,
      ),
      // 7. Dokumentasi: tiap baris foto blok tersendiri agar bisa
      // berpindah halaman tanpa memotong foto.
      _kotak(_t('7.    Dokumentasi'), 0, bawah: false),
      for (var i = 0; i < siap.length; i += 2)
        _kotak(
          pw.Center(
            child: pw.Row(
              mainAxisSize: pw.MainAxisSize.min,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                for (final (j, f) in siap.skip(i).take(2).indexed) ...[
                  if (j > 0) pw.SizedBox(width: 10),
                  _foto(f, lebarFoto),
                ],
              ],
            ),
          ),
          0,
          bawah: false,
        ),
      for (final nama in gagal)
        _kotak(
          pw.Center(child: _t('(foto $nama tidak dapat dimuat)')),
          0,
          bawah: false,
        ),
      if (siap.isEmpty && gagal.isEmpty)
        _kotak(pw.Center(child: _t('-')), 0, bawah: false),
      _kotak(pw.SizedBox(), 6),

      // ── C & D: satu blok utuh (pindah halaman bersama bila tak muat) ──
      pw.Inseparable(child: pw.Column(children: cd)),
    ];
  }

  // ── Potongan tata letak ────────────────────────────────────────────────

  static pw.TableRow _barisA(
    String l1,
    String i1,
    String l2,
    String i2,
    double tinggi,
  ) => pw.TableRow(
    verticalAlignment: pw.TableCellVerticalAlignment.middle,
    children: [
      _sel(_t(l1), tinggi),
      _sel(_t(i1), tinggi),
      _sel(_t(l2), tinggi),
      _sel(_t(i2), tinggi),
    ],
  );

  /// Isi sel tabel dengan tinggi minimum [tinggi] pt.
  static pw.Widget _sel(
    pw.Widget isi,
    double tinggi, {
    bool bawah = false,
    bool tengah = false,
  }) => pw.Container(
    constraints: pw.BoxConstraints(minHeight: tinggi),
    padding: const pw.EdgeInsets.symmetric(horizontal: _pad, vertical: 2),
    alignment: bawah
        ? pw.Alignment.bottomCenter
        : tengah
        ? pw.Alignment.center
        : pw.Alignment.centerLeft,
    child: isi,
  );

  /// Satu "baris tabel" selebar halaman berupa kotak bergaris; dipakai
  /// agar MultiPage bisa memindahkan baris per baris ke halaman berikutnya.
  static pw.Widget _kotak(
    pw.Widget isi,
    double tinggi, {
    bool atas = false,
    bool bawah = true,
    bool tengah = false,
  }) => pw.Container(
    constraints: pw.BoxConstraints(minHeight: tinggi),
    padding: const pw.EdgeInsets.symmetric(horizontal: _pad, vertical: 3),
    alignment: tengah ? pw.Alignment.centerLeft : pw.Alignment.topLeft,
    decoration: pw.BoxDecoration(
      border: pw.Border(
        top: atas ? _garis : pw.BorderSide.none,
        left: _garis,
        right: _garis,
        bottom: bawah ? _garis : pw.BorderSide.none,
      ),
    ),
    child: isi,
  );

  /// Tinggi maksimum satu baris foto: foto potret yang sangat panjang
  /// (mis. tangkapan layar) yang lebih tinggi dari satu halaman tidak bisa
  /// dipindah halaman oleh MultiPage dan menggagalkan seluruh PDF.
  static const double _tinggiFotoMaks = 560;

  /// Foto selebar [lebar], diperkecil (rasio tetap) bila terlalu tinggi.
  static pw.Widget _foto(RevisitDocxFoto f, double lebar) {
    final rasio = f.width == 0 ? 1.0 : f.height / f.width;
    final tinggi = lebar * rasio;
    final skala = tinggi > _tinggiFotoMaks ? _tinggiFotoMaks / tinggi : 1.0;
    return pw.Image(
      pw.MemoryImage(f.jpg),
      width: lebar * skala,
      height: tinggi * skala,
    );
  }

  static pw.Widget _kolom(List<pw.Widget> isi, {bool tengah = false}) =>
      pw.Column(
        mainAxisSize: pw.MainAxisSize.min,
        crossAxisAlignment: tengah
            ? pw.CrossAxisAlignment.center
            : pw.CrossAxisAlignment.start,
        children: [
          for (final (i, w) in isi.indexed) ...[
            if (i > 0) pw.SizedBox(height: _spasi15),
            w,
          ],
        ],
      );

  static pw.Widget _menjorok(pw.Widget isi, double kiri) => pw.Padding(
    padding: pw.EdgeInsets.only(left: kiri),
    child: isi,
  );

  /// Batas panjang satu potongan teks: kira-kira 15 baris, jauh di bawah
  /// tinggi satu halaman.
  static const int _maksPotongan = 1200;

  /// Memecah teks panjang (mis. catatan petugas) menjadi beberapa potongan
  /// di akhir kalimat, atau di antara kata bila kalimatnya sendiri terlalu
  /// panjang. MultiPage hanya bisa berpindah halaman di antara widget, jadi
  /// satu paragraf yang lebih tinggi dari satu halaman membuatnya terus
  /// menambah halaman kosong sampai TooManyPagesException. Jarak antar-
  /// potongan (_spasi15) sama dengan jarak antarbaris, jadi tetap menyatu.
  static List<String> _potong(String teks) {
    if (teks.length <= _maksPotongan) return [teks];
    final hasil = <String>[];
    var sisa = teks.trim();
    while (sisa.length > _maksPotongan) {
      final jendela = sisa.substring(0, _maksPotongan);
      var potong = jendela.lastIndexOf(RegExp(r'[.!?;]\s'));
      potong = potong > _maksPotongan ~/ 3
          ? potong + 1
          : jendela.lastIndexOf(RegExp(r'\s'));
      if (potong <= 0) potong = _maksPotongan;
      hasil.add(sisa.substring(0, potong).trim());
      sisa = sisa.substring(potong).trim();
    }
    if (sisa.isNotEmpty) hasil.add(sisa);
    return hasil;
  }

  /// [_butir] untuk teks yang mungkin panjang: potongan pertama berpoin,
  /// sisanya menjorok sejajar teks butir tanpa poin.
  static List<pw.Widget> _butirPanjang(String teks) {
    final potongan = _potong(teks);
    return [
      _butir(potongan.first),
      for (final p in potongan.skip(1))
        _menjorok(_t(p, align: pw.TextAlign.justify), 32 + 10.6),
    ];
  }

  /// Butir daftar menjorok 42,5 pt seperti DOCX.
  static pw.Widget _butir(String teks) => pw.Padding(
    padding: const pw.EdgeInsets.only(left: 32),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: 10.6,
          padding: const pw.EdgeInsets.only(top: 4),
          alignment: pw.Alignment.topLeft,
          child: pw.Container(
            width: 3.5,
            height: 3.5,
            decoration: const pw.BoxDecoration(
              color: PdfColors.black,
              shape: pw.BoxShape.circle,
            ),
          ),
        ),
        pw.Expanded(child: _t(teks, align: pw.TextAlign.justify)),
      ],
    ),
  );

  static pw.Widget _isianVisum(String label, [String isi = '']) => pw.Row(
    children: [
      pw.SizedBox(width: 50, child: _t(label)),
      _t(
        isi.trim().isEmpty
            ? ': ..........................................................'
            : ': ${isi.trim()}',
      ),
    ],
  );

  static pw.Widget _t(
    String s, {
    pw.TextAlign? align,
    bool garisBawah = false,
  }) => pw.Text(
    teksAman(s),
    textAlign: align,
    style: pw.TextStyle(
      fontSize: _font,
      lineSpacing: _spasi15,
      decoration: garisBawah ? pw.TextDecoration.underline : null,
    ),
  );

  static const Map<String, String> _pengganti = {
    '‘': "'",
    '’': "'",
    '“': '"',
    '”': '"',
    '–': '-',
    '—': '-',
    '…': '...',
    '•': '-',
    ' ': ' ',
  };

  /// Font PDF bawaan hanya Latin-1; karakter lain (emoji, tanda kutip
  /// miring, dsb. dari isian petugas) diganti agar PDF tidak gagal dibuat.
  static String teksAman(String s) {
    final b = StringBuffer();
    for (final r in s.runes) {
      final c = String.fromCharCode(r);
      if (r <= 0xFF) {
        b.write(c);
      } else {
        b.write(_pengganti[c] ?? '?');
      }
    }
    return b.toString();
  }
}
