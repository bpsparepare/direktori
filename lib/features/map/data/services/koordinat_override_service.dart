import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/supabase_config.dart';

/// Hasil operasi override koordinat.
class KoordinatOverrideResult {
  final bool ok;
  final String? error;

  const KoordinatOverrideResult(this.ok, this.error);
}

/// Menyimpan/menghapus koreksi posisi marker ke tabel terpisah
/// (se2026_koordinat_override) lewat RPC. Data ini tidak ikut tertimpa saat
/// se2026_keterangan_umum di-import ulang.
class KoordinatOverrideService {
  final SupabaseClient _client = SupabaseConfig.client;

  Future<KoordinatOverrideResult> upsert({
    required String assignmentId,
    required double latitude,
    required double longitude,
    String? note,
  }) async {
    try {
      final resp = await _client.rpc(
        'upsert_koordinat_override',
        params: {
          'p_assignment_id': assignmentId,
          'p_latitude': latitude,
          'p_longitude': longitude,
          'p_note': note,
        },
      );
      return _parse(resp);
    } catch (e) {
      return KoordinatOverrideResult(false, e.toString());
    }
  }

  /// Hapus override → marker kembali ke posisi asli hasil import.
  Future<KoordinatOverrideResult> reset(String assignmentId) async {
    try {
      final resp = await _client.rpc(
        'delete_koordinat_override',
        params: {'p_assignment_id': assignmentId},
      );
      return _parse(resp);
    } catch (e) {
      return KoordinatOverrideResult(false, e.toString());
    }
  }

  KoordinatOverrideResult _parse(dynamic resp) {
    if (resp is Map) {
      final ok = resp['ok'] == true;
      return KoordinatOverrideResult(ok, resp['error']?.toString());
    }
    return const KoordinatOverrideResult(false, 'Respons tidak valid');
  }
}
