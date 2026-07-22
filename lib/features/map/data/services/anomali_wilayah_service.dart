import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/supabase_config.dart';
import '../models/anggota_profesi_item.dart';
import '../models/keluarga_aset_item.dart';
import '../models/usaha_kbli_item.dart';
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

  /// Daftar usaha + KBLI/keg_utama/produk untuk pengecekan salah KBLI.
  /// Lihat get_usaha_kbli().
  Future<List<UsahaKbliItem>> fetchUsahaKbli({
    String? query,
    String? kategori,
    String? petugas,
    int limit = 200,
    int offset = 0,
  }) async {
    final response = await _client.rpc(
      'get_usaha_kbli',
      params: {
        'p_query': query,
        'p_kategori': kategori,
        'p_petugas': petugas,
        'p_limit': limit,
        'p_offset': offset,
      },
    );
    if (response is! List) return [];
    return response
        .map((e) => UsahaKbliItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Opsi filter lengkap: {'kategori': [...], 'petugas': [...]}.
  Future<Map<String, List<String>>> fetchKbliFilterOptions() async {
    final response =
        await _client.rpc('get_usaha_kbli_filter_options');
    final result = <String, List<String>>{'kategori': [], 'petugas': []};
    if (response is List) {
      for (final row in response) {
        final m = row as Map<String, dynamic>;
        final tipe = (m['tipe'] ?? '').toString();
        final nilai = (m['nilai'] ?? '').toString();
        if (nilai.isEmpty) continue;
        (result[tipe] ??= []).add(nilai);
      }
    }
    return result;
  }

  /// Tandai usaha sebagai anomali UW3 (Salah Penentuan KBLI) + catatan admin.
  /// Lihat insert_anomali_kbli().
  Future<void> insertAnomaliKbli({
    required String assignmentId,
    required int noUsaha,
    required String komentar,
  }) async {
    await _client.rpc('insert_anomali_kbli', params: {
      'p_assignment_id': assignmentId,
      'p_no_usaha': noUsaha,
      'p_komentar': komentar,
    });
  }

  /// Tandai banyak usaha sebagai UW3 sekaligus dengan catatan sama.
  Future<int> insertAnomaliKbliBatch({
    required List<UsahaKbliItem> items,
    required String komentar,
  }) async {
    final payload = items
        .map((e) => {'assignment_id': e.assignmentId, 'no_usaha': e.noUsaha})
        .toList();
    final response = await _client.rpc('insert_anomali_kbli_batch', params: {
      'p_items': payload,
      'p_komentar': komentar,
    });
    if (response is int) return response;
    return int.tryParse(response?.toString() ?? '') ?? 0;
  }

  // ─── Profesi (UW4) ─────────────────────────────────────────────
  Future<List<AnggotaProfesiItem>> fetchAnggotaProfesi({
    String? query,
    String? petugas,
    String? profesi,
    bool tanpaUsaha = false,
    int limit = 200,
    int offset = 0,
  }) async {
    final response = await _client.rpc('get_anggota_profesi', params: {
      'p_query': query,
      'p_petugas': petugas,
      'p_profesi': profesi,
      'p_tanpa_usaha': tanpaUsaha,
      'p_limit': limit,
      'p_offset': offset,
    });
    if (response is! List) return [];
    return response
        .map((e) => AnggotaProfesiItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, List<String>>> fetchProfesiFilterOptions() async {
    final response =
        await _client.rpc('get_anggota_profesi_filter_options');
    final result = <String, List<String>>{'profesi': [], 'petugas': []};
    if (response is List) {
      for (final row in response) {
        final m = row as Map<String, dynamic>;
        final tipe = (m['tipe'] ?? '').toString();
        final nilai = (m['nilai'] ?? '').toString();
        if (nilai.isEmpty) continue;
        (result[tipe] ??= []).add(nilai);
      }
    }
    return result;
  }

  Future<void> insertAnomaliProfesi({
    required String assignmentId,
    required int noUrut,
    required String profesiNama,
    required String komentar,
  }) async {
    await _client.rpc('insert_anomali_profesi', params: {
      'p_assignment_id': assignmentId,
      'p_no_urut': noUrut,
      'p_profesi_nama': profesiNama,
      'p_komentar': komentar,
    });
  }

  Future<int> insertAnomaliProfesiBatch({
    required List<Map<String, dynamic>> items,
    required String komentar,
  }) async {
    final response = await _client.rpc('insert_anomali_profesi_batch', params: {
      'p_items': items,
      'p_komentar': komentar,
    });
    if (response is int) return response;
    return int.tryParse(response?.toString() ?? '') ?? 0;
  }

  // ─── Aset (UW5) ────────────────────────────────────────────────
  Future<List<KeluargaAsetItem>> fetchKeluargaAset({
    String? query,
    String? petugas,
    bool hanyaAnomali = false,
    String? aset,
    Map<String, int> thresholds = const {},
    int limit = 200,
    int offset = 0,
  }) async {
    final response = await _client.rpc('get_keluarga_aset', params: {
      'p_query': query,
      'p_petugas': petugas,
      'p_hanya_anomali': hanyaAnomali,
      'p_aset': aset,
      'p_thresholds': thresholds,
      'p_limit': limit,
      'p_offset': offset,
    });
    if (response is! List) return [];
    return response
        .map((e) => KeluargaAsetItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<String>> fetchAsetPetugasOptions() async {
    final response = await _client.rpc('get_keluarga_aset_filter_options');
    final list = <String>[];
    if (response is List) {
      for (final row in response) {
        final m = row as Map<String, dynamic>;
        final nilai = (m['nilai'] ?? '').toString();
        if (nilai.isNotEmpty) list.add(nilai);
      }
    }
    return list;
  }

  Future<void> insertAnomaliAset({
    required String assignmentId,
    required String komentar,
    Map<String, int> thresholds = const {},
  }) async {
    await _client.rpc('insert_anomali_aset', params: {
      'p_assignment_id': assignmentId,
      'p_komentar': komentar,
      'p_thresholds': thresholds,
    });
  }

  Future<int> insertAnomaliAsetBatch({
    required List<Map<String, dynamic>> items,
    required String komentar,
    Map<String, int> thresholds = const {},
  }) async {
    final response = await _client.rpc('insert_anomali_aset_batch', params: {
      'p_items': items,
      'p_komentar': komentar,
      'p_thresholds': thresholds,
    });
    if (response is int) return response;
    return int.tryParse(response?.toString() ?? '') ?? 0;
  }
}

