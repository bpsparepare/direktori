import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/config/supabase_config.dart';

class PanduanKbliEntry {
  final int id;
  final String jenisUsaha;
  final String kategori;
  final String kbli2025;
  final String produksi;
  final String layananMakanMinum;
  final String penjualan;
  final String aktivitas;
  final String input;
  final String proses;
  final String output;

  const PanduanKbliEntry({
    required this.id,
    required this.jenisUsaha,
    required this.kategori,
    required this.kbli2025,
    required this.produksi,
    required this.layananMakanMinum,
    required this.penjualan,
    required this.aktivitas,
    required this.input,
    required this.proses,
    required this.output,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'jenis_usaha': jenisUsaha,
      'kategori': kategori,
      'kbli_2025': kbli2025,
      'produksi': produksi,
      'layanan_makan_minum': layananMakanMinum,
      'penjualan': penjualan,
      'aktivitas': aktivitas,
      'input': input,
      'proses': proses,
      'output': output,
    };
  }

  factory PanduanKbliEntry.fromJson(Map<String, dynamic> json) {
    return PanduanKbliEntry(
      id: (json['id'] as num?)?.toInt() ?? 0,
      jenisUsaha: (json['jenis_usaha'] ?? '').toString().trim(),
      kategori: (json['kategori'] ?? '').toString().trim(),
      kbli2025: (json['kbli_2025'] ?? '').toString().trim(),
      produksi: (json['produksi'] ?? '').toString().trim(),
      layananMakanMinum: (json['layanan_makan_minum'] ?? '').toString().trim(),
      penjualan: (json['penjualan'] ?? '').toString().trim(),
      aktivitas: (json['aktivitas'] ?? '').toString().trim(),
      input: (json['input'] ?? '').toString().trim(),
      proses: (json['proses'] ?? '').toString().trim(),
      output: (json['output'] ?? '').toString().trim(),
    );
  }
}

class KbliSupabaseService {
  final SupabaseClient _client = SupabaseConfig.client;
  static const String _tableName = 'panduan_kbli';
  static const String _cacheKey = 'panduan_kbli_cache_v1';
  static const String _cacheUpdatedAtKey = 'panduan_kbli_cache_updated_at_v1';

  Future<List<PanduanKbliEntry>> loadCachedEntries() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedData = prefs.getString(_cacheKey);
      if (cachedData == null || cachedData.isEmpty) {
        return [];
      }

      final decoded = jsonDecode(cachedData);
      if (decoded is! List) {
        return [];
      }

      return decoded
          .whereType<Map<String, dynamic>>()
          .map(PanduanKbliEntry.fromJson)
          .where((item) => item.jenisUsaha.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<PanduanKbliEntry>> refreshEntries() async {
    final entries = await _fetchEntriesFromRemote();

    try {
      final prefs = await SharedPreferences.getInstance();
      final updatedAt = DateTime.now().toIso8601String();
      final payload = jsonEncode(
        entries.map((entry) => entry.toJson()).toList(),
      );
      await prefs.setString(_cacheKey, payload);
      await prefs.setString(_cacheUpdatedAtKey, updatedAt);
    } catch (_) {
      // Ignore cache write failures and still return fresh server data.
    }

    return entries;
  }

  Future<DateTime?> loadCacheUpdatedAt() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getString(_cacheUpdatedAtKey);
      if (value == null || value.isEmpty) {
        return null;
      }

      return DateTime.tryParse(value);
    } catch (_) {
      return null;
    }
  }

  Future<List<PanduanKbliEntry>> fetchEntries() async {
    return _fetchEntriesFromRemote();
  }

  Future<List<PanduanKbliEntry>> _fetchEntriesFromRemote() async {
    final response = await _client
        .from(_tableName)
        .select('''
          id,
          jenis_usaha,
          kategori,
          kbli_2025,
          produksi,
          layanan_makan_minum,
          penjualan,
          aktivitas,
          input,
          proses,
          output
        ''')
        .order('jenis_usaha', ascending: true)
        .order('kategori', ascending: true)
        .order('kbli_2025', ascending: true);

    return response
        .whereType<Map<String, dynamic>>()
        .map(PanduanKbliEntry.fromJson)
        .where((item) => item.jenisUsaha.isNotEmpty)
        .toList();
  }
}
