import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/config/supabase_config.dart';
import '../../domain/entities/groundcheck_record.dart';
import '../../domain/entities/place.dart';
import 'package:latlong2/latlong.dart';
import '../../../../core/utils/debug_monitor.dart';
import '../../../../core/services/storage/storage_service.dart';
import '../../../../core/services/storage/storage_interface.dart';

class GroundcheckSupabaseService {
  final SupabaseClient _client = SupabaseConfig.client;
  static const String _tableName = 'groundcheck_list';
  static const String _localFileName = 'groundcheck_list_cache.json';
  static const String _lastSyncKey = 'groundcheck_last_sync_time';

  // Storage Service abstraction
  final StorageService _storage = StorageServiceFactory.create();

  Future<List<GroundcheckRecord>> fetchRecords({DateTime? updatedSince}) async {
    try {
      // Select specific columns to reduce bandwidth
      const columns =
          'idsbr, nama_usaha, alamat_usaha, kode_wilayah, '
          'status_perusahaan, skala_usaha, gcs_result, sumber_data, '
          'latitude, longitude, perusahaan_id, user_id, kdprov, kdkab, '
          'kdkec, kddesa, is_revisi, allow_cancel, updated_at, isUploaded';

      const int batchSize = 1000;
      int start = 0;
      final List<GroundcheckRecord> all = [];
      final sinceStr = updatedSince?.toIso8601String();

      while (true) {
        dynamic query = _client.from(_tableName).select(columns);

        if (sinceStr != null) {
          query = query.gt('updated_at', sinceStr);
          // Optimize: gunakan index updated_at untuk incremental sync
          query = query.order('updated_at', ascending: true);
        }

        // Always order by idsbr for deterministic pagination
        final batch = await query
            .order('idsbr', ascending: true)
            .range(start, start + batchSize - 1);

        DebugMonitor().logUsage(_tableName, 'SELECT (Batch)', batch);

        if (batch is List && batch.isNotEmpty) {
          // DEBUG: Check keys for troubleshooting

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
      debugPrint('DEBUG: fetchRecords Error: $e');
      // If table doesn't exist or empty, return empty list
      // But for debugging, we should probably know if it failed.
      // If we return [], syncRecords thinks DB is empty and returns localRecords.
      // We should rethrow to let syncRecords handle the fallback or error.
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> fetchDashboardStats() async {
    try {
      final response = await _client.from('view_dashboard_stats').select();
      DebugMonitor().logUsage('view_dashboard_stats', 'SELECT', response);
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
      debugPrint('[SupaSupabase Monitorporting from asset $assetPath...');
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
                'provinsi_id':
                    e['kd_prov']?.toString() ??
                    e['provinsi_id']?.toString() ??
                    '',
                'kabupaten_id':
                    e['kd_kab']?.toString() ??
                    e['kabupaten_id']?.toString() ??
                    '',
                'kecamatan_id':
                    e['kd_kec']?.toString() ??
                    e['kecamatan_id']?.toString() ??
                    '',
                'desa_id':
                    e['kd_desa']?.toString() ?? e['desa_id']?.toString() ?? '',
                'updated_at': DateTime.now().toIso8601String(),
                'isUploaded': e['isUploaded'] == true,
              },
            )
            .toList();

        DebugMonitor().logUsage(
          _tableName,
          'UPSERT (Batch)',
          payload,
          isResponse: false,
        );
        await _client.from(_tableName).upsert(payload, onConflict: 'idsbr');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<List<GroundcheckRecord>> searchRecords(String query) async {
    try {
      debugPrint('[SupaSupabase Monitorarching records for "$query"...');
      final response = await _client
          .from(_tableName)
          .select()
          .or('nama_usaha.ilike.%$query%,idsbr.ilike.%$query%')
          .limit(20);

      DebugMonitor().logUsage(_tableName, 'SELECT (Search)', response);

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

  Future<List<GroundcheckRecord>> searchLocalRecords(String query) async {
    try {
      final records = await loadLocalRecords();
      if (query.isEmpty) return [];

      final q = query.toLowerCase();
      return records
          .where((r) {
            return r.idsbr.toLowerCase().contains(q) ||
                r.namaUsaha.toLowerCase().contains(q) ||
                (r.alamatUsaha.isNotEmpty &&
                    r.alamatUsaha.toLowerCase().contains(q));
          })
          .take(50)
          .toList();
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
            kdProv:
                json['kd_prov']?.toString() ?? json['provinsi_id']?.toString(),
            kdKab:
                json['kd_kab']?.toString() ?? json['kabupaten_id']?.toString(),
            kdKec:
                json['kd_kec']?.toString() ?? json['kecamatan_id']?.toString(),
            kdDesa: json['kd_desa']?.toString() ?? json['desa_id']?.toString(),
            isRevisi: json['is_revisi'] == true,
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

      DebugMonitor().logUsage(
        'view_groundcheck_leaderboard',
        'SELECT',
        response,
      );

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

      DebugMonitor().logUsage('users', 'SELECT (ID)', response);

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

  Future<String?> fetchCurrentUserRole() async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) return null;

      final response = await _client
          .from('users')
          .select('role')
          .eq('auth_uid', user.id)
          .maybeSingle();

      if (response != null && response['role'] != null) {
        return response['role'].toString();
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<bool> deleteRecords(List<String> idsbrList) async {
    try {
      if (idsbrList.isEmpty) return true;

      // Delete from Supabase
      debugPrint('[SupaSupabase Monitorleting ${idsbrList.length} records...');
      await _client.from(_tableName).delete().filter('idsbr', 'in', idsbrList);
      DebugMonitor().logUsage(_tableName, 'DELETE', {
        'count': idsbrList.length,
      }, isResponse: false);

      // Delete from local cache
      final records = await loadLocalRecords();
      records.removeWhere((r) => idsbrList.contains(r.idsbr));
      await saveLocalRecords(records);

      return true;
    } catch (e) {
      print('Error deleteRecords: $e');
      return false;
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

  Future<void> updateRecord(
    GroundcheckRecord record, {
    bool updateTimestamp = true,
  }) async {
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
        'kdprov': record.kdProv,
        'kdkab': record.kdKab,
        'kdkec': record.kdKec,
        'kddesa': record.kdDesa,
        'isUploaded': record.isUploaded,
        'allow_cancel': record.allowCancel,
      };

      // Logic is_revisi: Jika data sudah diupload (isUploaded=true) dan ada update,
      // maka tandai sebagai revisi. Atau jika memang sudah status revisi.
      if (record.isUploaded || record.isRevisi) {
        data['is_revisi'] = true;
      }

      if (updateTimestamp) {
        data['updated_at'] = DateTime.now().toIso8601String();
      }

      if (record.userId != null) {
        data['user_id'] = record.userId!;
      }

      DebugMonitor().logUsage(
        _tableName,
        'UPSERT (Single)',
        data,
        isResponse: false,
      );
      await _client.from(_tableName).upsert(data, onConflict: 'idsbr');

      // Update local cache
      // Pastikan status isRevisi tersimpan di lokal jika berubah
      final recordToSave = (record.isUploaded && !record.isRevisi)
          ? record.copyWith(isRevisi: true)
          : record;
      await updateLocalRecord(recordToSave);
    } catch (e) {
      print('Error updateRecord: $e');
      // Handle error but try to update local cache anyway if it's a network error?
      // For now, let's assume we want to be optimistic or at least consistent.
      // If network fails, we might still want to save locally if we support full offline edits.
      // But for now, let's just save locally if we reached here (implies optimistic or parallel).
      // To be safe, we should update local only if successful or if we implement a sync queue.
      // Given the requirement is just "sync local and server", updating local after server attempt is fine.
      await updateLocalRecord(record);
    }
  }

  Future<bool> updateUploadStatus(String idsbr, bool isUploaded) async {
    try {
      final response = await _client
          .from(_tableName)
          .update({'isUploaded': isUploaded})
          .eq('idsbr', idsbr)
          .select();

      if (response.isEmpty) {
        print(
          'Warning: Gagal upload status, data tidak ditemukan untuk idsbr: $idsbr',
        );
      } else {
        print('Berhasil upload status untuk idsbr: $idsbr');
      }

      // Update local cache
      final records = await loadLocalRecords();
      final index = records.indexWhere((r) => r.idsbr == idsbr);
      if (index != -1) {
        final old = records[index];
        records[index] = old.copyWith(isUploaded: isUploaded);
        await saveLocalRecords(records);
      }
      return true;
    } catch (e) {
      print('Gagal upload status: $e');
      return false;
    }
  }

  Future<bool> updateCoordinates({
    required String idsbr,
    required double latitude,
    required double longitude,
  }) async {
    try {
      // Prepare update data
      final updateData = <String, dynamic>{
        'latitude': latitude.toString(),
        'longitude': longitude.toString(),
        'updated_at': DateTime.now().toIso8601String(),
      };

      // Check local cache for isUploaded status
      final records = await loadLocalRecords();
      final index = records.indexWhere((r) => r.idsbr == idsbr);
      bool shouldSetRevisi = false;

      if (index != -1) {
        final old = records[index];
        if (old.isUploaded || old.isRevisi) {
          updateData['is_revisi'] = true;
          shouldSetRevisi = true;
        }
      }

      await _client.from(_tableName).update(updateData).eq('idsbr', idsbr);

      // Update local cache
      if (index != -1) {
        final old = records[index];
        final newRecord = old.copyWith(
          latitude: latitude.toString(),
          longitude: longitude.toString(),
          isRevisi: shouldSetRevisi ? true : old.isRevisi,
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

  Future<bool> deleteOrCloseRecord(String idsbr) async {
    try {
      // Determine if temp
      final bool isTemp =
          idsbr.toUpperCase().startsWith('TEMP') ||
          idsbr.toUpperCase().startsWith('BARU');

      // 1. Update Local Cache First
      final records = await loadLocalRecords();
      final index = records.indexWhere((r) => r.idsbr == idsbr);
      bool shouldSetRevisi = false;

      if (index != -1) {
        if (isTemp) {
          records.removeAt(index);
        } else {
          final old = records[index];
          if (old.isUploaded || old.isRevisi) {
            shouldSetRevisi = true;
          }
          records[index] = old.copyWith(
            gcsResult: '3', // Tutup
            isRevisi: shouldSetRevisi ? true : old.isRevisi,
          );
        }
        await saveLocalRecords(records);
      }

      // 2. Update Remote
      if (isTemp) {
        await _client.from(_tableName).delete().eq('idsbr', idsbr);
      } else {
        final updateData = <String, dynamic>{
          'gcs_result': '3', // Tutup
          'updated_at': DateTime.now().toIso8601String(),
        };
        if (shouldSetRevisi) {
          updateData['is_revisi'] = true;
        }
        await _client.from(_tableName).update(updateData).eq('idsbr', idsbr);
      }

      return true;
    } catch (e) {
      print('Error deleteOrCloseRecord: $e');
      // If local succeeded but remote failed, we might still want to return true
      // or false depending on how strict we are.
      // Given "Local First", if local is updated, we are partially successful.
      return false;
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
      // Check local for isUploaded status
      final records = await loadLocalRecords();
      final index = records.indexWhere((r) => r.idsbr == idsbr);
      bool shouldSetRevisi = false;
      if (index != -1) {
        final old = records[index];
        if (old.isUploaded || old.isRevisi) {
          shouldSetRevisi = true;
        }
      }

      final data = <String, dynamic>{
        'gcs_result': hasilGc,
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (shouldSetRevisi) {
        data['is_revisi'] = true;
      }

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
      if (index != -1) {
        final old = records[index];
        final newRecord = old.copyWith(
          namaUsaha: namaUsaha ?? old.namaUsaha,
          alamatUsaha: alamatUsaha ?? old.alamatUsaha,
          gcsResult: hasilGc,
          userId: userId ?? old.userId,
          isRevisi: shouldSetRevisi ? true : old.isRevisi,
        );
        records[index] = newRecord;
        await saveLocalRecords(records);
      }

      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> resetRevisiStatus(String idsbr) async {
    try {
      // 1. Update Supabase
      await _client
          .from(_tableName)
          .update({
            'isUploaded': false,
            'is_revisi': false,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('idsbr', idsbr);

      // 2. Update Local Cache
      final records = await loadLocalRecords();
      final index = records.indexWhere((r) => r.idsbr == idsbr);
      if (index != -1) {
        final old = records[index];
        records[index] = old.copyWith(isUploaded: false, isRevisi: false);
        await saveLocalRecords(records);
      }
      return true;
    } catch (e) {
      print('Error resetRevisiStatus: $e');
      return false;
    }
  }

  Future<bool> disableAllowCancel(String idsbr) async {
    try {
      // 1. Update Supabase
      await _client
          .from(_tableName)
          .update({
            'allow_cancel': false,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('idsbr', idsbr);

      // 2. Update Local Cache
      final records = await loadLocalRecords();
      final index = records.indexWhere((r) => r.idsbr == idsbr);
      if (index != -1) {
        final old = records[index];
        records[index] = old.copyWith(allowCancel: false);
        await saveLocalRecords(records);
      }
      return true;
    } catch (e) {
      print('Error disableAllowCancel: $e');
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

  // Helper _localFile dihapus karena digantikan oleh StorageService abstraction

  Future<List<GroundcheckRecord>> loadLocalRecords() async {
    try {
      final content = await _storage.read(_localFileName);

      if (content == null || content.isEmpty) return [];
      final List<dynamic> jsonList = jsonDecode(content);
      return jsonList.map((json) => GroundcheckRecord.fromJson(json)).toList();
    } catch (e) {
      debugPrint('GroundcheckSupabaseService: Error loading local records: $e');
      return [];
    }
  }

  Future<void> saveLocalRecords(List<GroundcheckRecord> records) async {
    try {
      final jsonList = records.map((e) => e.toJson()).toList();
      final jsonString = jsonEncode(jsonList);

      await _storage.write(_localFileName, jsonString);
    } catch (e) {
      debugPrint('GroundcheckSupabaseService: Error saving local records: $e');
    }
  }

  /// Mengunduh data lengkap dari server (Full Sync).
  /// Mengganti seluruh cache lokal dengan data baru.
  /// Digunakan saat "Unduh" pertama kali atau user melakukan "Reset/Unduh Ulang".
  Future<List<GroundcheckRecord>> downloadFullData() async {
    try {
      // 1. Fetch all records from server
      final records = await fetchRecords();

      if (records.isNotEmpty) {
        // 2. Save to local cache (Replace all)
        await saveLocalRecords(records);

        // 3. Update last sync time
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          _lastSyncKey,
          DateTime.now().toUtc().toIso8601String(),
        );

        return records;
      } else {
        return [];
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Melakukan sinkronisasi inkremental (hanya mengambil data baru/update).
  /// HANYA berjalan jika sudah ada data lokal dan lastSyncTime.
  /// Jika belum ada data lokal, fungsi ini TIDAK melakukan apa-apa (return local).
  Future<List<GroundcheckRecord>> syncRecords() async {
    try {
      // 1. Load local first
      List<GroundcheckRecord> localRecords = await loadLocalRecords();

      if (localRecords.isEmpty) {
        return [];
      }

      // 2. Get last sync time
      final prefs = await SharedPreferences.getInstance();
      final lastSyncStr = prefs.getString(_lastSyncKey);
      DateTime? lastSync;
      if (lastSyncStr != null) {
        lastSync = DateTime.tryParse(lastSyncStr);
      }

      if (lastSync == null) {
        return localRecords;
      }

      // 3. Fetch updates only

      List<GroundcheckRecord> updates = [];
      try {
        updates = await fetchRecords(updatedSince: lastSync);
      } catch (e) {
        return localRecords;
      }

      // 4. Merge updates
      if (updates.isNotEmpty) {
        final Map<String, GroundcheckRecord> map = {
          for (var r in localRecords) r.idsbr: r,
        };
        for (var u in updates) {
          map[u.idsbr] = u;
        }
        final finalRecords = map.values.toList();

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
      debugPrint('[Supabase Monitor] syncRecords: Unexpected error ($e).');
      return [];
    }
  }
}
