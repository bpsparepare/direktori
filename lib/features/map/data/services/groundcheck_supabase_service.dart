import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/config/supabase_config.dart';
import '../../presentation/pages/groundcheck_page.dart';
import '../../domain/entities/place.dart';
import 'package:latlong2/latlong.dart';

class GroundcheckSupabaseService {
  final SupabaseClient _client = SupabaseConfig.client;
  static const String _tableName = 'groundcheck_list';

  Future<List<GroundcheckRecord>> fetchRecords() async {
    try {
      const int batchSize = 1000;
      int start = 0;
      final List<GroundcheckRecord> all = [];
      while (true) {
        final batch = await _client
            .from(_tableName)
            .select()
            .order('idsbr', ascending: true)
            .range(start, start + batchSize - 1);
        if (batch is List && batch.isNotEmpty) {
          all.addAll(
            batch.map((json) => GroundcheckRecord.fromJson(json)).toList(),
          );
          if (batch.length < batchSize) break;
          start += batchSize;
        } else {
          break;
        }
      }
      return all;
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

  Future<List<GroundcheckRecord>> searchRecords(String query) async {
    try {
      final response = await _client
          .from(_tableName)
          .select()
          .or('nama_usaha.ilike.%$query%,idsbr.ilike.%$query%')
          .limit(20);

      if (response is List) {
        return response
            .map((json) => GroundcheckRecord.fromJson(json))
            .toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<String?> fetchCurrentUserId() async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) return null;

      final response = await _client
          .from('users')
          .select('id')
          .eq('auth_uid', user.id)
          .maybeSingle();

      if (response != null && response['id'] != null) {
        return response['id'].toString();
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<void> updateRecord(GroundcheckRecord record) async {
    try {
      final data = {
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
      };

      if (record.userId != null) {
        data['user_id'] = record.userId!;
      }

      await _client.from(_tableName).upsert(data, onConflict: 'idsbr');
    } catch (e) {
      // Handle error
    }
  }

  Future<bool> updateCoordinates({
    required String idsbr,
    required double latitude,
    required double longitude,
  }) async {
    try {
      await _client
          .from(_tableName)
          .update({
            'latitude': latitude.toString(),
            'longitude': longitude.toString(),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('idsbr', idsbr);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> getRecordByIdsbr(String idsbr) async {
    try {
      final row = await _client
          .from(_tableName)
          .select(
            'idsbr,nama_usaha,latitude,longitude,perusahaan_id,gcs_result',
          )
          .eq('idsbr', idsbr)
          .maybeSingle();
      if (row is Map<String, dynamic>) return row;
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> updateGcsResult(String idsbr, String hasilGc) async {
    try {
      await _client
          .from(_tableName)
          .update({
            'gcs_result': hasilGc,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('idsbr', idsbr);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<List<Place>> fetchPlaces() async {
    try {
      const int batchSize = 1000;
      int start = 0;
      final List<Place> results = [];
      while (true) {
        final batch = await _client
            .from(_tableName)
            .select('''
              idsbr,
              nama_usaha,
              alamat_usaha,
              kode_wilayah,
              status_perusahaan,
              skala_usaha,
              gcs_result,
              latitude,
              longitude
              ''')
            .order('idsbr', ascending: true)
            .range(start, start + batchSize - 1);
        if (batch is! List || batch.isEmpty) break;
        for (final item in batch) {
          if (item is! Map<String, dynamic>) continue;
          final lat = _parseDouble(item['latitude']);
          final lon = _parseDouble(item['longitude']);
          if (lat == null || lon == null) continue;
          final idsbr = (item['idsbr'] ?? '').toString();
          if (idsbr.isEmpty) continue;
          final name = (item['nama_usaha'] ?? '').toString();
          final alamat = (item['alamat_usaha'] ?? '').toString();
          final kode = (item['kode_wilayah'] ?? '').toString();
          final status = (item['status_perusahaan'] ?? '').toString();
          final skala = (item['skala_usaha'] ?? '').toString();
          final gcs = (item['gcs_result'] ?? '').toString();
          final descParts = <String>[];
          if (kode.isNotEmpty) {
            descParts.add('Kode wilayah: $kode');
          }
          if (status.isNotEmpty) {
            descParts.add('Status: $status');
          }
          if (skala.isNotEmpty) {
            descParts.add('Skala: $skala');
          }
          if (gcs.isNotEmpty) {
            descParts.add('GCS: $gcs');
          }
          final desc = descParts.join(' | ');
          results.add(
            Place(
              id: 'gc:$idsbr',
              name: name.isNotEmpty ? name : idsbr,
              description: desc,
              position: LatLng(lat, lon),
              gcsResult: gcs,
              address: alamat,
              statusPerusahaan: status,
            ),
          );
        }
        if (batch.length < batchSize) break;
        start += batchSize;
      }
      return results;
    } catch (_) {
      return [];
    }
  }

  double? _parseDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }
}
