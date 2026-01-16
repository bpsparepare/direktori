import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/config/supabase_config.dart';
import '../../presentation/pages/groundcheck_page.dart';

class GroundcheckSupabaseService {
  final SupabaseClient _client = SupabaseConfig.client;
  static const String _tableName = 'groundcheck_list';

  Future<List<GroundcheckRecord>> fetchRecords() async {
    try {
      final response = await _client
          .from(_tableName)
          .select()
          .order('idsbr', ascending: true);

      final List<dynamic> data = response as List<dynamic>;
      return data.map((json) => GroundcheckRecord.fromJson(json)).toList();
    } catch (e) {
      // If table doesn't exist or empty, return empty list
      return [];
    }
  }

  Future<void> importFromAsset(String assetPath) async {
    try {
      final raw = await rootBundle.loadString(assetPath);
      final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;

      // Batch insert/upsert
      // Supabase limits batch size, so chunk it
      const int batchSize = 100;
      for (var i = 0; i < decoded.length; i += batchSize) {
        final end = (i + batchSize < decoded.length)
            ? i + batchSize
            : decoded.length;
        final chunk = decoded.sublist(i, end);

        final payload = chunk
            .map(
              (e) => {
                'idsbr': e['idsbr']?.toString() ?? '',
                'nama_usaha': e['nama_usaha']?.toString() ?? '',
                'alamat_usaha': e['alamat_usaha']?.toString() ?? '',
                'kode_wilayah': e['kode_wilayah']?.toString() ?? '',
                'status_perusahaan': e['status_perusahaan']?.toString() ?? '',
                'skala_usaha': e['skala_usaha']?.toString() ?? '',
                'gcs_result': e['gcs_result']?.toString() ?? '',
                'latitude': e['latitude']?.toString() ?? '',
                'longitude': e['longitude']?.toString() ?? '',
                'perusahaan_id': (e['perusahaan_id'] ?? e['idsbr'] ?? '')
                    .toString(),
                'updated_at': DateTime.now().toIso8601String(),
              },
            )
            .toList();

        await _client.from(_tableName).upsert(payload, onConflict: 'idsbr');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> updateRecord(GroundcheckRecord record) async {
    try {
      await _client.from(_tableName).upsert({
        'idsbr': record.idsbr,
        'nama_usaha': record.namaUsaha,
        'alamat_usaha': record.alamatUsaha,
        'kode_wilayah': record.kodeWilayah,
        'status_perusahaan': record.statusPerusahaan,
        'skala_usaha': record.skalaUsaha,
        'gcs_result': record.gcsResult,
        'latitude': record.latitude,
        'longitude': record.longitude,
        'perusahaan_id': record.perusahaanId,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'idsbr');
    } catch (e) {
      // Handle error
    }
  }
}
