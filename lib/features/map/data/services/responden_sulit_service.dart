import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/supabase_config.dart';
import '../models/responden_sulit_item.dart';

/// Service fitur "Responden Sulit". Semua akses lewat RPC security definer
/// (lihat supabase/migrations/20260707150000_responden_sulit.sql) yang sudah
/// menerapkan filter role: pendata melihat wilayahnya, pengawas melihat tim
/// PPL-nya, admin melihat semua.
class RespondenSulitService {
  final SupabaseClient _client = SupabaseConfig.client;

  Future<List<RespondenSulitItem>> fetchList({
    int limit = 500,
    int offset = 0,
  }) async {
    try {
      final response = await _client.rpc('get_responden_sulit', params: {
        'p_limit': limit,
        'p_offset': offset,
      });
      if (response is! List) return [];
      return response
          .whereType<Map>()
          .map((item) =>
              RespondenSulitItem.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } catch (e, stack) {
      debugPrint('[RespondenSulitService] fetchList ERROR: $e');
      debugPrint('[RespondenSulitService] STACK: $stack');
      rethrow;
    }
  }

  /// Insert (id null) atau update. Mengembalikan id entri.
  Future<String> upsert({
    String? id,
    String? kodeWilayah,
    required String nama,
    String? alamat,
    String? penjelasan,
    String? tindakLanjut,
  }) async {
    final response = await _client.rpc('upsert_responden_sulit', params: {
      'p_id': id,
      'p_kode_wilayah': kodeWilayah,
      'p_nama': nama,
      'p_alamat': alamat,
      'p_penjelasan': penjelasan,
      'p_tindak_lanjut': tindakLanjut,
    });
    return response?.toString() ?? '';
  }

  Future<void> delete(String id) async {
    await _client.rpc('delete_responden_sulit', params: {'p_id': id});
  }
}
