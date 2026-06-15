import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/supabase_config.dart';
import '../../../../core/services/storage/storage_interface.dart';
import '../../../../core/services/storage/storage_service.dart';
import '../models/assignment_place_record.dart';

class AssignmentPlacesService {
  static const String localFileName = 'assignment_places_cache.json';
  static const String lastSyncKey = 'assignment_places_last_sync_time';
  static const String lastFullSyncKey = 'assignment_places_last_full_sync_time';
  static const String cacheVersionKey = 'assignment_places_cache_version';
  static const String cacheOwnerKey = 'assignment_places_cache_owner';
  static const String cacheVersion = 'rpc_v2_minimal';

  final SupabaseClient _client = SupabaseConfig.client;
  final StorageService _storage = StorageServiceFactory.create();

  Future<List<AssignmentPlaceRecord>> loadLocalRecords() async {
    try {
      final content = await _storage.read(localFileName);
      if (content == null || content.isEmpty) return [];
      final decoded = jsonDecode(content);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map(
            (item) =>
                AssignmentPlaceRecord.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList();
    } catch (e) {
      debugPrint('AssignmentPlacesService: Error loading local records: $e');
      return [];
    }
  }

  Future<void> saveLocalRecords(List<AssignmentPlaceRecord> records) async {
    try {
      final payload = jsonEncode(records.map((e) => e.toJson()).toList());
      await _storage.write(localFileName, payload);
    } catch (e) {
      debugPrint('AssignmentPlacesService: Error saving local records: $e');
    }
  }

  Future<List<AssignmentPlaceRecord>> getVisibleLocalRecords() async {
    final ownerMatches = await _isCurrentUserCacheOwner();
    if (!ownerMatches) return [];
    final local = await loadLocalRecords();
    return local;
  }

  Future<List<AssignmentPlaceRecord>> syncRecords() async {
    final authUser = _client.auth.currentUser;
    if (authUser == null) {
      return getVisibleLocalRecords();
    }
    if (!await _isCurrentCacheUsable(authUser.id)) {
      return downloadFullData();
    }

    final prefs = await SharedPreferences.getInstance();
    final lastSync = prefs.getString(lastSyncKey);
    final localRecords = await loadLocalRecords();
    final updates = await _fetchRecords(
      syncMode: 'incremental',
      modifiedAfter: lastSync,
    );

    if (updates.isEmpty) {
      await _saveCacheMetadata(authUser.id);
      return getVisibleLocalRecords();
    }

    final merged = _mergeRecords(localRecords, updates);
    await saveLocalRecords(merged);
    await _saveCacheMetadata(authUser.id);
    final now = DateTime.now().toUtc().toIso8601String();
    await prefs.setString(lastSyncKey, now);
    if (!prefs.containsKey(lastFullSyncKey)) {
      await prefs.setString(lastFullSyncKey, now);
    }
    return merged;
  }

  Future<List<AssignmentPlaceRecord>> downloadFullData() async {
    final authUser = _client.auth.currentUser;
    if (authUser == null) {
      return getVisibleLocalRecords();
    }

    final fresh = await _fetchRecords(syncMode: 'full');
    await saveLocalRecords(fresh);
    await _saveCacheMetadata(authUser.id);

    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().toUtc().toIso8601String();
    await prefs.setString(lastSyncKey, now);
    await prefs.setString(lastFullSyncKey, now);

    return fresh;
  }

  Future<void> _saveCacheMetadata(String owner) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(cacheOwnerKey, owner);
    await prefs.setString(cacheVersionKey, cacheVersion);
  }

  Future<bool> _isCurrentCacheUsable(String owner) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(cacheOwnerKey) == owner &&
        prefs.getString(cacheVersionKey) == cacheVersion;
  }

  Future<bool> _isCurrentUserCacheOwner() async {
    final authUser = _client.auth.currentUser;
    if (authUser == null) return false;
    return _isCurrentCacheUsable(authUser.id);
  }

  Future<List<AssignmentPlaceRecord>> _fetchRecords({
    required String syncMode,
    String? modifiedAfter,
  }) async {
    try {
      final params = <String, dynamic>{'p_sync_mode': syncMode};
      if (modifiedAfter != null && modifiedAfter.isNotEmpty) {
        params['p_modified_after'] = modifiedAfter;
      }
      final response = await _client.rpc(
        'get_assignment_places_for_current_user',
        params: params,
      );
      if (response is! List) {
        return [];
      }
      return response
          .whereType<Map>()
          .map(
            (item) =>
                AssignmentPlaceRecord.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList();
    } catch (e) {
      debugPrint('AssignmentPlacesService: Error fetching RPC records: $e');
      return [];
    }
  }

  List<AssignmentPlaceRecord> _mergeRecords(
    List<AssignmentPlaceRecord> existing,
    List<AssignmentPlaceRecord> updates,
  ) {
    final map = <String, AssignmentPlaceRecord>{
      for (final record in existing) _recordKey(record): record,
    };
    for (final record in updates) {
      map[_recordKey(record)] = record;
    }
    return map.values.toList();
  }

  String _recordKey(AssignmentPlaceRecord record) {
    if (record.assignmentId.isNotEmpty) return record.assignmentId;
    return '${record.namaUsaha}:${record.noBang ?? ''}:${record.latitude}:${record.longitude}';
  }
}
