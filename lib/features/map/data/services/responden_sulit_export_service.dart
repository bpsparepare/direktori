import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart';

import '../models/responden_sulit_item.dart';

/// Ekspor daftar Responden Sulit ke file Excel (.xlsx) memakai
/// syncfusion_flutter_xlsio, lalu simpan ke direktori sementara aplikasi.
/// Mengikuti pola AnomaliExportService.
class RespondenSulitExportService {
  static String _fmtDate(DateTime? dt) {
    if (dt == null) return '';
    final l = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(l.day)}/${two(l.month)}/${l.year} ${two(l.hour)}:${two(l.minute)}';
  }

  /// Bangun file Excel dari [items], kembalikan path file yang tersimpan.
  Future<String> exportToFile(List<RespondenSulitItem> items) async {
    final workbook = Workbook();
    final sheet = workbook.worksheets[0];
    sheet.name = 'Responden Sulit';

    const headers = <String>[
      'No',
      'Nama',
      'Alamat',
      'Penjelasan',
      'Tindak Lanjut',
      'SLS',
      'Desa/Kelurahan',
      'Kecamatan',
      'Petugas (PPL)',
      'Pengawas (PML)',
      'Dibuat Oleh',
      'Diperbarui',
    ];

    for (var c = 0; c < headers.length; c++) {
      final cell = sheet.getRangeByIndex(1, c + 1);
      cell.setText(headers[c]);
      cell.cellStyle.bold = true;
      cell.cellStyle.backColor = '#0F4C81';
      cell.cellStyle.fontColor = '#FFFFFF';
    }

    for (var i = 0; i < items.length; i++) {
      final it = items[i];
      final row = i + 2;
      final values = <String>[
        '${i + 1}',
        it.nama,
        it.alamat,
        it.penjelasan,
        it.tindakLanjut,
        RespondenSulitItem.formatSlsLabel(it.nmSls, it.subSls),
        it.nmDesa,
        it.nmKec,
        it.pplNama,
        it.pmlNama,
        it.createdByNama,
        _fmtDate(it.updatedAt),
      ];
      for (var c = 0; c < values.length; c++) {
        sheet.getRangeByIndex(row, c + 1).setText(values[c]);
      }
    }

    // Lebar kolom sekadar agar terbaca.
    sheet.getRangeByIndex(1, 1).columnWidth = 5;
    for (var c = 2; c <= headers.length; c++) {
      sheet.getRangeByIndex(1, c).columnWidth = 22;
    }

    final bytes = workbook.saveAsStream();
    workbook.dispose();

    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final name =
        'responden_sulit_${stamp.year}${two(stamp.month)}${two(stamp.day)}_'
        '${two(stamp.hour)}${two(stamp.minute)}${two(stamp.second)}.xlsx';
    final path = '${dir.path}/$name';
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);
    return path;
  }
}
