import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/supabase_config.dart';
import '../../domain/entities/map_focus_bounds.dart';

class MapAssignmentFocusCacheService {
  static const String _cacheKeyPrefix = 'map_assignment_focus_bounds_v1';
  static const String _debugServerUrl = 'http://10.200.3.68:7777/event';
  static const String _debugSessionId = 'assignment-focus-cache';

  final SupabaseClient _client = SupabaseConfig.client;

  Future<MapFocusBounds?> loadCurrentUserBounds() async {
    final authUser = _client.auth.currentUser;
    if (authUser == null) return null;

    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey(authUser.id));
      if (raw == null || raw.isEmpty) return null;

      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;

      final bounds = MapFocusBounds.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      // #region debug-point A:focus-cache-load
      unawaited(
        _debugReport(
          hypothesisId: 'A',
          location: 'map_assignment_focus_cache_service.dart:31',
          msg: '[DEBUG] focus cache loaded',
          data: {
            'owner': authUser.id,
            'hasRaw': raw.isNotEmpty,
            'isValid': bounds.isValid,
            'south': bounds.south,
            'north': bounds.north,
            'west': bounds.west,
            'east': bounds.east,
          },
        ),
      );
      // #endregion
      return bounds.isValid ? bounds : null;
    } catch (e) {
      // #region debug-point A:focus-cache-load-error
      unawaited(
        _debugReport(
          hypothesisId: 'A',
          location: 'map_assignment_focus_cache_service.dart:50',
          msg: '[DEBUG] focus cache load failed',
          data: {'error': e.toString()},
        ),
      );
      // #endregion
      debugPrint('MapAssignmentFocusCacheService: Error loading bounds: $e');
      return null;
    }
  }

  Future<void> saveCurrentUserBounds(MapFocusBounds bounds) async {
    final authUser = _client.auth.currentUser;
    if (authUser == null || !bounds.isValid) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey(authUser.id), jsonEncode(bounds.toJson()));
      // #region debug-point A:focus-cache-save
      unawaited(
        _debugReport(
          hypothesisId: 'A',
          location: 'map_assignment_focus_cache_service.dart:72',
          msg: '[DEBUG] focus cache saved',
          data: {
            'owner': authUser.id,
            'south': bounds.south,
            'north': bounds.north,
            'west': bounds.west,
            'east': bounds.east,
          },
        ),
      );
      // #endregion
    } catch (e) {
      debugPrint('MapAssignmentFocusCacheService: Error saving bounds: $e');
    }
  }

  Future<void> clearCurrentUserBounds() async {
    final authUser = _client.auth.currentUser;
    if (authUser == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey(authUser.id));
    } catch (e) {
      debugPrint('MapAssignmentFocusCacheService: Error clearing bounds: $e');
    }
  }

  String _cacheKey(String userId) => '$_cacheKeyPrefix::$userId';

  Future<void> _debugReport({
    required String hypothesisId,
    required String location,
    required String msg,
    required Map<String, Object?> data,
  }) async {
    final localLine =
        '[assignment-focus-cache][$hypothesisId][$location] $msg ${jsonEncode(data)}';
    debugPrint(localLine);
    try {
      final client = HttpClient();
      final request = await client.postUrl(Uri.parse(_debugServerUrl));
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode({
          'sessionId': _debugSessionId,
          'runId': 'pre-fix',
          'hypothesisId': hypothesisId,
          'location': location,
          'msg': msg,
          'data': data,
          'ts': DateTime.now().millisecondsSinceEpoch,
        }),
      );
      await request.close();
      client.close(force: true);
    } catch (e) {
      debugPrint(
        '[assignment-focus-cache][$hypothesisId][$location] remote-log-failed ${e.toString()}',
      );
    }
  }
}
