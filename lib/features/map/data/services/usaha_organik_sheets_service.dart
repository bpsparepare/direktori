import 'dart:convert';

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart' show rootBundle;
import 'package:gsheets/gsheets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/usaha_organik_item.dart';

class UsahaOrganikSheetsService {
  static const String _spreadsheetId =
      '1mYcv_13CRFRfeu5JE5tCnNFtzBK4NJpVVoEtI3ps_po';
  static const String _worksheetName = 'Sheet1';
  static const String _saAssetPath = 'assets/sa/sa-account.json';
  static const String _cacheKey = 'usaha_organik_cache_v1';
  static const String _cacheUpdatedAtKey = 'usaha_organik_cache_updated_at_v1';

  Future<List<UsahaOrganikItem>> loadCachedEntries() async {
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
          .map(UsahaOrganikItem.fromJson)
          .where((item) => item.nama.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<DateTime?> loadCacheUpdatedAt() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheUpdatedAtKey);
      if (raw == null || raw.isEmpty) {
        return null;
      }
      return DateTime.tryParse(raw);
    } catch (_) {
      return null;
    }
  }

  Future<List<UsahaOrganikItem>> refreshEntries() async {
    final entries = await _fetchEntriesFromRemote();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _cacheKey,
        jsonEncode(entries.map((item) => item.toJson()).toList()),
      );
      await prefs.setString(
        _cacheUpdatedAtKey,
        DateTime.now().toIso8601String(),
      );
    } catch (_) {
      // Abaikan kegagalan menulis cache, data segar tetap dikembalikan.
    }

    return entries;
  }

  Future<List<UsahaOrganikItem>> _fetchEntriesFromRemote() async {
    final gsheets = await _initClient();

    try {
      final spreadsheet = await gsheets.spreadsheet(_spreadsheetId);
      final worksheet = spreadsheet.worksheetByTitle(_worksheetName);
      if (worksheet == null) {
        throw Exception('Worksheet "$_worksheetName" tidak ditemukan.');
      }

      final rows =
          await worksheet.values.map.allRows(fromRow: 1) ??
          const <Map<String, String>>[];

      final headerIndex = _buildHeaderIndexFromMapRows(rows);
      return _mapRowsWithHeaderIndex(rows, headerIndex);
    } on GSheetsException catch (e) {
      throw Exception(_friendlyGSheetsError(e));
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Gagal membaca data Usaha Organik: $e');
    }
  }

  List<UsahaOrganikItem> _mapRowsWithHeaderIndex(
    List<Map<String, String>> rows,
    Map<String, int> headerIndex,
  ) {
    const requiredHeaders = ['nama', 'alamat', 'keterangan'];
    final missingHeaders = requiredHeaders
        .where((header) => !headerIndex.containsKey(header))
        .toList();

    if (missingHeaders.isNotEmpty) {
      throw Exception(
        'Header sheet tidak lengkap. Wajib ada: Nama, Alamat, Keterangan.',
      );
    }

    return rows
        .map((row) {
          return UsahaOrganikItem(
            nama: _mapCellValue(row, 'Nama'),
            alamat: _mapCellValue(row, 'Alamat'),
            keterangan: _mapCellValue(row, 'Keterangan'),
          );
        })
        .where((item) => item.nama.isNotEmpty)
        .toList();
  }

  Future<GSheets> _initClient() async {
    try {
      final jsonStr = await rootBundle.loadString(_saAssetPath);
      if (jsonStr.trim().isEmpty) {
        throw Exception('File service account kosong.');
      }
      return GSheets(jsonStr);
    } on FlutterError {
      throw Exception(
        'File asset $_saAssetPath tidak ditemukan. Tambahkan file service account ke folder assets/sa/.',
      );
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Gagal memuat service account: $e');
    }
  }

  Map<String, int> _buildHeaderIndexFromMapRows(
    List<Map<String, String>> rows,
  ) {
    final result = <String, int>{};
    if (rows.isEmpty) {
      return result;
    }

    final keys = rows.first.keys.toList();
    for (var i = 0; i < keys.length; i++) {
      final normalized = _normalizeHeader(keys[i]);
      if (normalized.isNotEmpty) {
        result[normalized] = i;
      }
    }
    return result;
  }

  String _mapCellValue(Map<String, String> row, String key) {
    return (row[key] ?? '').toString().trim();
  }

  String _normalizeHeader(String raw) {
    return raw
        .replaceFirst('\ufeff', '')
        .replaceAll('"', '')
        .trim()
        .toLowerCase();
  }

  String _friendlyGSheetsError(GSheetsException error) {
    final message = error.toString();
    final lower = message.toLowerCase();

    if (lower.contains('403') ||
        lower.contains('permission') ||
        lower.contains('forbidden')) {
      return 'Akses ke spreadsheet ditolak. Pastikan sheet sudah dibagikan ke email service account.';
    }

    if (lower.contains('404') || lower.contains('not found')) {
      return 'Spreadsheet atau worksheet tidak ditemukan. Periksa spreadsheet id dan nama sheet.';
    }

    return 'Gagal membaca Google Sheets: $message';
  }
}
