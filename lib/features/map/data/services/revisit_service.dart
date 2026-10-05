import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/supabase_config.dart';
import '../../../../core/services/google_drive_service.dart';
import '../models/revisit_models.dart';
import '../models/revisit_reject_item.dart';

/// Satu baris impor cepat yang sudah diverifikasi.
class RevisitImportRow {
  final String kodeSls;
  final String petugasId;
  final int? hariKe;
  final String? tim;

  const RevisitImportRow({
    required this.kodeSls,
    required this.petugasId,
    this.hariKe,
    this.tim,
  });
}

/// Konteks pengguna untuk menu Revisit.
class RevisitContext {
  final bool isAdmin;
  final bool isRevisit;

  const RevisitContext({required this.isAdmin, required this.isRevisit});

  static const none = RevisitContext(isAdmin: false, isRevisit: false);

  bool get canOpen => isAdmin || isRevisit;
}

/// Service fitur "Revisit". Semua akses tabel lewat RPC security definer —
/// lihat supabase/migrations/20260919120000_revisit.sql. Foto disimpan di
/// Google Drive (folder `Revisit/<tanggal>`), metadata-nya di Supabase.
class RevisitService {
  /// Folder induk yang sama dengan menu Dokumentasi.
  static const String _driveRootFolderId = '1lOWg2mW4px6VsWuBE2if1o4LLYZfggAk';
  static const String _driveFolderName = 'Revisit';

  /// Ukuran halaman = batas max-rows PostgREST (default Supabase 1000).
  static const int _pageSize = 1000;

  final SupabaseClient _client = SupabaseConfig.client;
  final GoogleDriveService _driveService = GoogleDriveService();

  Future<RevisitContext> fetchContext() async {
    try {
      final response = await _client.rpc('get_revisit_context');
      if (response is! Map) return RevisitContext.none;
      return RevisitContext(
        isAdmin: response['is_admin'] == true,
        isRevisit: response['is_revisit'] == true,
      );
    } catch (e) {
      debugPrint('[RevisitService] fetchContext ERROR: $e');
      return RevisitContext.none;
    }
  }

  // ── Tim & alokasi (admin) ──────────────────────────────────────────────────

  Future<List<RevisitPetugas>> fetchPetugas() async {
    final rows = await _fetchAll('get_revisit_petugas');
    return rows.map(RevisitPetugas.fromJson).toList();
  }

  Future<void> setPetugasRevisit(String petugasId, bool aktif) async {
    final response = await _client.rpc(
      'set_revisit_petugas',
      params: {'p_petugas_id': petugasId, 'p_aktif': aktif},
    );
    _throwIfError(response);
  }

  Future<void> setTim(String petugasId, String tim) async {
    final response = await _client.rpc(
      'set_revisit_petugas_tim',
      params: {'p_petugas_id': petugasId, 'p_tim': tim},
    );
    _throwIfError(response);
  }

  Future<List<RevisitAlokasiItem>> fetchAlokasi() async {
    final rows = await _fetchAll('get_revisit_alokasi');
    return rows.map(RevisitAlokasiItem.fromJson).toList();
  }

  /// Menambah jadwal (SLS + hari + petugas). Satu SLS boleh punya beberapa
  /// hari, dan satu hari boleh dipegang lebih dari satu petugas.
  ///
  /// - [petugasId] null: lepas jadwal SLS tsb — hanya [hariKe] bila diisi,
  ///   atau seluruh harinya bila null.
  /// - [lepasPetugas] true dengan [petugasId] terisi: hapus jadwal petugas
  ///   itu saja.
  /// - [ganti] true: petugas lain pada (SLS, hari) itu dilepas dulu, jadi
  ///   jadwalnya bertukar, bukan bertambah.
  Future<void> setAlokasi(
    List<String> kodeSls,
    String? petugasId, {
    int? hariKe,
    bool lepasPetugas = false,
    bool ganti = false,
  }) async {
    final response = await _client.rpc(
      'set_revisit_alokasi',
      params: {
        'p_kode_sls': kodeSls,
        'p_petugas_id': petugasId,
        'p_hari_ke': hariKe,
        'p_lepas_petugas': lepasPetugas,
        'p_ganti': ganti,
      },
    );
    _throwIfError(response);
  }

  /// Impor cepat alokasi hasil verifikasi. [ganti] true = petugas lain pada
  /// (SLS, hari) yang diimpor dilepas dulu (tukar, bukan tambah).
  /// Mengembalikan (tersimpan, dilewati, jadwal petugas lain yang dilepas).
  Future<(int, int, int)> importAlokasi(
    List<RevisitImportRow> rows, {
    bool ganti = false,
  }) async {
    final response = await _client.rpc(
      'import_revisit_alokasi',
      params: {
        'p_rows': [
          for (final r in rows)
            {
              'kode_sls': r.kodeSls,
              'petugas_id': r.petugasId,
              'hari_ke': r.hariKe,
              'tim': r.tim,
            },
        ],
        'p_ganti': ganti,
      },
    );
    _throwIfError(response);
    final map = response as Map;
    return (
      (map['count'] as num?)?.toInt() ?? 0,
      (map['skipped'] as num?)?.toInt() ?? 0,
      ((map['diganti'] as num?)?.toInt() ?? 0) +
          ((map['dilepas'] as num?)?.toInt() ?? 0),
    );
  }

  // ── Reject (daftar assignment yang perlu di-reject) ───────────────────────

  /// Ringkasan per SLS (ringan; dipanggil saat tab dibuka).
  Future<List<RevisitRejectSls>> fetchRejectSls() async {
    final rows = await _fetchAll('get_revisit_reject_sls');
    return rows.map(RevisitRejectSls.fromJson).toList();
  }

  /// Isi assignment satu SLS (dipanggil saat SLS dibuka).
  Future<List<RevisitRejectItem>> fetchRejectDetail(String kodeSls) async {
    final rows = await _fetchAll(
      'get_revisit_reject_detail',
      params: {'p_kode_sls': kodeSls},
    );
    return rows.map(RevisitRejectItem.fromJson).toList();
  }

  Future<void> tandaiReject(String assignmentId, {String? alasan}) async {
    final response = await _client.rpc(
      'set_revisit_reject',
      params: {'p_assignment_id': assignmentId, 'p_alasan': alasan},
    );
    _throwIfError(response);
  }

  Future<void> batalkanReject(String assignmentId) async {
    final response = await _client.rpc(
      'unset_revisit_reject',
      params: {'p_assignment_id': assignmentId},
    );
    _throwIfError(response);
  }

  // ── Petugas revisit ────────────────────────────────────────────────────────

  /// Ringkasan per SLS alokasi. Tanpa [petugasId] = milik sendiri; dengan
  /// [petugasId] = petugas tsb (admin).
  Future<List<RevisitTugas>> fetchTugasSaya({String? petugasId}) async {
    final rows = await _fetchAll(
      'get_revisit_tugas_saya',
      params: {'p_petugas_id': petugasId},
    );
    return rows.map(RevisitTugas.fromJson).toList();
  }

  /// Admin: semua laporan (opsional per petugas). Selain admin: milik sendiri.
  /// [milikSaya] true = hanya laporan milik pengguna yang login (dipakai
  /// form laporan, karena satu SLS+tanggal bisa punya laporan dari beberapa
  /// petugas).
  Future<List<RevisitLaporan>> fetchLaporan({
    required DateTime dari,
    required DateTime sampai,
    String? petugasId,
    String? kodeSls,
    bool milikSaya = false,
    int? hariKe,
  }) async {
    final rows = await _fetchAll(
      'get_revisit_laporan',
      params: {
        'p_dari': revisitDateParam(dari),
        'p_sampai': revisitDateParam(sampai),
        'p_petugas_id': petugasId,
        'p_kode_sls': kodeSls,
        'p_milik_saya': milikSaya,
        'p_hari_ke': hariKe,
      },
    );
    return rows.map(RevisitLaporan.fromJson).toList();
  }

  /// Progres kumulatif per "hari ke-" alokasi (untuk grafik Rekap).
  Future<List<RevisitProgresHariKe>> fetchProgresHariKe() async {
    final rows = await _fetchAll('get_revisit_progres_hari_ke');
    return rows.map(RevisitProgresHariKe.fromJson).toList();
  }

  /// Matriks petugas × hari ke- (untuk melihat sel yang belum dilapor).
  Future<List<RevisitMatriksSel>> fetchMatriksHari() async {
    final rows = await _fetchAll('get_revisit_matriks_hari');
    return rows.map(RevisitMatriksSel.fromJson).toList();
  }

  /// Rekap kumulatif per petugas (admin: semua; selain admin: sendiri).
  Future<List<RevisitRekapPetugas>> fetchRekapPetugas() async {
    final rows = await _fetchAll('get_revisit_rekap_petugas');
    return rows.map(RevisitRekapPetugas.fromJson).toList();
  }

  /// Total didata per tanggal (seluruh riwayat). Admin: semua / per petugas;
  /// selain admin: milik sendiri.
  Future<List<RevisitProgresHari>> fetchProgres({String? petugasId}) async {
    final rows = await _fetchAll(
      'get_revisit_progres_harian',
      params: {'p_petugas_id': petugasId},
    );
    return rows.map(RevisitProgresHari.fromJson).toList();
  }

  /// Simpan laporan (insert/update per SLS+tanggal). Mengembalikan id laporan.
  /// [hariKe] = jadwal yang dilaporkan (0 = jadwal tanpa hari). Satu laporan
  /// per (SLS, petugas, hari ke-).
  Future<String> simpanLaporan({
    required String kodeSls,
    required DateTime tanggal,
    required int hariKe,
    required String status,
    int? jumlahDidata,
    int? jumlahSubmit,
    int? jumlahBelumDidata,
    String? catatan,
  }) async {
    final response = await _client.rpc(
      'upsert_revisit_laporan',
      params: {
        'p_kode_sls': kodeSls,
        'p_tanggal': revisitDateParam(tanggal),
        'p_status': status,
        'p_jumlah_dicek': jumlahDidata,
        'p_catatan': catatan,
        'p_jumlah_belum': jumlahBelumDidata,
        'p_jumlah_submit': jumlahSubmit,
        'p_hari_ke': hariKe,
      },
    );
    _throwIfError(response);
    return (response as Map)['id'].toString();
  }

  Future<void> hapusLaporan(RevisitLaporan laporan) async {
    for (final foto in laporan.foto) {
      await _deleteDriveFileQuietly(foto.driveFileId);
    }
    final response = await _client.rpc(
      'delete_revisit_laporan',
      params: {'p_id': laporan.id},
    );
    _throwIfError(response);
  }

  /// Upload foto ke Drive (`Revisit/<tanggal>`) lalu catat di laporan.
  Future<void> uploadFoto({
    required String laporanId,
    required String kodeSls,
    required DateTime tanggal,
    required Uint8List bytes,
    required String extension,
  }) async {
    final revisitFolder = await _driveService.ensureFolderInParent(
      _driveRootFolderId,
      _driveFolderName,
    );
    final dateFolder = await _driveService.ensureFolderInParent(
      revisitFolder,
      revisitDateParam(tanggal),
    );
    final now = DateTime.now();
    final stamp =
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}'
        '${now.millisecond.toString().padLeft(3, '0')}';
    final fileName = 'revisit_${kodeSls}_$stamp.$extension';

    final result = await _driveService.uploadFile(dateFolder, fileName, bytes);
    final driveFileId = (result['id'] ?? '').toString();
    if (driveFileId.isEmpty) {
      throw Exception('Upload foto gagal: id file Drive kosong');
    }

    final response = await _client.rpc(
      'add_revisit_foto',
      params: {
        'p_laporan_id': laporanId,
        'p_drive_file_id': driveFileId,
        'p_link_file': (result['webViewLink'] ?? '').toString(),
        'p_nama_file': fileName,
      },
    );
    if (response is Map && response['ok'] != true) {
      await _deleteDriveFileQuietly(driveFileId);
      _throwIfError(response);
    }
  }

  Future<void> hapusFoto(RevisitFoto foto) async {
    final response = await _client.rpc(
      'delete_revisit_foto',
      params: {'p_id': foto.id},
    );
    _throwIfError(response);
    await _deleteDriveFileQuietly(foto.driveFileId);
  }

  // ── Helper ─────────────────────────────────────────────────────────────────

  /// Ambil SEMUA baris RPC dengan paging (.range) karena respons dibatasi
  /// max-rows. Urutan RPC stabil sehingga halaman tidak tumpang tindih.
  Future<List<Map<String, dynamic>>> _fetchAll(
    String fn, {
    Map<String, dynamic>? params,
  }) async {
    try {
      final rows = <Map<String, dynamic>>[];
      for (var offset = 0; ; offset += _pageSize) {
        final response = await _client
            .rpc(fn, params: params)
            .range(offset, offset + _pageSize - 1);
        if (response is! List) break;
        rows.addAll(
          response.whereType<Map>().map((r) => Map<String, dynamic>.from(r)),
        );
        if (response.length < _pageSize) break;
      }
      return rows;
    } catch (e) {
      debugPrint('[RevisitService] $fn ERROR: $e');
      rethrow;
    }
  }

  Future<void> _deleteDriveFileQuietly(String fileId) async {
    if (fileId.isEmpty) return;
    try {
      await _driveService.deleteFile(fileId);
    } catch (e) {
      // Abaikan; file mungkin sudah terhapus manual.
      debugPrint('[RevisitService] hapus file Drive $fileId gagal: $e');
    }
  }

  void _throwIfError(dynamic response) {
    if (response is Map && response['ok'] != true) {
      throw Exception(response['error']?.toString() ?? 'Gagal menyimpan');
    }
  }
}
