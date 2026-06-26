import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/supabase_config.dart';
import '../models/nik_tidak_valid_item.dart';

// Safe parsers — handles both num and text columns from PostgREST
int _parseInt(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? 0;
}

int? _parseIntNull(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

class AnggotaItem {
  final int noUrut;
  final String namaDtsen;
  final String? nikDtsen;
  final String? hubungan;
  final String? jkDtsen;
  final int? umurAk;
  final String? tglLahir;
  final int? blnLahir;
  final int? thnLahir;
  final String? statusKawin;
  final String? keberadaanDtsen;

  const AnggotaItem({
    required this.noUrut,
    required this.namaDtsen,
    required this.nikDtsen,
    required this.hubungan,
    required this.jkDtsen,
    required this.umurAk,
    required this.tglLahir,
    required this.blnLahir,
    required this.thnLahir,
    required this.statusKawin,
    required this.keberadaanDtsen,
  });

  factory AnggotaItem.fromJson(Map<String, dynamic> json) {
    return AnggotaItem(
      noUrut: _parseInt(json['no_urut']),
      namaDtsen: (json['nama_dtsen'] ?? '').toString(),
      nikDtsen: json['nik_dtsen']?.toString(),
      hubungan: json['hubungan']?.toString(),
      jkDtsen: json['jk_dtsen']?.toString(),
      umurAk: _parseIntNull(json['umur_ak']),
      tglLahir: json['tgl_lahir']?.toString(),
      // bln_lahir is TEXT in se2026_anggota_keluarga
      blnLahir: _parseIntNull(json['bln_lahir']),
      thnLahir: _parseIntNull(json['thn_lahir']),
      statusKawin: json['status_kawin']?.toString(),
      keberadaanDtsen: json['keberadaan_dtsen']?.toString(),
    );
  }

  bool get isNikValid {
    final nik = nikDtsen;
    if (nik == null) return false;
    return RegExp(r'^\d{16}$').hasMatch(nik);
  }
}

class NikTidakValidService {
  final SupabaseClient _client = SupabaseConfig.client;
  static const String _cacheKey = 'nik_tidak_valid_cache_v2';
  static const String _cacheUpdatedAtKey = 'nik_tidak_valid_cache_updated_at_v2';

  Future<List<NikTidakValidItem>> loadCachedEntries() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedData = prefs.getString(_cacheKey);
      if (cachedData == null || cachedData.isEmpty) return [];
      final decoded = jsonDecode(cachedData);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(NikTidakValidItem.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<NikTidakValidItem>> refreshEntries() async {
    final entries = await _fetchFromRemote();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _cacheKey, jsonEncode(entries.map((e) => e.toJson()).toList()));
      await prefs.setString(
          _cacheUpdatedAtKey, DateTime.now().toIso8601String());
    } catch (_) {}
    return entries;
  }

  Future<DateTime?> loadCacheUpdatedAt() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getString(_cacheUpdatedAtKey);
      if (value == null || value.isEmpty) return null;
      return DateTime.tryParse(value);
    } catch (_) {
      return null;
    }
  }

  Future<List<AnggotaItem>> fetchAnggota(String assignmentId) async {
    final response = await _client
        .from('se2026_anggota_keluarga')
        .select(
          'no_urut, nama_dtsen, nik_dtsen, hubungan, jk_dtsen, umur_ak, '
          'tgl_lahir, bln_lahir, thn_lahir, status_kawin, keberadaan_dtsen',
        )
        .eq('assignment_id', assignmentId)
        .order('no_urut');
    return (response as List)
        .whereType<Map<String, dynamic>>()
        .map(AnggotaItem.fromJson)
        .toList();
  }

  Future<List<NikTidakValidItem>> _fetchFromRemote() async {
    final response = await _client.rpc('fn_nik_tidak_valid');
    if (response is! List) return [];
    return response
        .whereType<Map<String, dynamic>>()
        .map(NikTidakValidItem.fromJson)
        .toList();
  }
}
