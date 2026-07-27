import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/supabase_config.dart';

/// Satu sel bukti (satu dokumentasi terakhir untuk suatu kolom).
class BuktiDukungCell {
  final String namaFile;
  final String linkFile;
  final String driveFileId;
  final String previewUrl;
  final String createdAt;

  const BuktiDukungCell({
    required this.namaFile,
    required this.linkFile,
    required this.driveFileId,
    required this.previewUrl,
    required this.createdAt,
  });

  bool get isEmpty => linkFile.isEmpty && driveFileId.isEmpty;
  bool get isNotEmpty => !isEmpty;

  /// File ID Drive dari `driveFileId`, atau di-parse dari `linkFile`.
  String get resolvedDriveFileId {
    if (driveFileId.isNotEmpty) return driveFileId;
    if (linkFile.isEmpty) return '';
    final match = RegExp(r'/d/([a-zA-Z0-9_-]+)').firstMatch(linkFile);
    if (match != null) return match.group(1) ?? '';
    return Uri.tryParse(linkFile)?.queryParameters['id'] ?? '';
  }

  /// URL gambar yang bisa dirender langsung (thumbnail Drive).
  String get imageUrl {
    final id = resolvedDriveFileId;
    if (id.isEmpty) return '';
    return 'https://drive.google.com/thumbnail?id=$id&sz=w1000';
  }

  static BuktiDukungCell? fromRow(
    Map<String, dynamic> row, {
    required String prefix,
  }) {
    final link = (row['${prefix}_link'] ?? '').toString();
    final driveId = (row['${prefix}_drive_id'] ?? '').toString();
    if (link.isEmpty && driveId.isEmpty) return null;
    return BuktiDukungCell(
      namaFile: (row['${prefix}_nama_file'] ?? '').toString(),
      linkFile: link,
      driveFileId: driveId,
      previewUrl: (row['${prefix}_preview'] ?? '').toString(),
      createdAt: (row['${prefix}_created'] ?? '').toString(),
    );
  }
}

/// Satu baris petugas dengan 3 kolom bukti.
class BuktiDukungRow {
  final String petugasId;
  final String userId;
  final String nama;
  final String role;
  final BuktiDukungCell? termin1;
  final BuktiDukungCell? termin2;
  final BuktiDukungCell? paketData;

  const BuktiDukungRow({
    required this.petugasId,
    required this.userId,
    required this.nama,
    required this.role,
    this.termin1,
    this.termin2,
    this.paketData,
  });

  factory BuktiDukungRow.fromJson(Map<String, dynamic> row) {
    return BuktiDukungRow(
      petugasId: (row['petugas_id'] ?? '').toString(),
      userId: (row['user_id'] ?? '').toString(),
      nama: (row['nama'] ?? '-').toString(),
      role: (row['role'] ?? '').toString(),
      termin1: BuktiDukungCell.fromRow(row, prefix: 't1'),
      termin2: BuktiDukungCell.fromRow(row, prefix: 't2'),
      paketData: BuktiDukungCell.fromRow(row, prefix: 'pd'),
    );
  }
}

class BuktiDukungService {
  final SupabaseClient _client = SupabaseConfig.client;

  Future<List<BuktiDukungRow>> fetchRows() async {
    final response = await _client.rpc('get_bukti_dukung');
    if (response is! List) return [];
    return response
        .whereType<Map<String, dynamic>>()
        .map(BuktiDukungRow.fromJson)
        .toList();
  }
}
