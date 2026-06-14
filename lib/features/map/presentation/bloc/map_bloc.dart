import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/services/map_assignment_focus_cache_service.dart';
import '../../data/services/groundcheck_supabase_service.dart';
import '../../domain/entities/map_focus_bounds.dart';
import '../../domain/entities/polygon_data.dart';
import '../../domain/usecases/get_all_polygons_meta_from_geojson.dart';
import '../../domain/usecases/get_first_polygon_meta_from_geojson.dart';
import '../../domain/usecases/get_polygon_points.dart';
import '../../domain/usecases/get_initial_map_config.dart';
import '../../domain/usecases/get_places.dart';
import '../../domain/usecases/get_places_in_bounds.dart';
import '../../domain/usecases/refresh_places.dart';
import 'map_event.dart';
import 'map_state.dart';

class MapBloc extends Bloc<MapEvent, MapState> {
  static const String _debugServerUrl = 'http://10.200.3.68:7777/event';
  static const String _debugSessionId = 'assignment-focus-cache';
  final GetInitialMapConfig getInitialMapConfig;
  final GetPlaces getPlaces;
  final RefreshPlaces refreshPlaces;
  final GetPlacesInBounds getPlacesInBounds;
  final GetFirstPolygonMetaFromGeoJson getFirstPolygonMeta;
  final GetAllPolygonsMetaFromGeoJson getAllPolygonsMeta;
  final GetPolygonPoints getPolygonPoints;
  final GroundcheckSupabaseService _groundcheckService =
      GroundcheckSupabaseService();
  final MapAssignmentFocusCacheService _focusCacheService =
      MapAssignmentFocusCacheService();

  MapBloc({
    required this.getInitialMapConfig,
    required this.getPlaces,
    required this.refreshPlaces,
    required this.getFirstPolygonMeta,
    required this.getAllPolygonsMeta,
    required this.getPlacesInBounds,
    required this.getPolygonPoints,
  }) : super(const MapState()) {
    on<MapInitRequested>(_onInit);
    on<PlacesRequested>(_onPlacesRequested);
    on<PlacesRefreshRequested>(_onPlacesRefreshRequested);
    on<PlacesInBoundsRequested>(_onPlacesInBoundsRequested);
    on<PlaceSelected>(_onPlaceSelected);
    on<PlaceCleared>(_onPlaceCleared);
    on<PolygonRequested>(_onPolygonRequested);
    on<PolygonsListRequested>(_onPolygonsListRequested);
    on<PolygonSelectedByIndex>(_onPolygonSelectedByIndex);
    on<PolygonSelected>(_onPolygonSelected);
    on<MultiplePolygonsSelected>(_onMultiplePolygonsSelected);
    on<TemporaryMarkerAdded>(_onTemporaryMarkerAdded);
    on<TemporaryMarkerRemoved>(_onTemporaryMarkerRemoved);
    on<AssignmentPolygonsToggleRequested>(_onAssignmentPolygonsToggleRequested);
  }

  Future<void> _onInit(MapInitRequested event, Emitter<MapState> emit) async {
    emit(state.copyWith(status: MapStatus.loading));
    try {
      final config = await getInitialMapConfig();
      final focusBounds = await _focusCacheService.loadCurrentUserBounds();
      // #region debug-point C:init-state
      unawaited(
        _debugReport(
          hypothesisId: 'C',
          location: 'map_bloc.dart:66',
          msg: '[DEBUG] map init completed',
          data: {
            'hasConfig': true,
            'hasFocusBounds': focusBounds != null,
            'focusSouth': focusBounds?.south,
            'focusNorth': focusBounds?.north,
            'focusWest': focusBounds?.west,
            'focusEast': focusBounds?.east,
          },
        ),
      );
      // #endregion
      emit(
        state.copyWith(
          status: MapStatus.success,
          config: config,
          assignmentFocusBounds: focusBounds,
          clearAssignmentFocusBounds: focusBounds == null,
        ),
      );
    } catch (e) {
      emit(state.copyWith(status: MapStatus.failure, error: e.toString()));
    }
  }

  Future<void> _onPlacesRequested(
    PlacesRequested event,
    Emitter<MapState> emit,
  ) async {
    try {
      final list = await getPlaces();

      // If we have active bounds, filter the result immediately
      if (state.lastSouth != null &&
          state.lastNorth != null &&
          state.lastWest != null &&
          state.lastEast != null) {
        final filtered = await getPlacesInBounds(
          state.lastSouth!,
          state.lastNorth!,
          state.lastWest!,
          state.lastEast!,
        );
        emit(state.copyWith(places: filtered));
      } else {
        emit(state.copyWith(places: list));
      }
    } catch (e) {
      emit(state.copyWith(error: e.toString()));
    }
  }

  Future<void> _onPlacesRefreshRequested(
    PlacesRefreshRequested event,
    Emitter<MapState> emit,
  ) async {
    try {
      // 1. Refresh cache (this fetches all places)
      final allPlaces = await refreshPlaces();

      // 2. If we have active bounds, filter the result immediately
      // This prevents the map from suddenly showing all 15k places (or first N of them)
      // which causes the "disappearing markers" flicker.
      if (state.lastSouth != null &&
          state.lastNorth != null &&
          state.lastWest != null &&
          state.lastEast != null) {
        final filtered = await getPlacesInBounds(
          state.lastSouth!,
          state.lastNorth!,
          state.lastWest!,
          state.lastEast!,
        );
        emit(state.copyWith(places: filtered));
      } else {
        emit(state.copyWith(places: allPlaces));
      }
    } catch (e) {
      emit(state.copyWith(error: e.toString()));
    }
  }

  Future<void> _onPlacesInBoundsRequested(
    PlacesInBoundsRequested event,
    Emitter<MapState> emit,
  ) async {
    try {
      final list = await getPlacesInBounds(
        event.south,
        event.north,
        event.west,
        event.east,
      );
      emit(
        state.copyWith(
          places: list,
          lastSouth: event.south,
          lastNorth: event.north,
          lastWest: event.west,
          lastEast: event.east,
        ),
      );
    } catch (e) {
      emit(state.copyWith(error: e.toString()));
    }
  }

  Future<void> _onPolygonRequested(
    PolygonRequested event,
    Emitter<MapState> emit,
  ) async {
    try {
      final meta = await getFirstPolygonMeta(event.assetPath);
      debugPrint(
        'BLoC: polygon points loaded = ${meta.points.length}, label = ${meta.name}',
      );

      // Buat label yang lebih informatif dengan nmsls, nmkec, dan nmdesa
      String label = _formatPolygonDisplayName(meta) ?? 'Polygon';
      if (meta.kecamatan != null || meta.desa != null) {
        final kecInfo = meta.kecamatan ?? '-';
        final desaInfo = meta.desa ?? '-';
        label = '$label\nKec: $kecInfo\nDesa: $desaInfo';
      }

      emit(
        state.copyWith(
          polygon: meta.points,
          polygonLabel: label,
          selectedPolygonMeta: meta,
        ),
      );
    } catch (e) {
      debugPrint('BLoC: polygon load failed: $e');
      emit(state.copyWith(error: e.toString()));
    }
  }

  Future<void> _onPolygonsListRequested(
    PolygonsListRequested event,
    Emitter<MapState> emit,
  ) async {
    try {
      final list = await getAllPolygonsMeta(event.assetPath);
      // debugPrint('BLoC: polygons list loaded count = ${list.length}');
      // Keep current selection if any, but don't auto-select first item
      var selPoints = state.polygon;
      String? selLabel = state.polygonLabel;
      var selMeta = state.selectedPolygonMeta;

      final assignmentPolygons = await _loadAssignmentPolygons(list);
      final assignmentFocusBounds = _buildFocusBounds(assignmentPolygons);
      // #region debug-point B:assignment-polygon-summary
      unawaited(
        _debugReport(
          hypothesisId: 'B',
          location: 'map_bloc.dart:224',
          msg: '[DEBUG] assignment polygons resolved',
          data: {
            'totalPolygonsMeta': list.length,
            'assignmentPolygonCount': assignmentPolygons.length,
            'firstPolygonIdsls': list.isNotEmpty ? list.first.idsls : null,
            'firstPolygonIdSubsls': list.isNotEmpty
                ? list.first.idsubsls
                : null,
            'firstPolygonPointCount': list.isNotEmpty ? list.first.points.length : null,
            'firstAssignmentIdsls': assignmentPolygons.isNotEmpty
                ? assignmentPolygons.first.idsls
                : null,
            'firstAssignmentIdSubsls': assignmentPolygons.isNotEmpty
                ? assignmentPolygons.first.idsubsls
                : null,
            'firstAssignmentPointCount': assignmentPolygons.isNotEmpty
                ? assignmentPolygons.first.points.length
                : null,
            'hasFocusBounds': assignmentFocusBounds != null,
            'focusSouth': assignmentFocusBounds?.south,
            'focusNorth': assignmentFocusBounds?.north,
            'focusWest': assignmentFocusBounds?.west,
            'focusEast': assignmentFocusBounds?.east,
          },
        ),
      );
      // #endregion
      if (assignmentFocusBounds != null) {
        await _focusCacheService.saveCurrentUserBounds(assignmentFocusBounds);
      } else {
        await _focusCacheService.clearCurrentUserBounds();
      }
      emit(
        state.copyWith(
          polygonsMeta: list,
          assignmentPolygons: assignmentPolygons,
          showAssignmentPolygons: state.assignmentPolygons.isEmpty
              ? assignmentPolygons.isNotEmpty
              : state.showAssignmentPolygons,
          assignmentFocusBounds: assignmentFocusBounds,
          clearAssignmentFocusBounds: assignmentFocusBounds == null,
          polygon: selPoints,
          polygonLabel: selLabel,
          selectedPolygonMeta: selMeta,
        ),
      );
    } catch (e) {
      debugPrint('BLoC: polygons list load failed: $e');
      emit(state.copyWith(error: e.toString()));
    }
  }

  Future<void> _onPolygonSelectedByIndex(
    PolygonSelectedByIndex event,
    Emitter<MapState> emit,
  ) async {
    if (event.index < 0 || event.index >= state.polygonsMeta.length) return;
    var sel = state.polygonsMeta[event.index];

    // Fetch points if missing
    if (sel.points.isEmpty && sel.idsls != null) {
      try {
        final points = await getPolygonPoints(sel.idsls!);
        sel = PolygonData(
          points: points,
          name: sel.name,
          kecamatan: sel.kecamatan,
          desa: sel.desa,
          idsls: sel.idsls,
          idsubsls: sel.idsubsls,
          subsls: sel.subsls,
          kodePos: sel.kodePos,
        );
      } catch (e) {
        debugPrint('BLoC: failed to load points for ${sel.idsls}: $e');
      }
    }

    // Buat label yang lebih informatif dengan nmsls, nmkec, dan nmdesa
    String label =
        _formatPolygonDisplayName(sel) ?? 'Polygon ${event.index + 1}';
    if (sel.kecamatan != null || sel.desa != null) {
      final kecInfo = sel.kecamatan ?? '-';
      final desaInfo = sel.desa ?? '-';
      label = '$label\nKec: $kecInfo\nDesa: $desaInfo';
    }

    emit(
      state.copyWith(
        polygon: sel.points,
        polygonLabel: label,
        selectedPolygonMeta: sel,
        selectedPolygons: [], // Clear multiple selection
      ),
    );
  }

  Future<void> _onPolygonSelected(
    PolygonSelected event,
    Emitter<MapState> emit,
  ) async {
    var sel = event.polygon;

    // Fetch points if missing
    if (sel.points.isEmpty && sel.idsls != null) {
      try {
        final points = await getPolygonPoints(sel.idsls!);
        sel = PolygonData(
          points: points,
          name: sel.name,
          kecamatan: sel.kecamatan,
          desa: sel.desa,
          idsls: sel.idsls,
          idsubsls: sel.idsubsls,
          subsls: sel.subsls,
          kodePos: sel.kodePos,
        );
      } catch (e) {
        debugPrint('BLoC: failed to load points for ${sel.idsls}: $e');
      }
    }

    // Buat label yang lebih informatif dengan nmsls, nmkec, dan nmdesa
    String label = _formatPolygonDisplayName(sel) ?? 'Polygon';
    if (sel.kecamatan != null || sel.desa != null) {
      final kecInfo = sel.kecamatan ?? '-';
      final desaInfo = sel.desa ?? '-';
      label = '$label\nKec: $kecInfo\nDesa: $desaInfo';
    }

    emit(
      state.copyWith(
        polygon: sel.points,
        polygonLabel: label,
        selectedPolygonMeta: sel,
        selectedPolygons: [], // Clear multiple selection
      ),
    );
  }

  void _onPlaceSelected(PlaceSelected event, Emitter<MapState> emit) {
    emit(state.copyWith(selectedPlace: event.place));
  }

  void _onPlaceCleared(PlaceCleared event, Emitter<MapState> emit) {
    emit(state.copyWith(clearSelectedPlace: true));
  }

  void _onTemporaryMarkerAdded(
    TemporaryMarkerAdded event,
    Emitter<MapState> emit,
  ) {
    emit(state.copyWith(temporaryMarker: event.position));
  }

  void _onTemporaryMarkerRemoved(
    TemporaryMarkerRemoved event,
    Emitter<MapState> emit,
  ) {
    emit(state.copyWith(clearTemporaryMarker: true));
  }

  void _onAssignmentPolygonsToggleRequested(
    AssignmentPolygonsToggleRequested event,
    Emitter<MapState> emit,
  ) {
    if (state.assignmentPolygons.isEmpty) return;
    // #region debug-point D:assignment-polygon-toggle
    unawaited(
      _debugReport(
        hypothesisId: 'D',
        location: 'map_bloc.dart:381',
        msg: '[DEBUG] assignment polygon visibility toggled',
        data: {
          'currentShowAssignmentPolygons': state.showAssignmentPolygons,
          'nextShowAssignmentPolygons': !state.showAssignmentPolygons,
          'assignmentPolygonCount': state.assignmentPolygons.length,
        },
      ),
    );
    // #endregion
    emit(state.copyWith(showAssignmentPolygons: !state.showAssignmentPolygons));
  }

  Future<void> _onMultiplePolygonsSelected(
    MultiplePolygonsSelected event,
    Emitter<MapState> emit,
  ) async {
    if (event.polygons.isEmpty) {
      emit(
        state.copyWith(
          selectedPolygons: [],
          polygon: [],
          polygonLabel: '',
          clearSelectedPolygonMeta: true,
        ),
      );
      return;
    }

    // Fetch points for all selected polygons if missing
    final List<PolygonData> polygonsWithPoints = [];
    for (var p in event.polygons) {
      if (p.points.isEmpty && p.idsls != null) {
        try {
          final points = await getPolygonPoints(p.idsls!);
          polygonsWithPoints.add(
            PolygonData(
              points: points,
              name: p.name,
              kecamatan: p.kecamatan,
              desa: p.desa,
              idsls: p.idsls,
              idsubsls: p.idsubsls,
              subsls: p.subsls,
              kodePos: p.kodePos,
            ),
          );
        } catch (e) {
          debugPrint('BLoC: failed to load points for ${p.idsls}: $e');
          polygonsWithPoints.add(p);
        }
      } else {
        polygonsWithPoints.add(p);
      }
    }

    final first = polygonsWithPoints.first;
    String label = '';
    final firstId = first.idsls ?? '';
    if (firstId.length >= 10) {
      final prefix = firstId.substring(0, 10);
      final sameDesa = polygonsWithPoints.every(
        (p) => (p.idsls ?? '').startsWith(prefix),
      );
      if (sameDesa) {
        label =
            'Kelurahan: ${first.desa ?? '-'}\nKec: ${first.kecamatan ?? '-'}';
      } else {
        label = '${polygonsWithPoints.length} Polygons Selected';
      }
    } else {
      label = '${polygonsWithPoints.length} Polygons Selected';
    }

    emit(
      state.copyWith(
        selectedPolygons: polygonsWithPoints,
        polygon: first.points,
        polygonLabel: label,
        selectedPolygonMeta: first,
      ),
    );
  }

  Future<List<PolygonData>> _loadAssignmentPolygons(
    List<PolygonData> polygonsMeta,
  ) async {
    if (polygonsMeta.isEmpty) return const [];

    try {
      final profile = await _groundcheckService.fetchCurrentSe2026Profile();
      // #region debug-point E:profile-role
      unawaited(
        _debugReport(
          hypothesisId: 'E',
          location: 'map_bloc.dart:434',
          msg: '[DEBUG] profile fetched for assignment polygons',
          data: {
            'hasProfile': profile != null,
            'isActive': profile?.isActive,
            'role': profile?.role,
          },
        ),
      );
      // #endregion
      if (profile == null || !profile.isActive || profile.role == 'admin') {
        return const [];
      }

      final wilayah = await _groundcheckService.fetchCurrentUserWilayahTugas();
      // #region debug-point B:wilayah-match-input
      unawaited(
        _debugReport(
          hypothesisId: 'B',
          location: 'map_bloc.dart:449',
          msg: '[DEBUG] wilayah tugas fetched for polygon matching',
          data: {
            'wilayahCount': wilayah.length,
            'firstWilayahId': wilayah.isNotEmpty ? wilayah.first['id']?.toString() : null,
            'firstWilayahIdSls': wilayah.isNotEmpty
                ? wilayah.first['id_sls']?.toString()
                : null,
          },
        ),
      );
      // #endregion
      if (wilayah.isEmpty) return const [];

      final assignmentIds = wilayah
          .expand((item) {
            final values = <String>[
              item['id']?.toString().trim() ?? '',
              item['id_sls']?.toString().trim() ?? '',
            ];
            return values.where((value) => value.isNotEmpty);
          })
          .toSet();
      if (assignmentIds.isEmpty) return const [];

      final matchedPolygons = polygonsMeta.where((polygon) {
        final idsubsls = polygon.idsubsls?.trim();
        final idsls = polygon.idsls?.trim();
        return (idsubsls != null && assignmentIds.contains(idsubsls)) ||
            (idsls != null && assignmentIds.contains(idsls));
      }).toList();

      // #region debug-point B:wilayah-match-result
      unawaited(
        _debugReport(
          hypothesisId: 'B',
          location: 'map_bloc.dart:512',
          msg: '[DEBUG] assignment polygon matching completed',
          data: {
            'assignmentIdCount': assignmentIds.length,
            'polygonMetaCount': polygonsMeta.length,
            'matchedPolygonCount': matchedPolygons.length,
            'sampleAssignmentIds': assignmentIds.take(5).toList(),
            'samplePolygonIds': polygonsMeta
                .take(5)
                .map(
                  (polygon) => {
                    'idsls': polygon.idsls,
                    'idsubsls': polygon.idsubsls,
                  },
                )
                .toList(),
            'sampleMatchedPolygonIds': matchedPolygons
                .take(5)
                .map(
                  (polygon) => {
                    'idsls': polygon.idsls,
                    'idsubsls': polygon.idsubsls,
                  },
                )
                .toList(),
          },
        ),
      );
      // #endregion

      return matchedPolygons;
    } catch (e) {
      debugPrint('BLoC: failed to load assignment polygons: $e');
      unawaited(
        _debugReport(
          hypothesisId: 'B',
          location: 'map_bloc.dart:531',
          msg: '[DEBUG] assignment polygon load failed',
          data: {'error': e.toString()},
        ),
      );
      return const [];
    }
  }

  MapFocusBounds? _buildFocusBounds(List<PolygonData> polygons) {
    if (polygons.isEmpty) return null;

    double minLat = 90.0;
    double maxLat = -90.0;
    double minLng = 180.0;
    double maxLng = -180.0;
    var hasPoints = false;

    for (final polygon in polygons) {
      for (final point in polygon.points) {
        hasPoints = true;
        if (point.latitude < minLat) minLat = point.latitude;
        if (point.latitude > maxLat) maxLat = point.latitude;
        if (point.longitude < minLng) minLng = point.longitude;
        if (point.longitude > maxLng) maxLng = point.longitude;
      }
    }

    if (!hasPoints) return null;

    final bounds = MapFocusBounds(
      south: minLat,
      north: maxLat,
      west: minLng,
      east: maxLng,
    );
    return bounds.isValid ? bounds : null;
  }

  String? _formatPolygonDisplayName(PolygonData polygon) {
    final baseName = polygon.name?.trim();
    if (baseName == null || baseName.isEmpty) return null;

    final subsls = polygon.subsls?.trim();
    if (subsls == null || subsls.isEmpty || subsls == '00') {
      return baseName;
    }

    return '$baseName ($subsls)';
  }

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
