import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart';

import '../models/anomali_gabungan_item.dart';

/// Ekspor daftar anomali (pusat_baru) ke file Excel (.xlsx) memakai
/// syncfusion_flutter_xlsio, lalu simpan ke direktori sementara aplikasi.
class AnomaliExportService {
  static String _fmtDate(DateTime? dt) {
    if (dt == null) return '';
    final l = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(l.day)}/${two(l.month)}/${l.year} ${two(l.hour)}:${two(l.minute)}';
  }

  // Deployment Parepare: provinsi & kab/kota selalu tetap.
  static const String _namaProvinsi = 'Sulawesi Selatan';
  static const String _namaKab = 'Kota Parepare';

  /// Potong aman [kw] pada [start,end); '' bila panjang kurang.
  static String _slice(String kw, int start, int end) =>
      kw.length >= end ? kw.substring(start, end) : '';

  /// Bangun file Excel dari [items], kembalikan path file yang tersimpan.
  Future<String> exportToFile(List<AnomaliGabunganItem> items) async {
    final workbook = Workbook();
    final sheet = workbook.worksheets[0];
    sheet.name = 'Anomali';

    const headers = <String>[
      'No',
      'Jenis',
      'Kode Prov',
      'Nama Provinsi',
      'Kode Kab/Kota',
      'Nama Kab/Kota',
      'Kode Kec',
      'Nama Kecamatan',
      'Kode Desa',
      'Nama Desa/Kel',
      'Kode SLS',
      'Sub SLS',
      'Nama SLS',
      'Kode Wilayah',
      'Nama Subjek',
      'Kategori',
      'Nama Kategori',
      'Deskripsi Anomali',
      'Status Pemeriksaan',
      'Jumlah Respons',
      'Keterangan',
      'Petugas (PPL)',
      'Pengawas (PML)',
      'Status Assignment',
      'Terverifikasi',
      'Diverifikasi Oleh',
      'Waktu Verifikasi',
      'Assignment ID',
      'Link Fasih',
    ];

    for (var c = 0; c < headers.length; c++) {
      final cell = sheet.getRangeByIndex(1, c + 1);
      cell.setText(headers[c]);
      cell.cellStyle.bold = true;
      cell.cellStyle.backColor = '#1F6FEB';
      cell.cellStyle.fontColor = '#FFFFFF';
    }

    for (var i = 0; i < items.length; i++) {
      final it = items[i];
      final row = i + 2;
      final kw = it.kodeWilayah;
      // nama_wilayah = "Kecamatan / Kelurahan".
      final wparts = it.namaWilayah.split(' / ');
      final namaKec = wparts.isNotEmpty ? wparts.first : '';
      final namaDesa = wparts.length > 1 ? wparts[1] : '';
      final values = <String>[
        '${i + 1}',
        it.kategoriBesarLabel,
        _slice(kw, 0, 2),
        _namaProvinsi,
        _slice(kw, 0, 4),
        _namaKab,
        _slice(kw, 0, 7),
        namaKec,
        _slice(kw, 0, 10),
        namaDesa,
        _slice(kw, 10, 14),
        it.subSls.isNotEmpty ? it.subSls : _slice(kw, 14, 16),
        it.namaSls,
        kw,
        it.subjek,
        it.kategoriKode,
        it.kategoriLabel,
        it.deskripsi,
        it.jenisSemua.isNotEmpty ? it.jenisSemua : 'Belum Diperiksa',
        '${it.jumlahRespons}',
        it.keteranganSemua,
        it.namaPetugas,
        it.namaPml,
        it.statusAssignment ?? '',
        it.isVerified ? 'Ya' : 'Tidak',
        it.verifiedOleh ?? '',
        _fmtDate(it.verifiedAt),
        it.assignmentId,
        it.linkFasih,
      ];
      for (var c = 0; c < values.length; c++) {
        sheet.getRangeByIndex(row, c + 1).setText(values[c]);
      }
    }

    // Lebar kolom sekadar agar terbaca (No sempit, lainnya lebih lebar).
    sheet.getRangeByIndex(1, 1).columnWidth = 5;
    for (var c = 2; c <= headers.length; c++) {
      sheet.getRangeByIndex(1, c).columnWidth = 20;
    }

    final bytes = workbook.saveAsStream();
    workbook.dispose();

    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final name =
        'anomali_${stamp.year}${two(stamp.month)}${two(stamp.day)}_'
        '${two(stamp.hour)}${two(stamp.minute)}${two(stamp.second)}.xlsx';
    final path = '${dir.path}/$name';
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);
    return path;
  }
}
