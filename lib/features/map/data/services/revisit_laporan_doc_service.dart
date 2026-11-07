import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../../../../core/services/google_drive_service.dart';
import '../models/revisit_models.dart';
import 'revisit_laporan_docx.dart';
import 'revisit_laporan_pdf.dart';
import 'revisit_service.dart';

/// Hasil pembuatan laporan: satu dokumen per petugas, di satu folder periode.
class RevisitLaporanHasil {
  /// Link folder Drive tempat semua dokumen periode ini disimpan.
  final String folderLink;

  /// Nama petugas → link Google Docs-nya.
  final Map<String, String> dokumen;

  const RevisitLaporanHasil({required this.folderLink, required this.dokumen});
}

/// Membuat "Laporan Perjalanan Dinas" revisit sebagai Google Docs: satu
/// dokumen per petugas (nama file memuat nama petugas), berisi satu laporan
/// per hari ke- yang masing-masing mulai di halaman baru, dengan foto
/// dokumentasi tertanam. Disimpan pribadi (tidak publik) di folder Drive
/// `Revisit/Laporan/<periode>`.
class RevisitLaporanDocService {
  final GoogleDriveService _drive = GoogleDriveService();

  /// Jumlah dokumen yang diunggah bersamaan.
  static const int _unggahBersamaan = 3;

  /// [periode] dipakai untuk nama folder dan dokumen, mis. "Hari ke-1 s.d. 14".
  /// [onProgress] menerima keterangan langkah yang sedang berjalan.
  Future<RevisitLaporanHasil> buat({
    required List<RevisitLaporan> laporan,
    required String periode,
    required RevisitPejabatMengetahui mengetahui,
    void Function(String)? onProgress,
  }) async {
    laporan = await _muatPenyisiran(laporan);
    final perPetugas = kelompokPerPetugas(laporan);
    final foto = await _muatFoto(laporan, onProgress);
    final pejabat = await _muatPejabat(laporan);

    final revisitFolder = await _drive.ensureFolderInParent(
      RevisitService.driveRootFolderId,
      RevisitService.driveFolderName,
    );
    final folderLaporan = await _drive.ensureFolderInParent(
      revisitFolder,
      'Laporan',
    );
    final folderPeriode = await _drive.ensureFolderInParent(
      folderLaporan,
      periode,
    );

    final dokumen = <String, String>{};
    var selesai = 0;
    final daftar = perPetugas.entries.toList();
    onProgress?.call('Membuat dokumen 0/${daftar.length}…');
    for (var i = 0; i < daftar.length; i += _unggahBersamaan) {
      await Future.wait(
        daftar.skip(i).take(_unggahBersamaan).map((e) async {
          final docx = RevisitLaporanDocx.build(
            halaman: RevisitLaporanDocx.kelompokkan(e.value),
            foto: foto,
            mengetahui: mengetahui,
            pejabat: pejabat,
          );
          dokumen[e.key] = await _drive.createGoogleDocFromDocx(
            folderId: folderPeriode,
            name: namaDokumen(e.key, periode),
            docx: docx,
          );
          selesai++;
          onProgress?.call('Membuat dokumen $selesai/${daftar.length}…');
        }),
      );
    }

    return RevisitLaporanHasil(
      folderLink: 'https://drive.google.com/drive/folders/$folderPeriode',
      dokumen: dokumen,
    );
  }

  /// Laporan yang sama sebagai satu PDF lokal (tanpa unggah ke Drive; foto
  /// tetap dimuat dari Drive). Urut per petugas, tiap laporan di halaman
  /// baru. Mengembalikan path file.
  Future<String> buatPdf({
    required List<RevisitLaporan> laporan,
    required String periode,
    required RevisitPejabatMengetahui mengetahui,
    void Function(String)? onProgress,
  }) async {
    laporan = await _muatPenyisiran(laporan);
    final foto = await _muatFoto(laporan, onProgress);
    final pejabat = await _muatPejabat(laporan);
    onProgress?.call('Menyusun PDF…');
    final halaman = [
      for (final isi in kelompokPerPetugas(laporan).values)
        ...RevisitLaporanDocx.kelompokkan(isi),
    ];
    final bytes = await RevisitLaporanPdf.build(
      halaman: halaman,
      foto: foto,
      mengetahui: mengetahui,
      pejabat: pejabat,
    );
    final dir = await getTemporaryDirectory();
    final aman = periode.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
    final path = '${dir.path}/laporan_revisit_$aman.pdf';
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }

  /// Nama & jabatan pejabat yang ditemui (isian form petugas). Gagal dibaca
  /// (mis. database belum diperbarui) tidak menggagalkan laporan: bagian C
  /// tetap berupa titik-titik untuk diisi tangan.
  Future<Map<String, RevisitPejabat>> _muatPejabat(
    List<RevisitLaporan> laporan,
  ) async {
    try {
      return await RevisitService().fetchPejabat(
        laporan.map((l) => l.id).toList(),
      );
    } catch (e) {
      debugPrint('[RevisitLaporanDoc] pejabat gagal dibaca: $e');
      return const {};
    }
  }

  /// Laporan dilengkapi nama jalan & jumlah bangunan penyisiran. Gagal
  /// dibaca tidak menggagalkan laporan: isiannya jadi titik-titik.
  Future<List<RevisitLaporan>> _muatPenyisiran(
    List<RevisitLaporan> laporan,
  ) async {
    try {
      final data = await RevisitService().fetchPenyisiran(
        laporan.map((l) => l.id).toList(),
      );
      return [
        for (final l in laporan)
          data[l.id] == null ? l : l.denganPenyisiran(data[l.id]!),
      ];
    } catch (e) {
      debugPrint('[RevisitLaporanDoc] penyisiran gagal dibaca: $e');
      return laporan;
    }
  }

  /// Laporan dikelompokkan per petugas (diurutkan menurut nama). Kunci =
  /// nama petugas; nama kembar dibedakan dengan id singkat.
  static Map<String, List<RevisitLaporan>> kelompokPerPetugas(
    List<RevisitLaporan> laporan,
  ) {
    final perId = <String, List<RevisitLaporan>>{};
    for (final l in laporan) {
      perId.putIfAbsent(l.petugasId, () => []).add(l);
    }
    final namaDipakai = <String, int>{};
    for (final isi in perId.values) {
      final nama = isi.first.petugasNama;
      namaDipakai[nama] = (namaDipakai[nama] ?? 0) + 1;
    }
    final hasil = <String, List<RevisitLaporan>>{};
    final urut = perId.entries.toList()
      ..sort(
        (a, b) => a.value.first.petugasNama.toLowerCase().compareTo(
          b.value.first.petugasNama.toLowerCase(),
        ),
      );
    for (final e in urut) {
      final nama = e.value.first.petugasNama;
      final kunci = (namaDipakai[nama] ?? 0) > 1
          ? '$nama (${e.key.substring(0, e.key.length.clamp(0, 6))})'
          : nama;
      hasil[kunci] = e.value;
    }
    return hasil;
  }

  /// Nama file Google Docs untuk seorang petugas.
  static String namaDokumen(String petugas, String periode) =>
      'Laporan Perjalanan Dinas Revisit - $petugas - $periode';

  /// Jumlah foto yang diunduh bersamaan.
  static const int _unduhBersamaan = 6;

  /// Ambil foto dari Drive, beberapa sekaligus. Foto yang gagal dilewati
  /// (dokumen menuliskan keterangan sebagai gantinya).
  Future<Map<String, RevisitDocxFoto>> _muatFoto(
    List<RevisitLaporan> laporan,
    void Function(String)? onProgress,
  ) async {
    final ids = <String>{
      for (final l in laporan)
        for (final f in l.foto)
          if (f.driveFileId.isNotEmpty) f.driveFileId,
    }.toList();
    final hasil = <String, RevisitDocxFoto>{};
    var selesai = 0;
    if (ids.isNotEmpty) onProgress?.call('Memuat foto 0/${ids.length}…');
    for (var i = 0; i < ids.length; i += _unduhBersamaan) {
      await Future.wait(
        ids.skip(i).take(_unduhBersamaan).map((id) async {
          try {
            final siap = await _ambilFoto(id);
            if (siap != null) hasil[id] = siap;
          } catch (e) {
            debugPrint('[RevisitLaporanDoc] foto $id gagal: $e');
          }
          selesai++;
          onProgress?.call('Memuat foto $selesai/${ids.length}…');
        }),
      );
    }
    return hasil;
  }

  /// Utamakan thumbnail Drive 1000 px (kecil, sudah diputar, cukup dibaca
  /// ukurannya). Baru unduh file asli lalu perkecil bila thumbnail tidak ada.
  Future<RevisitDocxFoto?> _ambilFoto(String id) async {
    final thumb = await _drive.downloadThumbnailBytes(
      id,
      ukuran: _lebarFotoMaks,
    );
    if (thumb != null) {
      final ukuran = RevisitLaporanDocx.ukuranJpeg(thumb);
      if (ukuran != null) {
        return RevisitDocxFoto(jpg: thumb, width: ukuran.$1, height: ukuran.$2);
      }
      return compute(_siapkanFoto, thumb);
    }
    final asli = await _drive.downloadFileBytes(id);
    return compute(_siapkanFoto, asli);
  }
}

/// Lebar maksimum foto yang ditanam (px): cukup tajam untuk cetak, dan
/// menjaga ukuran dokumen tetap kecil.
const int _lebarFotoMaks = 1000;

/// Dijalankan di isolate terpisah: putar sesuai EXIF, perkecil, encode JPEG.
RevisitDocxFoto? _siapkanFoto(Uint8List bytes) {
  final asli = img.decodeImage(bytes);
  if (asli == null) return null;
  var gambar = img.bakeOrientation(asli);
  if (gambar.width > _lebarFotoMaks) {
    gambar = img.copyResize(
      gambar,
      width: _lebarFotoMaks,
      interpolation: img.Interpolation.average,
    );
  }
  return RevisitDocxFoto(
    jpg: img.encodeJpg(gambar, quality: 82),
    width: gambar.width,
    height: gambar.height,
  );
}
