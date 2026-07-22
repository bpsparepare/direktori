import 'dart:convert';

import 'package:flutter/services.dart';

class KbliInfo {
  final String kode;
  final String judul;
  final String deskripsi;
  final String kategori;

  const KbliInfo({
    required this.kode,
    required this.judul,
    required this.deskripsi,
    required this.kategori,
  });
}

/// Master KBLI 2025 dari CSV di assets/csv (delimiter ';', kolom:
/// No;Kategori;Kode;Judul;kat_kbli;Deskripsi;Bukan cakupan SE).
/// Dimuat sekali lalu di-cache.
class KbliMaster {
  static Map<String, KbliInfo>? _cache;

  static Future<Map<String, KbliInfo>> load() async {
    if (_cache != null) return _cache!;
    final map = <String, KbliInfo>{};
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final path = manifest.listAssets().firstWhere(
            (p) =>
                p.startsWith('assets/csv/') &&
                p.toLowerCase().endsWith('.csv') &&
                p.toLowerCase().contains('kbli'),
            orElse: () => '',
          );
      if (path.isNotEmpty) {
        final raw = await rootBundle.loadString(path);
        final lines = const LineSplitter().convert(raw);
        for (var i = 1; i < lines.length; i++) {
          final line = lines[i];
          if (line.trim().isEmpty) continue;
          final f = line.split(';');
          if (f.length < 4) continue;
          final kode = f[2].trim();
          if (kode.isEmpty) continue;
          // Deskripsi bisa mengandung ';'; kolom terakhir = "Bukan cakupan SE".
          final deskripsi = f.length > 6
              ? f.sublist(5, f.length - 1).join(';').trim()
              : (f.length > 5 ? f[5].trim() : '');
          map[kode] = KbliInfo(
            kode: kode,
            judul: f[3].trim(),
            deskripsi: deskripsi,
            kategori: f[1].trim(),
          );
        }
      }
    } catch (_) {
      // gagal muat CSV -> lookup kosong (kode tetap tampil apa adanya).
    }
    _cache = map;
    return map;
  }
}
