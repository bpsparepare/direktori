import 'dart:convert';

import 'package:flutter/services.dart';

/// Lookup profesi dari CSV di assets/csv (delimiter ';', kolom: kode;nama).
/// nama berformat "003. Akuntan" -> disimpan tanpa prefiks kode.
class ProfesiLookup {
  static Map<String, String>? _cache;

  static Future<Map<String, String>> load() async {
    if (_cache != null) return _cache!;
    final map = <String, String>{};
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final path = manifest.listAssets().firstWhere(
            (p) =>
                p.startsWith('assets/csv/') &&
                p.toLowerCase().endsWith('.csv') &&
                p.toLowerCase().contains('profesi'),
            orElse: () => '',
          );
      if (path.isNotEmpty) {
        final raw = await rootBundle.loadString(path);
        final lines = const LineSplitter().convert(raw);
        for (var i = 1; i < lines.length; i++) {
          final line = lines[i];
          if (line.trim().isEmpty) continue;
          final f = line.split(';');
          if (f.length < 2) continue;
          final kode = f[0].trim();
          if (kode.isEmpty) continue;
          var nama = f.sublist(1).join(';').trim();
          // buang prefiks "003. " bila ada.
          final m = RegExp(r'^\s*\d+\.\s*').firstMatch(nama);
          if (m != null) nama = nama.substring(m.end).trim();
          map[kode] = nama;
        }
      }
    } catch (_) {
      // gagal muat -> kode ditampilkan apa adanya.
    }
    _cache = map;
    return map;
  }

  /// Nama profesi untuk [kode], fallback ke kode itu sendiri.
  static String name(Map<String, String> map, String kode) {
    final k = kode.trim();
    return map[k] ?? k;
  }
}
