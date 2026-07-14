import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart';

/// Satu baris data ekspor Lembar Kerja (level wilayah SLS/sub-SLS) beserta
/// petugas pemiliknya.
class LembarKerjaExportRow {
  final String petugas;
  final String petugasEmail;
  final String kodeWilayah;
  final String namaSls;
  final String kecDesa;
  final int target;
  final int total;
  final int submitted;
  final int draft;
  final int open;

  /// Distribusi jenis bangunan untuk wilayah ini: key kode_bang ('1'..'9',
  /// '' = Tidak Diketahui) -> jumlah.
  final Map<String, int> kodeBang;

  const LembarKerjaExportRow({
    required this.petugas,
    required this.petugasEmail,
    required this.kodeWilayah,
    required this.namaSls,
    required this.kecDesa,
    required this.target,
    required this.total,
    required this.submitted,
    required this.draft,
    required this.open,
    this.kodeBang = const {},
  });

  int get potensi => submitted + draft;
}

/// Ekspor Lembar Kerja (progres per wilayah untuk seluruh petugas) ke file
/// Excel (.xlsx) memakai syncfusion_flutter_xlsio.
class LembarKerjaExportService {
  // Deployment Parepare: provinsi & kab/kota selalu tetap.
  static const String _namaProvinsi = 'Sulawesi Selatan';
  static const String _namaKab = 'Kota Parepare';

  /// Urutan kolom kode_bang. Bucket "tidak ditemukan" (kode_bang kosong) sudah
  /// dipecah RPC menjadi TD_USAHA & TD_KELUARGA (via jenis_prelist).
  static const List<String> _kodeBangOrder = [
    '1', '2', '3', '4', '5', '6', '7', '8', '9', 'TD_USAHA', 'TD_KELUARGA',
  ];

  /// Label singkat kode_bang untuk header Excel.
  static const Map<String, String> _kodeBangShort = {
    '1': 'Khusus Usaha',
    '2': 'Campuran',
    '3': 'Tempat Tinggal',
    '4': 'Ibadah/Ormas',
    '5': 'Pemerintah',
    '6': 'Lainnya',
    '7': 'Virtual Office',
    '8': 'Panti/Lapas',
    '9': 'Non Respon',
    'TD_USAHA': 'Usaha Tidak Ditemukan',
    'TD_KELUARGA': 'Keluarga Tidak Ditemukan',
  };

  static String _kodeBangHeader(String code) {
    final label = _kodeBangShort[code] ?? code;
    if (code.startsWith('TD')) return label;
    return 'Bang $code: $label';
  }

  /// Potong aman [kw] pada [start,end); '' bila panjang kurang.
  static String _slice(String kw, int start, int end) =>
      kw.length >= end ? kw.substring(start, end) : '';

  /// Bangun file Excel dari [rows], kembalikan path file yang tersimpan.
  Future<String> exportToFile(List<LembarKerjaExportRow> rows) async {
    final workbook = Workbook();
    final sheet = workbook.worksheets[0];
    sheet.name = 'Lembar Kerja';

    // Kolom dasar (21 kolom), lalu rincian distribusi kode_bang.
    final headers = <String>[
      'No',
      'Petugas (PPL)',
      'Email',
      'Kode Prov',
      'Nama Provinsi',
      'Kode Kab/Kota',
      'Nama Kab/Kota',
      'Kode Kec',
      'Kode Desa',
      'Kode SLS',
      'Sub SLS',
      'Nama SLS',
      'Kecamatan / Desa',
      'Kode Wilayah',
      'Target (Prelist)',
      'Total Assignment',
      'Submitted',
      'Draft',
      'Open',
      'Potensi (Sub+Draft)',
      '% Capaian',
      for (final code in _kodeBangOrder) _kodeBangHeader(code),
    ];
    // Kolom pertama rincian kode_bang (setelah 21 kolom dasar).
    const kodeBangStartCol = 22;

    for (var c = 0; c < headers.length; c++) {
      final cell = sheet.getRangeByIndex(1, c + 1);
      cell.setText(headers[c]);
      cell.cellStyle.bold = true;
      cell.cellStyle.backColor = '#0F4C81';
      cell.cellStyle.fontColor = '#FFFFFF';
    }

    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      final row = i + 2;
      final kw = r.kodeWilayah;
      final persen = r.target > 0
          ? '${(r.submitted / r.target * 100).toStringAsFixed(0)}%'
          : '';

      // Kolom teks.
      final texts = <int, String>{
        1: '${i + 1}',
        2: r.petugas,
        3: r.petugasEmail,
        4: _slice(kw, 0, 2),
        5: _namaProvinsi,
        6: _slice(kw, 0, 4),
        7: _namaKab,
        8: _slice(kw, 0, 7),
        9: _slice(kw, 0, 10),
        10: _slice(kw, 10, 14),
        11: _slice(kw, 14, 16),
        12: r.namaSls,
        13: r.kecDesa,
        14: kw,
        21: persen,
      };
      texts.forEach((col, value) {
        sheet.getRangeByIndex(row, col).setText(value);
      });

      // Kolom angka.
      final numbers = <int, int>{
        15: r.target,
        16: r.total,
        17: r.submitted,
        18: r.draft,
        19: r.open,
        20: r.potensi,
      };
      numbers.forEach((col, value) {
        sheet.getRangeByIndex(row, col).setNumber(value.toDouble());
      });

      // Rincian distribusi kode_bang.
      for (var k = 0; k < _kodeBangOrder.length; k++) {
        final value = r.kodeBang[_kodeBangOrder[k]] ?? 0;
        sheet
            .getRangeByIndex(row, kodeBangStartCol + k)
            .setNumber(value.toDouble());
      }
    }

    // Baris total di bawah.
    if (rows.isNotEmpty) {
      final totalRow = rows.length + 2;
      final totTarget = rows.fold<int>(0, (s, r) => s + r.target);
      final totTotal = rows.fold<int>(0, (s, r) => s + r.total);
      final totSubmitted = rows.fold<int>(0, (s, r) => s + r.submitted);
      final totDraft = rows.fold<int>(0, (s, r) => s + r.draft);
      final totOpen = rows.fold<int>(0, (s, r) => s + r.open);
      final totPotensi = totSubmitted + totDraft;

      final labelCell = sheet.getRangeByIndex(totalRow, 2);
      labelCell.setText('TOTAL');
      final totNumbers = <int, int>{
        15: totTarget,
        16: totTotal,
        17: totSubmitted,
        18: totDraft,
        19: totOpen,
        20: totPotensi,
      };
      totNumbers.forEach((col, value) {
        sheet.getRangeByIndex(totalRow, col).setNumber(value.toDouble());
      });
      if (totTarget > 0) {
        sheet
            .getRangeByIndex(totalRow, 21)
            .setText('${(totSubmitted / totTarget * 100).toStringAsFixed(0)}%');
      }
      // Total rincian kode_bang.
      for (var k = 0; k < _kodeBangOrder.length; k++) {
        final code = _kodeBangOrder[k];
        final sum = rows.fold<int>(0, (s, r) => s + (r.kodeBang[code] ?? 0));
        sheet
            .getRangeByIndex(totalRow, kodeBangStartCol + k)
            .setNumber(sum.toDouble());
      }
      final totalRange = sheet.getRangeByIndex(
        totalRow,
        1,
        totalRow,
        headers.length,
      );
      totalRange.cellStyle.bold = true;
      totalRange.cellStyle.backColor = '#EAF1FB';
    }

    // Lebar kolom sekadar agar terbaca.
    sheet.getRangeByIndex(1, 1).columnWidth = 5;
    for (var c = 2; c <= headers.length; c++) {
      sheet.getRangeByIndex(1, c).columnWidth = 16;
    }

    final bytes = workbook.saveAsStream();
    workbook.dispose();

    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final name =
        'lembar_kerja_${stamp.year}${two(stamp.month)}${two(stamp.day)}_'
        '${two(stamp.hour)}${two(stamp.minute)}${two(stamp.second)}.xlsx';
    final path = '${dir.path}/$name';
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);
    return path;
  }
}
