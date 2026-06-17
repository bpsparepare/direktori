import 'dart:convert';

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart' show rootBundle;
import 'package:gsheets/gsheets.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PanduanKbliEntry {
  final int id;
  final String jenisUsaha;
  final String kategori;
  final String kbli2025;
  final String keteranganKbli;
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
    required this.keteranganKbli,
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
      'keterangan_kbli': keteranganKbli,
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
      keteranganKbli: (json['keterangan_kbli'] ?? '').toString().trim(),
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

class KbliSheetsService {
  static const String _spreadsheetId =
      '1eDyc0Sg8tyyvk6V5LWs4fW8hX8_fh24Z_yIONqCWgwU';
  static const String _worksheetName = 'Sheet1';
  static const String _saAssetPath = 'assets/sa/sa-account.json';
  static const String _cacheKey = 'panduan_kbli_cache_v2';
  static const String _cacheUpdatedAtKey = 'panduan_kbli_cache_updated_at_v2';

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

  Future<List<PanduanKbliEntry>> refreshEntries() async {
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

  Future<List<PanduanKbliEntry>> fetchEntries() async {
    return _fetchEntriesFromRemote();
  }

  Future<List<PanduanKbliEntry>> _fetchEntriesFromRemote() async {
    final gsheets = await _initClient();

    try {
      final spreadsheet = await gsheets.spreadsheet(_spreadsheetId);
      final prioritizedWorksheets = <Worksheet>[
        if (spreadsheet.worksheetByTitle(_worksheetName) != null)
          spreadsheet.worksheetByTitle(_worksheetName)!,
        ...spreadsheet.sheets.where((sheet) => sheet.title != _worksheetName),
      ];

      Exception? lastError;
      for (final worksheet in prioritizedWorksheets) {
        final rows =
            await worksheet.values.map.allRows(fromRow: 1) ??
            const <Map<String, String>>[];
        if (rows.isEmpty) {
          continue;
        }

        try {
          _validateHeaders(rows);
          final entries = rows
              .map(_mapRowToEntry)
              .where((item) => item.jenisUsaha.isNotEmpty)
              .toList();
          if (entries.isNotEmpty) {
            return entries;
          }
          lastError = Exception(
            'Worksheet "${worksheet.title}" terbaca, tetapi semua baris kosong setelah dipetakan.',
          );
        } catch (e) {
          lastError = e is Exception ? e : Exception(e.toString());
        }
      }

      if (lastError != null) {
        throw lastError;
      }
      throw Exception(
        'Tidak ada worksheet KBLI yang berisi data. Periksa nama tab dan isi spreadsheet.',
      );
    } on GSheetsException catch (e) {
      throw Exception(_friendlyGSheetsError(e));
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Gagal membaca data KBLI: $e');
    }
  }

  PanduanKbliEntry _mapRowToEntry(Map<String, String> row) {
    final idText = _valueForHeaders(row, const ['No']);
    return PanduanKbliEntry(
      id: int.tryParse(idText) ?? 0,
      jenisUsaha: _valueForHeaders(row, const ['Jenis Usaha']),
      kategori: _valueForHeaders(row, const ['Kategori']),
      kbli2025: _normalizeKbli(_valueForHeaders(row, const ['KBLI 2025'])),
      keteranganKbli: _valueForHeaders(row, const ['KETERANGAN KBLI']),
      produksi: _valueForHeaders(row, const ['Produksi']),
      layananMakanMinum: _valueForHeaders(row, const ['Layanan Makan Minum']),
      penjualan: _valueForHeaders(row, const ['Penjualan']),
      aktivitas: _valueForHeaders(row, const ['Aktivitas']),
      input: _valueForHeaders(row, const ['Input']),
      proses: _valueForHeaders(row, const ['Proses']),
      output: _valueForHeaders(row, const ['Output']),
    );
  }

  void _validateHeaders(List<Map<String, String>> rows) {
    if (rows.isEmpty) {
      return;
    }

    const requiredHeaders = <String>[
      'Jenis Usaha',
      'Kategori',
      'KBLI 2025',
      'KETERANGAN KBLI',
      'Produksi',
      'Layanan Makan Minum',
      'Penjualan',
      'Aktivitas',
      'Input',
      'Proses',
      'Output',
    ];

    final normalizedHeaders = rows.first.keys
        .map(_normalizeHeader)
        .where((value) => value.isNotEmpty)
        .toSet();
    final missingHeaders = requiredHeaders
        .where(
          (header) => !normalizedHeaders.contains(_normalizeHeader(header)),
        )
        .toList();

    if (missingHeaders.isNotEmpty) {
      throw Exception(
        'Header sheet tidak lengkap. Wajib ada: ${missingHeaders.join(', ')}.',
      );
    }
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

  String _valueForHeaders(Map<String, String> row, List<String> headers) {
    for (final header in headers) {
      if (row.containsKey(header)) {
        return (row[header] ?? '').trim();
      }
    }

    final normalizedRow = <String, String>{};
    row.forEach((key, value) {
      normalizedRow[_normalizeHeader(key)] = value;
    });
    for (final header in headers) {
      final value = normalizedRow[_normalizeHeader(header)];
      if (value != null) {
        return value.trim();
      }
    }
    return '';
  }

  String _normalizeHeader(String raw) {
    return raw
        .replaceFirst('\ufeff', '')
        .replaceAll('"', '')
        .trim()
        .toLowerCase();
  }

  String _normalizeKbli(String raw) {
    final trimmed = raw.trim();
    if (trimmed.endsWith('.0')) {
      return trimmed.substring(0, trimmed.length - 2);
    }
    return trimmed;
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
