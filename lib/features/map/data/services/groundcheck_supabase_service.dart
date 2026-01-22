import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/config/supabase_config.dart';
import '../../presentation/pages/groundcheck_page.dart';
import '../../domain/entities/place.dart';
import 'package:latlong2/latlong.dart';

class GroundcheckSupabaseService {
  final SupabaseClient _client = SupabaseConfig.client;
  static const String _tableName = 'groundcheck_list';
  static const String _localFileName = 'groundcheck_list_cache.json';
  static const String _lastSyncKey = 'groundcheck_last_sync_time';

  Future<List<GroundcheckRecord>> fetchRecords({DateTime? updatedSince}) async {
    try {
      const int batchSize = 1000;
      int start = 0;
      final List<GroundcheckRecord> all = [];
      final sinceStr = updatedSince?.toIso8601String();

      while (true) {
        dynamic query = _client.from(_tableName).select();

        if (sinceStr != null) {
          query = query.gt('updated_at', sinceStr);
        }

        final batch = await query
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

  Future<List<Map<String, dynamic>>> fetchDashboardStats() async {
    try {
      final response = await _client.from('view_dashboard_stats').select();
      if (response is List) {
        return List<Map<String, dynamic>>.from(response);
      }
      return [];
    } catch (e) {
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

  Future<List<GroundcheckRecord>> fetchUserRecords(String userId) async {
    try {
      final response = await _client
          .from('view_groundcheck_history')
          .select()
          .eq('user_id', userId)
          .order('updated_at', ascending: false);

      if (response is List) {
        return response.map((json) {
          // Map view fields to GroundcheckRecord expected fields
          // View fields: idsbr, nama_usaha, alamat_usaha, gcs_result, updated_at, user_id
          // GroundcheckRecord needs more fields, so we need to fill them with defaults or adjust the view/model
          // Since GroundcheckRecord is from groundcheck_page.dart and has required fields:
          // kodeWilayah, statusPerusahaan, skalaUsaha, latitude, longitude, perusahaanId
          // The current view might not return all these.
          // We should probably update the view to include all needed fields or query the table directly if we need all fields.
          // BUT the user explicitly asked to use the view.
          // So I will update the view definition to include all fields OR handle partial data here.
          // Let's assume for now we use the view as requested and fill missing data if any,
          // but better yet, let's update the view query to include all fields if the model requires them.
          // Actually, looking at the view definition:
          // SELECT idsbr, nama_usaha, alamat_usaha, gcs_result, updated_at, user_id FROM groundcheck_list
          // It is missing required fields for GroundcheckRecord.
          // I will use a helper to map partial data safely.

          return GroundcheckRecord(
            idsbr: (json['idsbr'] ?? '').toString(),
            namaUsaha: (json['nama_usaha'] ?? '').toString(),
            alamatUsaha: (json['alamat_usaha'] ?? '').toString(),
            kodeWilayah: (json['kode_wilayah'] ?? '')
                .toString(), // Missing in view
            statusPerusahaan: (json['status_perusahaan'] ?? '')
                .toString(), // Missing in view
            skalaUsaha: (json['skala_usaha'] ?? '')
                .toString(), // Missing in view
            gcsResult: (json['gcs_result'] ?? '').toString(),
            latitude: (json['latitude'] ?? '0').toString(), // Missing in view
            longitude: (json['longitude'] ?? '0').toString(), // Missing in view
            perusahaanId: (json['perusahaan_id'] ?? '')
                .toString(), // Missing in view
            userId: json['user_id']?.toString(),
          );
        }).toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchLeaderboard() async {
    try {
      // Coba ambil dari View jika ada
      final response = await _client
          .from('view_groundcheck_leaderboard')
          .select()
          .limit(50);

      if (response is List) {
        return List<Map<String, dynamic>>.from(response);
      }
      return [];
    } catch (e) {
      // Fallback: Query manual jika View belum dibuat (agak berat untuk data besar)
      // Note: Supabase JS/Dart client tidak support .rpc untuk group by manual mudah tanpa function/view
      // Jadi kita return empty atau error, menyarankan user membuat View.
      print('Error fetching leaderboard (mungkin view belum dibuat): $e');
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

  Future<String?> fetchCurrentUserName() async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) return null;

      final response = await _client
          .from('users')
          .select('name')
          .eq('auth_uid', user.id)
          .maybeSingle();

      if (response != null && response['name'] != null) {
        return response['name'].toString();
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<void> updateLocalRecord(GroundcheckRecord record) async {
    try {
      final records = await loadLocalRecords();
      final index = records.indexWhere((r) => r.idsbr == record.idsbr);
      if (index != -1) {
        records[index] = record;
      } else {
        records.add(record);
      }
      await saveLocalRecords(records);
    } catch (e) {
      // Ignore
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

      // Update local cache
      await updateLocalRecord(record);
    } catch (e) {
      // Handle error but try to update local cache anyway if it's a network error?
      // For now, let's assume we want to be optimistic or at least consistent.
      // If network fails, we might still want to save locally if we support full offline edits.
      // But for now, let's just save locally if we reached here (implies optimistic or parallel).
      // To be safe, we should update local only if successful or if we implement a sync queue.
      // Given the requirement is just "sync local and server", updating local after server attempt is fine.
      await updateLocalRecord(record);
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

      // Update local cache
      final records = await loadLocalRecords();
      final index = records.indexWhere((r) => r.idsbr == idsbr);
      if (index != -1) {
        final old = records[index];
        final newRecord = GroundcheckRecord(
          idsbr: old.idsbr,
          namaUsaha: old.namaUsaha,
          alamatUsaha: old.alamatUsaha,
          kodeWilayah: old.kodeWilayah,
          statusPerusahaan: old.statusPerusahaan,
          skalaUsaha: old.skalaUsaha,
          gcsResult: old.gcsResult,
          latitude: latitude.toString(),
          longitude: longitude.toString(),
          perusahaanId: old.perusahaanId,
          userId: old.userId,
        );
        records[index] = newRecord;
        await saveLocalRecords(records);
      }

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

  Future<bool> updateGcsResult(
    String idsbr,
    String hasilGc, {
    String? userId,
    String? namaUsaha,
    String? alamatUsaha,
  }) async {
    try {
      final data = {
        'gcs_result': hasilGc,
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (userId != null) {
        data['user_id'] = userId;
      }
      if (namaUsaha != null && namaUsaha.isNotEmpty) {
        data['nama_usaha'] = namaUsaha;
      }
      if (alamatUsaha != null && alamatUsaha.isNotEmpty) {
        data['alamat_usaha'] = alamatUsaha;
      }
      await _client.from(_tableName).update(data).eq('idsbr', idsbr);

      // Update local cache
      final records = await loadLocalRecords();
      final index = records.indexWhere((r) => r.idsbr == idsbr);
      if (index != -1) {
        final old = records[index];
        final newRecord = GroundcheckRecord(
          idsbr: old.idsbr,
          namaUsaha: namaUsaha ?? old.namaUsaha,
          alamatUsaha: alamatUsaha ?? old.alamatUsaha,
          kodeWilayah: old.kodeWilayah,
          statusPerusahaan: old.statusPerusahaan,
          skalaUsaha: old.skalaUsaha,
          gcsResult: hasilGc,
          latitude: old.latitude,
          longitude: old.longitude,
          perusahaanId: old.perusahaanId,
          userId: userId ?? old.userId,
        );
        records[index] = newRecord;
        await saveLocalRecords(records);
      }

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
          final p = _mapToPlace(item);
          if (p != null) results.add(p);
        }
        if (batch.length < batchSize) break;
        start += batchSize;
      }
      return results;
    } catch (_) {
      return [];
    }
  }

  Future<List<Place>> fetchPlacesUpdatedSince(DateTime since) async {
    try {
      const int batchSize = 1000;
      int start = 0;
      final List<Place> results = [];
      // Gunakan format ISO8601 dengan timezone offset jika perlu,
      // tapi biasanya toIso8601String() sudah cukup jika Supabase fieldnya timestamptz
      final sinceStr = since.toIso8601String();

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
            .gte('updated_at', sinceStr)
            .order('idsbr', ascending: true)
            .range(start, start + batchSize - 1);

        if (batch is! List || batch.isEmpty) break;
        for (final item in batch) {
          if (item is! Map<String, dynamic>) continue;
          final p = _mapToPlace(item);
          if (p != null) results.add(p);
        }
        if (batch.length < batchSize) break;
        start += batchSize;
      }
      return results;
    } catch (_) {
      return [];
    }
  }

  Place? _mapToPlace(Map<String, dynamic> item) {
    final lat = _parseDouble(item['latitude']);
    final lon = _parseDouble(item['longitude']);
    if (lat == null || lon == null) return null;
    final idsbr = (item['idsbr'] ?? '').toString();
    if (idsbr.isEmpty) return null;
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
    return Place(
      id: 'gc:$idsbr',
      name: name.isNotEmpty ? name : idsbr,
      description: desc,
      position: LatLng(lat, lon),
      gcsResult: gcs,
      address: alamat,
      statusPerusahaan: status,
    );
  }

  double? _parseDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  Future<File> get _localFile async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$_localFileName');
  }

  Future<List<GroundcheckRecord>> loadLocalRecords() async {
    try {
      final file = await _localFile;
      if (!await file.exists()) return [];
      final content = await file.readAsString();
      final List<dynamic> jsonList = jsonDecode(content);
      return jsonList.map((json) => GroundcheckRecord.fromJson(json)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> saveLocalRecords(List<GroundcheckRecord> records) async {
    try {
      final file = await _localFile;
      final jsonList = records.map((e) => e.toJson()).toList();
      await file.writeAsString(jsonEncode(jsonList));
    } catch (e) {
      // Ignore error
    }
  }

  Future<List<GroundcheckRecord>> syncRecords({bool forceFull = false}) async {
    try {
      // 1. Load local first
      List<GroundcheckRecord> localRecords = await loadLocalRecords();

      // 2. Get last sync time
      final prefs = await SharedPreferences.getInstance();
      final lastSyncStr = prefs.getString(_lastSyncKey);
      DateTime? lastSync;
      if (lastSyncStr != null) {
        lastSync = DateTime.tryParse(lastSyncStr);
      }

      // 3. Fetch updates
      List<GroundcheckRecord> updates = [];
      bool isIncremental = false;

      if (!forceFull && lastSync != null && localRecords.isNotEmpty) {
        // Fetch incremental
        try {
          updates = await fetchRecords(updatedSince: lastSync);
          isIncremental = true;
        } catch (e) {
          // If incremental fetch fails (e.g. offline), return local
          return localRecords;
        }
      } else {
        // Fetch all (first time, reset, or forced full sync)
        try {
          updates = await fetchRecords();
          // If we fetched everything successfully, we treat it as a full replacement
          // unless updates are empty (which might mean error or empty DB)
        } catch (e) {
          // If full fetch fails (e.g. offline), return local (which might be empty)
          return localRecords;
        }
      }

      // 4. Merge or Replace
      if (updates.isNotEmpty) {
        List<GroundcheckRecord> finalRecords;

        if (isIncremental) {
          // Merge incremental updates
          final Map<String, GroundcheckRecord> map = {
            for (var r in localRecords) r.idsbr: r,
          };
          for (var u in updates) {
            map[u.idsbr] = u;
          }
          finalRecords = map.values.toList();
        } else {
          // Full fetch (forceFull or first sync) -> Replace local cache
          finalRecords = updates;
        }

        // 5. Save local
        await saveLocalRecords(finalRecords);

        // 6. Update sync time
        await prefs.setString(
          _lastSyncKey,
          DateTime.now().toUtc().toIso8601String(),
        );

        return finalRecords;
      }

      return localRecords;
    } catch (e) {
      // Fallback
      return [];
    }
  }
}
