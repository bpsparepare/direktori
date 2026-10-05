import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/supabase_config.dart';
import '../models/tindak_lanjut_item.dart';

/// Service fitur "Submit" (daftar assignment belum submit + tanda perlu
/// dihapus). Semua akses lewat RPC security definer — lihat
/// supabase/migrations/20260913120000_tindak_lanjut_hapus.sql. Filter role
/// (admin semua, pengawas timnya, pendata wilayahnya) dilakukan di server.
class TindakLanjutService {
  final SupabaseClient _client = SupabaseConfig.client;

  /// Ukuran halaman = batas max-rows PostgREST (default Supabase 1000).
  static const int _pageSize = 1000;

  /// Ambil SEMUA baris dengan paging (.range) karena respons RPC dibatasi
  /// max-rows. Urutan RPC stabil (kunci akhir assignment_id) sehingga halaman
  /// tidak saling tumpang tindih.
  Future<List<TindakLanjutItem>> fetchList() async {
    try {
      final items = <TindakLanjutItem>[];
      for (var offset = 0; ; offset += _pageSize) {
        final response = await _client
            .rpc('get_tindak_lanjut')
            .range(offset, offset + _pageSize - 1);
        if (response is! List) break;
        items.addAll(
          response.whereType<Map>().map(
            (item) =>
                TindakLanjutItem.fromJson(Map<String, dynamic>.from(item)),
          ),
        );
        if (response.length < _pageSize) break;
      }
      return items;
    } catch (e, stack) {
      debugPrint('[TindakLanjutService] fetchList ERROR: $e');
      debugPrint('[TindakLanjutService] STACK: $stack');
      rethrow;
    }
  }

  Future<void> tandaiHapus(String assignmentId, {String? alasan}) async {
    final response = await _client.rpc(
      'set_tindak_lanjut_hapus',
      params: {'p_assignment_id': assignmentId, 'p_alasan': alasan},
    );
    _throwIfError(response);
  }

  Future<void> batalkanHapus(String assignmentId) async {
    final response = await _client.rpc(
      'unset_tindak_lanjut_hapus',
      params: {'p_assignment_id': assignmentId},
    );
    _throwIfError(response);
  }

  void _throwIfError(dynamic response) {
    if (response is Map && response['ok'] != true) {
      throw Exception(response['error']?.toString() ?? 'Gagal menyimpan');
    }
  }
}
