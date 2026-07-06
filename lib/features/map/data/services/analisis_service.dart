import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/supabase_config.dart';
import '../../../../core/utils/debug_monitor.dart';
import '../models/status_alias_stat.dart';

/// Service untuk tab "Analisis" (khusus admin).
///
/// Sumber data: RPC public.get_se2026_status_alias_stats yang mengagregasi
/// jumlah baris se2026_keterangan_umum per assignment_status_alias. RPC
/// membatasi akses ke role admin, sehingga non-admin menerima daftar kosong.
class AnalisisService {
  final SupabaseClient _client = SupabaseConfig.client;

  Future<List<StatusAliasStat>> fetchStatusAliasStats() async {
    final response = await _client.rpc('get_se2026_status_alias_stats');
    DebugMonitor().logUsage('get_se2026_status_alias_stats', 'RPC', response);
    if (response is! List) return [];
    return response
        .whereType<Map<String, dynamic>>()
        .map(StatusAliasStat.fromJson)
        .toList();
  }

  /// Label kode_bang. Kode di luar daftar ini ditampilkan apa adanya,
  /// NULL/kosong menjadi "Tidak Diketahui" (lihat _mapKodeBang).
  static const Map<String, String> kodeBangLabels = {
    '1': 'Bangunan Khusus Usaha',
    '2': 'Bangunan Campuran',
    '3': 'Bangunan Tempat Tinggal',
    '4': 'Tempat Ibadah, Kantor Organisasi',
    '5': 'Kantor Pemerintah, Kedutaan/Konsulat',
    '6': 'Bangunan Lainnya yang Tidak Tercakup',
    '7': 'Virtual Office (VO)',
    '8': 'Panti Asuhan/Jompo, Lapas, Barak Militer',
    '9': 'Non Respon',
  };

  Future<List<StatusAliasStat>> fetchKodeBangStats() async {
    final response = await _client.rpc('get_se2026_kode_bang_stats');
    DebugMonitor().logUsage('get_se2026_kode_bang_stats', 'RPC', response);
    if (response is! List) return [];
    return response.whereType<Map<String, dynamic>>().map((json) {
      final raw = json['kode_bang'];
      final code = raw?.toString().trim() ?? '';
      final label = code.isEmpty
          ? 'Tidak Diketahui'
          : kodeBangLabels[code] ?? 'Kode $code';
      final rawJumlah = json['jumlah'];
      final jumlah = rawJumlah is num
          ? rawJumlah.toInt()
          : int.tryParse(rawJumlah?.toString() ?? '') ?? 0;
      return StatusAliasStat(alias: label, jumlah: jumlah);
    }).toList();
  }

  static String _kodeBangLabel(dynamic raw) {
    final code = raw?.toString().trim() ?? '';
    if (code.isEmpty) return 'Tidak Diketahui';
    return kodeBangLabels[code] ?? 'Kode $code';
  }

  /// Statistik silang Status Assignment × Kode Bangunan, dikelompokkan per
  /// status (urut jumlah terbesar). Rincian kode_bang di dalam tiap status
  /// juga urut jumlah terbesar.
  Future<List<StatusKodeBangGroup>> fetchStatusKodeBangStats() {
    return _fetchKodeBangPivot(
      'get_se2026_status_kode_bang_stats',
      groupKey: (json) => (json['status_text'] ?? json['assignment_status_alias'])
          ?.toString()
          .trim(),
    );
  }

  /// Statistik silang Petugas × Kode Bangunan. Petugas = pencacah (ppl_id) di
  /// se2026_wilayah_tugas, dicocokkan via wilayah 16 digit; nama dari users.
  Future<List<StatusKodeBangGroup>> fetchPetugasKodeBangStats() {
    return _fetchKodeBangPivot(
      'get_se2026_petugas_kode_bang_stats',
      groupKey: (json) => json['petugas']?.toString().trim(),
    );
  }

  /// Ambil hasil RPC pivot (kolom pengelompokan × kode_bang × jumlah) lalu
  /// susun menjadi grup per nilai [groupKey] dengan rincian kode_bang.
  Future<List<StatusKodeBangGroup>> _fetchKodeBangPivot(
    String rpcName, {
    required String? Function(Map<String, dynamic>) groupKey,
  }) async {
    final response = await _client.rpc(rpcName);
    DebugMonitor().logUsage(rpcName, 'RPC', response);
    if (response is! List) return [];

    // Pertahankan urutan sesuai kemunculan pertama (RPC sudah urut).
    final ordered = <String>[];
    final grouped = <String, List<StatusAliasStat>>{};
    for (final json in response.whereType<Map<String, dynamic>>()) {
      final key = groupKey(json) ?? '';
      final label = key.isEmpty ? 'Tidak Diketahui' : key;
      final rawJumlah = json['jumlah'];
      final jumlah = rawJumlah is num
          ? rawJumlah.toInt()
          : int.tryParse(rawJumlah?.toString() ?? '') ?? 0;
      grouped.putIfAbsent(label, () {
        ordered.add(label);
        return [];
      }).add(StatusAliasStat(
        alias: _kodeBangLabel(json['kode_bang']),
        jumlah: jumlah,
      ));
    }

    final groups = ordered.map((label) {
      final breakdown = grouped[label]!;
      final total = breakdown.fold(0, (sum, s) => sum + s.jumlah);
      return StatusKodeBangGroup(
        status: label,
        total: total,
        breakdown: breakdown,
      );
    }).toList()
      ..sort((a, b) => b.total.compareTo(a.total));

    return groups;
  }
}
