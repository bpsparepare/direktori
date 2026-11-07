import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:direktori/features/map/data/models/revisit_models.dart';
import 'package:direktori/features/map/data/services/revisit_laporan_docx.dart';
import 'package:direktori/features/map/data/services/revisit_laporan_pdf.dart';

RevisitLaporan _laporan({
  String kodeSls = '7372010001001001',
  String catatan = 'Ada “kendala” — ✅\nBaris dua',
  int hariKe = 2,
  List<String> fotoIds = const ['d1', 'd2', 'd3'],
}) {
  return RevisitLaporan.fromJson({
    'id': 'x-$kodeSls',
    'kode_sls': kodeSls,
    'nm_kec': 'Bacukiki Barat',
    'nm_desa': 'Lumpue',
    'nm_sls': 'RT 01',
    'petugas_id': 'p1',
    'petugas_nama': 'Budi',
    'petugas_role': 'PPL',
    'petugas_tim': 'Tim A',
    'hari_ke': hariKe,
    'tanggal': DateTime(2026, 9, 18).toIso8601String(),
    'status': 'selesai',
    'jumlah_submit': 8,
    'jumlah_belum_didata': 3,
    'catatan': catatan,
    'foto': [
      for (final id in fotoIds)
        {
          'id': 'f-$id',
          'drive_file_id': id,
          'link_file': 'https://example.com/$id',
          'nama_file': '$id.jpg',
        },
    ],
  });
}

RevisitDocxFoto _jpg(int w, int h) {
  final g = img.Image(width: w, height: h)..clear(img.ColorRgb8(120, 160, 200));
  return RevisitDocxFoto(
    jpg: Uint8List.fromList(img.encodeJpg(g)),
    width: w,
    height: h,
  );
}

void main() {
  test('PDF laporan terbentuk, teks non-Latin1 tidak menggagalkan', () async {
    final halaman = RevisitLaporanDocx.kelompokkan([
      _laporan(),
      _laporan(kodeSls: '7372010001002001', fotoIds: const ['d4']),
      _laporan(hariKe: 3, fotoIds: const ['d5']),
    ]);
    final bytes = await RevisitLaporanPdf.build(
      halaman: halaman,
      foto: {
        'd1': _jpg(1000, 750),
        'd2': _jpg(750, 1000),
        'd3': _jpg(1000, 750),
        'd5': _jpg(750, 1000),
      },
      mengetahui: const RevisitPejabatMengetahui(
        nama: 'Dian Ernawaty, S.ST, M.A.P',
        jabatan: 'Kepala BPS Kota Parepare',
        nip: '19850324 200801 2 002',
      ),
      pejabat: const {
        'x-7372010001001001': RevisitPejabat(
          nama: 'Pak RT',
          jabatan: 'Ketua RT',
        ),
      },
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    final keluar = Platform.environment['LAPORAN_PDF_OUT'];
    if (keluar != null) await File(keluar).writeAsBytes(bytes);
  });

  test('catatan lebih panjang dari satu halaman tetap jadi PDF', () async {
    final panjang = List.filled(1500, 'Catatan kunjungan.').join(' ');
    final tanpaTitik = List.filled(1500, 'kata').join(' ');
    for (final catatan in [panjang, tanpaTitik, 'x' * 20000]) {
      final bytes = await RevisitLaporanPdf.build(
        halaman: RevisitLaporanDocx.kelompokkan([
          _laporan(catatan: catatan, fotoIds: const []),
          _laporan(kodeSls: '7372010001002001', fotoIds: const []),
        ]),
        foto: const {},
        mengetahui: const RevisitPejabatMengetahui(nama: 'A', jabatan: 'B'),
      );
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    }
  });

  test('banyak SLS & catatan panjang melewati batas halaman', () async {
    final panjang = List.filled(
      12,
      'Responden belum ditemui, dijadwalkan ulang',
    ).join('\n');
    final halaman = RevisitLaporanDocx.kelompokkan([
      for (var i = 0; i < 14; i++)
        _laporan(
          kodeSls: '73720100010${i.toString().padLeft(2, '0')}001',
          catatan: i.isEven ? panjang : 'Selesai',
          fotoIds: ['a$i', 'b$i'],
        ),
    ]);
    final bytes = await RevisitLaporanPdf.build(
      halaman: halaman,
      foto: {
        for (var i = 0; i < 14; i++) ...{
          'a$i': _jpg(1000, 750),
          'b$i': _jpg(450, 1000),
        },
        // Tangkapan layar panjang: lebih tinggi dari satu halaman.
        'a0': _jpg(400, 2000),
      },
      mengetahui: const RevisitPejabatMengetahui(nama: 'X', jabatan: 'Y'),
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    final keluar = Platform.environment['LAPORAN_PDF_OUT2'];
    if (keluar != null) await File(keluar).writeAsBytes(bytes);
  });

  test('banyak SLS dengan pejabat berbeda: C+D tetap jadi PDF', () async {
    for (final n in [12, 30]) {
      final laporan = [
        for (var i = 0; i < n; i++)
          _laporan(
            kodeSls: '7372010001${i.toString().padLeft(3, '0')}01',
            fotoIds: const [],
          ),
      ];
      final bytes = await RevisitLaporanPdf.build(
        halaman: RevisitLaporanDocx.kelompokkan(laporan),
        foto: const {},
        mengetahui: const RevisitPejabatMengetahui(nama: 'A', jabatan: 'B'),
        pejabat: {
          for (final (i, l) in laporan.indexed)
            l.id: RevisitPejabat(nama: 'Pejabat $i', jabatan: 'Ketua RT $i'),
        },
      );
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    }
  });

  test('teksAman mengganti karakter di luar Latin-1', () {
    expect(RevisitLaporanPdf.teksAman('“a” – b ✅ é'), '"a" - b ? é');
  });
}
