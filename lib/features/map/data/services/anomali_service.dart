import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/supabase_config.dart';
import '../models/anomali_gabungan_item.dart';
import '../models/anomali_item.dart';
import '../models/anomali_progress_item.dart';
import '../models/anomali_pusat_item.dart';
import '../models/keterangan_pusat_item.dart';

class AnomalyService {
  final SupabaseClient _client = SupabaseConfig.client;

  /// List gabungan sumber 'kualitas' (wilayah) + 'pusat_baru' (excel Fasih),
  /// lihat get_anomali_gabungan() di
  /// supabase/migrations/20260703130000_anomali_gabungan_kategori_besar_rincian.sql.
  Future<List<AnomaliGabunganItem>> fetchAnomaliGabungan({
    String? sumber,
    String? kategoriBesar,
    String? kategoriKode,
    String? status,
    String? pengawasId,
    String? petugasId,
    int limit = 500,
    int offset = 0,
  }) async {
    final params = <String, dynamic>{
      'p_limit': limit,
      'p_offset': offset,
    };
    if (sumber != null) params['p_sumber'] = sumber;
    if (kategoriBesar != null) params['p_kategori_besar'] = kategoriBesar;
    if (kategoriKode != null) params['p_kategori_kode'] = kategoriKode;
    if (status != null) params['p_status'] = status;
    if (pengawasId != null) params['p_pengawas_id'] = pengawasId;
    if (petugasId != null) params['p_petugas_id'] = petugasId;

    try {
      final response =
          await _client.rpc('get_anomali_gabungan', params: params);
      if (response is! List) return [];
      return response
          .map((item) =>
              AnomaliGabunganItem.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e, stack) {
      debugPrint('[AnomalyService] fetchAnomaliGabungan ERROR: $e');
      debugPrint('[AnomalyService] STACK: $stack');
      rethrow;
    }
  }

  /// Respons petugas gabungan (dipakai sumber 'kualitas' maupun
  /// 'pusat_baru'), 2 pilihan: 'perbaikan' atau 'konfirmasi_valid'
  /// (keterangan wajib utk konfirmasi_valid). Multi-petugas per kasus.
  /// Lihat upsert_anomali_respons() di
  /// supabase/migrations/20260703150000_anomali_respons_gabungan.sql.
  Future<void> upsertAnomaliRespons({
    required String sumber,
    required String scope,
    required String assignmentId,
    required String kategoriKode,
    required String jenisRespons,
    String namaSubjek = '',
    String? keterangan,
  }) async {
    await _client.rpc('upsert_anomali_respons', params: {
      'p_sumber': sumber,
      'p_scope': scope,
      'p_assignment_id': assignmentId,
      'p_kategori_kode': kategoriKode,
      'p_jenis_respons': jenisRespons,
      'p_nama_subjek': namaSubjek,
      'p_keterangan': keterangan,
    });
  }

  /// Progres pemeriksaan anomali pusat untuk grafik donut. Breakdown otomatis
  /// sesuai role (per PML utk admin, per PPL utk pengawas, diri sendiri utk
  /// pendata). Isi p_pengawas_id/p_petugas_id untuk drill-down.
  /// Lihat get_anomali_pusat_progress() di
  /// supabase/migrations/20260707150000_anomali_pusat_progress.sql.
  Future<List<AnomaliProgressItem>> fetchAnomaliProgress({
    String? pengawasId,
    String? petugasId,
  }) async {
    final params = <String, dynamic>{};
    if (pengawasId != null) params['p_pengawas_id'] = pengawasId;
    if (petugasId != null) params['p_petugas_id'] = petugasId;

    final response =
        await _client.rpc('get_anomali_pusat_progress', params: params);
    if (response is! List) return [];
    return response
        .map((e) =>
            AnomaliProgressItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Jumlah notifikasi konfirmasi (kasus di wilayah petugas/PML yang ada
  /// 'konfirmasi' dari admin dan belum ditanggapi). 0 untuk admin.
  Future<int> fetchKonfirmasiCount() async {
    final response = await _client.rpc('get_anomali_konfirmasi_count');
    if (response is int) return response;
    return int.tryParse(response?.toString() ?? '') ?? 0;
  }

  /// Set / batalkan verifikasi PML atas satu kasus anomali pusat.
  /// Hanya berhasil untuk role pengawas/admin (divalidasi di server).
  Future<void> setVerifikasi({
    required String scope,
    required String assignmentId,
    required String namaSubjek,
    required String kategoriKode,
    required bool verified,
    String? catatan,
  }) async {
    await _client.rpc('set_anomali_pusat_verifikasi', params: {
      'p_scope': scope,
      'p_assignment_id': assignmentId,
      'p_nama_subjek': namaSubjek,
      'p_kategori_kode': kategoriKode,
      'p_verified': verified,
      'p_catatan': catatan,
    });
  }

  /// Thread multi-petugas untuk satu kasus (baik 'kualitas' maupun
  /// 'pusat_baru').
  Future<List<KeteranganPusatItem>> fetchAnomaliRespons({
    required String sumber,
    required String scope,
    required String assignmentId,
    required String kategoriKode,
    String namaSubjek = '',
  }) async {
    final response = await _client.rpc('get_anomali_respons', params: {
      'p_sumber': sumber,
      'p_scope': scope,
      'p_assignment_id': assignmentId,
      'p_kategori_kode': kategoriKode,
      'p_nama_subjek': namaSubjek,
    });
    if (response is! List) return [];
    return response
        .map((e) => KeteranganPusatItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<AnomalyItem>> fetchAnomalyWilayah({
    String? kategori,
    String? status,
    String? pengawasId,
    String? petugasId,
    int limit = 500,
    int offset = 0,
  }) async {
    final params = <String, dynamic>{
      'p_limit': limit,
      'p_offset': offset,
    };
    if (kategori != null) params['p_kategori'] = kategori;
    if (status != null) params['p_status'] = status;
    if (pengawasId != null) params['p_pengawas_id'] = pengawasId;
    if (petugasId != null) params['p_petugas_id'] = petugasId;

    debugPrint('[AnomalyService] fetchAnomalyWilayah params: $params');

    try {
      final response = await _client.rpc('get_anomali_wilayah', params: params);

      debugPrint('[AnomalyService] response type: ${response.runtimeType}');
      debugPrint('[AnomalyService] response: $response');

      if (response is! List) return [];
      return response
          .map((item) => AnomalyItem.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e, stack) {
      debugPrint('[AnomalyService] ERROR: $e');
      debugPrint('[AnomalyService] STACK: $stack');
      rethrow;
    }
  }

  Future<List<AnomaliPusatItem>> fetchAnomalyPusat({
    String? petugasId,
    String? pengawasId,
    String? kategori,
    String? status,
    int limit = 500,
    int offset = 0,
  }) async {
    final params = <String, dynamic>{
      'p_limit': limit,
      'p_offset': offset,
    };
    if (petugasId != null) params['p_petugas_id'] = petugasId;
    if (pengawasId != null) params['p_pengawas_id'] = pengawasId;
    if (kategori != null) params['p_kategori'] = kategori;
    if (status != null) params['p_status'] = status;

    debugPrint('[AnomalyService] fetchAnomalyPusat params: $params');

    try {
      final response = await _client.rpc('get_anomali_pusat', params: params);
      debugPrint('[AnomalyService] pusat response type: ${response.runtimeType}');
      if (response is! List) return [];
      return response
          .map((item) => AnomaliPusatItem.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e, stack) {
      debugPrint('[AnomalyService] ERROR pusat: $e');
      debugPrint('[AnomalyService] STACK: $stack');
      rethrow;
    }
  }

  /// Ambil set key (assignment_id|nama_anomali) yang sudah diisi keterangan
  /// oleh user yang sedang login. RLS otomatis filter per petugas.
  Future<Set<String>> fetchMyKeteranganKeys() async {
    try {
      final response = await _client
          .from('se2026_anomali_pusat_keterangan')
          .select('assignment_id, nama_anomali')
          .neq('keterangan', '');
      return {
        for (final row in response)
          '${row['assignment_id']}|${row['nama_anomali']}'
      };
    } catch (e) {
      debugPrint('[AnomalyService] fetchMyKeteranganKeys ERROR: $e');
      return {};
    }
  }

  Future<List<KeteranganPusatItem>> fetchKeteranganPusat({
    required String assignmentId,
    required String namaAnomali,
  }) async {
    try {
      final response = await _client.rpc('get_anomali_pusat_keterangan', params: {
        'p_assignment_id': assignmentId,
        'p_nama_anomali': namaAnomali,
      });
      if (response is! List) return [];
      return response
          .map((e) => KeteranganPusatItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[AnomalyService] fetchKeteranganPusat ERROR: $e');
      rethrow;
    }
  }

  Future<void> upsertKeteranganPusat({
    required String assignmentId,
    required String namaAnomali,
    required String keterangan,
  }) async {
    await _client.rpc('upsert_anomali_pusat_keterangan', params: {
      'p_assignment_id': assignmentId,
      'p_nama_anomali': namaAnomali,
      'p_keterangan': keterangan,
    });
  }

  Future<int?> upsertTindakLanjut({
    required String assignmentId,
    required String kategori,
    required int noAnomali,
    required String statusTindakLanjut,
    String? catatanPetugas,
  }) async {
    final response = await _client.rpc(
      'upsert_anomali_tindak_lanjut',
      params: {
        'p_assignment_id': assignmentId,
        'p_kategori': kategori,
        'p_no_anomali': noAnomali,
        'p_status_tindak_lanjut': statusTindakLanjut,
        'p_catatan_petugas': catatanPetugas,
      },
    );

    if (response is int) return response;
    return null;
  }
}
