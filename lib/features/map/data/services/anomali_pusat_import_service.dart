import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/supabase_config.dart';
import 'xlsx_reader.dart';

/// Mode penanganan kasus lama (scope yang sama) yang tidak muncul lagi
/// di file yang baru diunggah.
enum AnomaliPusatImportMode {
  /// Nonaktifkan sementara -- otomatis aktif lagi kalau muncul lagi nanti.
  refresh,

  /// Hapus permanen dari daftar. Keterangan petugas tidak ikut terhapus.
  replace,

  /// Jangan ubah apa pun yang lama, cuma tambah/perbarui yang ada di file.
  tambahkan,
}

extension on AnomaliPusatImportMode {
  String get rpcValue {
    switch (this) {
      case AnomaliPusatImportMode.refresh:
        return 'refresh';
      case AnomaliPusatImportMode.replace:
        return 'replace';
      case AnomaliPusatImportMode.tambahkan:
        return 'tambahkan';
    }
  }
}

class ParsedAnomaliPusatFile {
  final String fileName;
  final String scope;
  final List<Map<String, dynamic>> rows;

  const ParsedAnomaliPusatFile({
    required this.fileName,
    required this.scope,
    required this.rows,
  });
}

class AnomaliPusatImportResult {
  final String fileName;
  final int totalBaris;
  final int diperbarui;
  final int dinonaktifkan;
  final int dihapus;

  const AnomaliPusatImportResult({
    required this.fileName,
    required this.totalBaris,
    required this.diperbarui,
    required this.dinonaktifkan,
    required this.dihapus,
  });
}

/// Import file export Fasih ("Data Mikro Kasus Anomali Usaha/Keluarga")
/// langsung ke tabel anomali_pusat_temuan lewat RPC import_anomali_pusat_batch.
/// Jenis data (usaha/keluarga) dideteksi otomatis dari header kolom file,
/// jadi pengguna tidak perlu memilihnya secara manual.
class AnomaliPusatImportService {
  final SupabaseClient _client = SupabaseConfig.client;

  static const Map<String, String> _headerAliases = {
    'nama usaha': 'nama_subjek',
    'nama krt': 'nama_subjek',
    'kode prov': 'kode_prov',
    'nama provinsi': 'nama_provinsi',
    'kode kab/kota': 'kode_kab',
    'nama kab/kota': 'nama_kab',
    'kode kec': 'kode_kec',
    'nama kecamatan': 'nama_kec',
    'kode desa': 'kode_desa',
    'nama desa/kel': 'nama_desa',
    'kode sls': 'kode_sls',
    'sub sls': 'sub_sls',
    'assignment id': 'assignment_id',
    'nama anomali': 'nama_anomali',
    'tindak lanjut': 'tindak_lanjut',
    'id petugas': 'id_petugas',
    'email petugas': 'email_petugas',
    'link fasih': 'link_fasih',
  };

  static const Map<String, String> _scopeByHeader = {
    'nama usaha': 'usaha',
    'nama krt': 'keluarga',
  };

  static final RegExp _kategoriPattern =
      RegExp(r'Anomali\s+(?:Data\s+)?(\d+)\s*\(([^)]*)\)');

  /// Baca 1 file excel, deteksi otomatis jenis datanya (usaha/keluarga) dari
  /// header kolom ("Nama Usaha" vs "Nama KRT"), lalu parse semua barisnya.
  ParsedAnomaliPusatFile parseFile(String fileName, Uint8List bytes) {
    final grid = XlsxReader.readFirstSheet(bytes);

    int? headerRowIndex;
    Map<int, String>? columnMap;
    String? detectedScope;

    for (var i = 0; i < grid.length; i++) {
      final map = <int, String>{};
      String? scopeGuess;
      final row = grid[i];
      for (var c = 0; c < row.length; c++) {
        final key = row[c].trim().toLowerCase();
        final alias = _headerAliases[key];
        if (alias != null) map[c] = alias;
        final scopeAlias = _scopeByHeader[key];
        if (scopeAlias != null) scopeGuess = scopeAlias;
      }
      if (map.values.contains('assignment_id') &&
          map.values.contains('nama_anomali')) {
        headerRowIndex = i;
        columnMap = map;
        detectedScope = scopeGuess;
        break;
      }
    }

    if (headerRowIndex == null || columnMap == null) {
      throw Exception(
        'Format file "$fileName" tidak dikenali: header "Assignment ID"/'
        '"Nama Anomali" tidak ditemukan. Pastikan file adalah export '
        '"Data Mikro Kasus Anomali" dari Fasih.',
      );
    }
    if (detectedScope == null) {
      throw Exception(
        'Tidak bisa mendeteksi jenis data (usaha/keluarga) dari file '
        '"$fileName" -- kolom "Nama Usaha"/"Nama KRT" tidak ditemukan.',
      );
    }

    var startRow = headerRowIndex + 1;
    if (startRow < grid.length && _looksLikeColumnNumbering(grid[startRow])) {
      startRow += 1;
    }

    final results = <Map<String, dynamic>>[];
    for (var i = startRow; i < grid.length; i++) {
      final row = grid[i];
      if (row.every((cell) => cell.trim().isEmpty)) continue;

      final record = <String, dynamic>{};
      columnMap.forEach((col, field) {
        record[field] = col < row.length ? row[col].trim() : '';
      });

      if ((record['assignment_id'] as String? ?? '').isEmpty) continue;

      final parsedKategori = _parseKategori(
        record['nama_anomali'] as String? ?? '',
        detectedScope,
      );
      record['kategori_kode'] = parsedKategori.$1;
      record['kategori_nama'] = parsedKategori.$2;

      results.add(record);
    }

    return ParsedAnomaliPusatFile(
      fileName: fileName,
      scope: detectedScope,
      rows: results,
    );
  }

  /// Ekstrak (kode, nama) kategori dari kalimat "Nama Anomali" mentah.
  /// Kode diberi prefix per scope ('usaha' -> UP, 'keluarga' -> KP) supaya
  /// sama persis dengan yang dihitung server di import_anomali_pusat_batch.
  /// Dipakai untuk preview -- parsing final tetap dilakukan lagi di server.
  (String, String) _parseKategori(String namaAnomali, String scope) {
    final prefix = scope == 'usaha' ? 'UP' : 'KP';
    final match = _kategoriPattern.firstMatch(namaAnomali);
    if (match == null) {
      return ('${prefix}LAINNYA', namaAnomali.isEmpty ? '-' : namaAnomali);
    }
    return ('$prefix${match.group(1)!}', match.group(2)!.trim());
  }

  bool _looksLikeColumnNumbering(List<String> row) {
    final nonEmpty = row.where((c) => c.trim().isNotEmpty).toList();
    if (nonEmpty.isEmpty) return false;
    return nonEmpty.every((c) => RegExp(r'^\(\d+\)$').hasMatch(c.trim()));
  }

  Future<AnomaliPusatImportResult> importFile({
    required ParsedAnomaliPusatFile file,
    required AnomaliPusatImportMode mode,
  }) async {
    if (file.rows.isEmpty) {
      throw Exception('Tidak ada baris data pada file "${file.fileName}".');
    }

    final response = await _client.rpc(
      'import_anomali_pusat_batch',
      params: {
        'p_scope': file.scope,
        'p_rows': file.rows,
        'p_mode': mode.rpcValue,
      },
    );

    final result = (response is List && response.isNotEmpty)
        ? response.first as Map<String, dynamic>
        : <String, dynamic>{};

    return AnomaliPusatImportResult(
      fileName: file.fileName,
      totalBaris: file.rows.length,
      diperbarui: (result['diperbarui'] as int?) ?? 0,
      dinonaktifkan: (result['dinonaktifkan'] as int?) ?? 0,
      dihapus: (result['dihapus'] as int?) ?? 0,
    );
  }
}
