import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/supabase_config.dart';
import '../models/anomali_item.dart';

class AnomalyService {
  final SupabaseClient _client = SupabaseConfig.client;

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
