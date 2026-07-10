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
  final String label;
  final int totalBaris;
  final int diperbarui;
  final int dinonaktifkan;
  final int dihapus;

  const AnomaliPusatImportResult({
    required this.label,
    required this.totalBaris,
    required this.diperbarui,
    required this.dinonaktifkan,
    required this.dihapus,
  });
}

/// Satu perubahan kolom pada kasus yang sudah ada di database.
class AnomaliPusatPerubahanKolom {
  final String field;
  final String? lama;
  final String? baru;

  const AnomaliPusatPerubahanKolom({
    required this.field,
    this.lama,
    this.baru,
  });

  factory AnomaliPusatPerubahanKolom.fromMap(Map<String, dynamic> map) {
    return AnomaliPusatPerubahanKolom(
      field: map['field'] as String? ?? '-',
      lama: map['lama'] as String?,
      baru: map['baru'] as String?,
    );
  }
}

/// Satu baris hasil perbandingan file vs database.
/// status: 'baru' | 'berubah' | 'sama' | 'hilang' (ada di database,
/// tidak ada di file).
class AnomaliPusatCompareRow {
  final String status;
  final String assignmentId;
  final String namaSubjek;
  final String kategoriKode;
  final String kategoriNama;
  final String? namaKec;
  final String? namaDesa;
  final bool isAktif;
  final List<AnomaliPusatPerubahanKolom> perubahan;

  const AnomaliPusatCompareRow({
    required this.status,
    required this.assignmentId,
    required this.namaSubjek,
    required this.kategoriKode,
    required this.kategoriNama,
    this.namaKec,
    this.namaDesa,
    required this.isAktif,
    required this.perubahan,
  });

  factory AnomaliPusatCompareRow.fromMap(Map<String, dynamic> map) {
    final rawPerubahan = map['perubahan'];
    return AnomaliPusatCompareRow(
      status: map['status'] as String? ?? '-',
      assignmentId: map['assignment_id'] as String? ?? '-',
      namaSubjek: map['nama_subjek'] as String? ?? '-',
      kategoriKode: map['kategori_kode'] as String? ?? '-',
      kategoriNama: map['kategori_nama'] as String? ?? '-',
      namaKec: map['nama_kec'] as String?,
      namaDesa: map['nama_desa'] as String?,
      isAktif: map['is_aktif'] as bool? ?? true,
      perubahan: rawPerubahan is List
          ? rawPerubahan
              .map((e) => AnomaliPusatPerubahanKolom.fromMap(
                  Map<String, dynamic>.from(e as Map)))
              .toList()
          : const [],
    );
  }
}

/// Hasil perbandingan seluruh baris 1 scope terhadap database.
class AnomaliPusatCompareResult {
  final String scope;
  final List<AnomaliPusatCompareRow> rows;

  const AnomaliPusatCompareResult({required this.scope, required this.rows});

  List<AnomaliPusatCompareRow> byStatus(String status) =>
      rows.where((r) => r.status == status).toList();

  int countOf(String status) => rows.where((r) => r.status == status).length;

  /// Kasus 'hilang' yang saat ini masih aktif -- kandidat dinonaktifkan
  /// pada mode refresh.
  int get hilangAktif =>
      rows.where((r) => r.status == 'hilang' && r.isAktif).length;
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
    'nama kepala keluarga': 'nama_subjek',
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
    'nama kepala keluarga': 'keluarga',
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

  /// Gabungkan baris semua file per scope dalam 1 daftar. Duplikat kunci
  /// kasus (assignment_id + nama_subjek + kategori_kode): baris terakhir
  /// menang, sama seperti perilaku upsert berurutan di server.
  ///
  /// Penting untuk mode refresh/replace: server memperlakukan baris yang
  /// tidak ada di batch sebagai "kasus lama", jadi semua file dengan scope
  /// sama HARUS dikirim sebagai 1 batch -- kalau dikirim per file, file
  /// kedua akan menonaktifkan/menghapus baris dari file pertama.
  static Map<String, List<Map<String, dynamic>>> gabungkanRowsPerScope(
    List<ParsedAnomaliPusatFile> files,
  ) {
    final byScope = <String, Map<String, Map<String, dynamic>>>{};
    for (final file in files) {
      final rows = byScope.putIfAbsent(file.scope, () => {});
      for (final row in file.rows) {
        final key = '${row['assignment_id']}||${row['nama_subjek']}||'
            '${row['kategori_kode']}';
        rows[key] = row;
      }
    }
    return {
      for (final entry in byScope.entries) entry.key: entry.value.values.toList(),
    };
  }

  /// Bandingkan baris 1 scope dengan isi database tanpa mengubah apa pun.
  /// Lihat compare_anomali_pusat_batch di
  /// supabase/migrations/20260708140000_anomali_pusat_compare.sql.
  Future<AnomaliPusatCompareResult> compareRows({
    required String scope,
    required List<Map<String, dynamic>> rows,
  }) async {
    final response = await _client.rpc(
      'compare_anomali_pusat_batch',
      params: {'p_scope': scope, 'p_rows': rows},
    );

    final parsed = (response as List)
        .map((e) =>
            AnomaliPusatCompareRow.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();

    return AnomaliPusatCompareResult(scope: scope, rows: parsed);
  }

  Future<AnomaliPusatImportResult> importRows({
    required String scope,
    required String label,
    required List<Map<String, dynamic>> rows,
    required AnomaliPusatImportMode mode,
  }) async {
    if (rows.isEmpty) {
      throw Exception('Tidak ada baris data untuk "$label".');
    }

    final response = await _client.rpc(
      'import_anomali_pusat_batch',
      params: {
        'p_scope': scope,
        'p_rows': rows,
        'p_mode': mode.rpcValue,
      },
    );

    final result = (response is List && response.isNotEmpty)
        ? response.first as Map<String, dynamic>
        : <String, dynamic>{};

    return AnomaliPusatImportResult(
      label: label,
      totalBaris: rows.length,
      diperbarui: (result['diperbarui'] as int?) ?? 0,
      dinonaktifkan: (result['dinonaktifkan'] as int?) ?? 0,
      dihapus: (result['dihapus'] as int?) ?? 0,
    );
  }
}
