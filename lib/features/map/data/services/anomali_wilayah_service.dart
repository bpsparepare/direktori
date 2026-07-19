import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/supabase_config.dart';
import '../models/usaha_pendapatan_item.dart';

/// Impor anomali berbasis wilayah (dari data lapangan), kategori pertama:
/// pengecekan pendapatan usaha ekstrem. Khusus admin.
class AnomaliWilayahService {
  final SupabaseClient _client = SupabaseConfig.client;

  /// Ambil usaha dengan total_pendapatan >= batas ('tinggi') atau <= batas
  /// ('rendah'). Lihat get_usaha_pendapatan_ekstrem().
  Future<List<UsahaPendapatanItem>> fetchUsahaPendapatanEkstrem({
    required String jenis,
    required num batas,
    int limit = 300,
  }) async {
    final response = await _client.rpc(
      'get_usaha_pendapatan_ekstrem',
      params: {'p_jenis': jenis, 'p_batas': batas, 'p_limit': limit},
    );
    if (response is! List) return [];
    return response
        .map((e) => UsahaPendapatanItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Masukkan usaha terpilih ke anomali_pusat_temuan (UW1/UW2). Kembalikan
  /// jumlah baris diproses. Lihat insert_anomali_usaha_pendapatan().
  Future<int> insertAnomaliUsahaPendapatan({
    required String jenis,
    required List<UsahaPendapatanItem> items,
  }) async {
    final payload = items
        .map((e) => {'assignment_id': e.assignmentId, 'no_usaha': e.noUsaha})
        .toList();
    final response = await _client.rpc(
      'insert_anomali_usaha_pendapatan',
      params: {'p_jenis': jenis, 'p_items': payload},
    );
    if (response is int) return response;
    return int.tryParse(response?.toString() ?? '') ?? 0;
  }
}
