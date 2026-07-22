import 'package:shared_preferences/shared_preferences.dart';

import '../models/keluarga_aset_item.dart';

/// Ambang kepemilikan aset (>= ambang = anomali). Disimpan lokal
/// (SharedPreferences), dapat diatur admin per perangkat.
class AsetThresholds {
  static const Map<String, int> defaults = {
    'tabung3kg': 4,
    'tabung5kg': 3,
    'kulkas': 3,
    'ac': 3,
    'emas': 100,
    'laptop': 4,
    'motor': 5,
    'mobil': 3,
    'lahan': 4,
    'rumah': 3,
  };

  static String _key(String aset) => 'aset_threshold_$aset';

  static Future<Map<String, int>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final map = <String, int>{};
    for (final k in KeluargaAsetItem.asetKeys) {
      map[k] = prefs.getInt(_key(k)) ?? defaults[k] ?? 1;
    }
    return map;
  }

  static Future<void> save(Map<String, int> values) async {
    final prefs = await SharedPreferences.getInstance();
    for (final k in KeluargaAsetItem.asetKeys) {
      final v = values[k];
      if (v != null) await prefs.setInt(_key(k), v);
    }
  }

  static Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    for (final k in KeluargaAsetItem.asetKeys) {
      await prefs.remove(_key(k));
    }
  }
}
