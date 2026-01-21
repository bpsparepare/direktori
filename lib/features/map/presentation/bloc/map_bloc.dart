import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/usecases/get_all_polygons_meta_from_geojson.dart';
import '../../domain/usecases/get_first_polygon_meta_from_geojson.dart';
import '../../domain/usecases/get_initial_map_config.dart';
import '../../domain/usecases/get_places.dart';
import '../../domain/usecases/get_places_in_bounds.dart';
import '../../domain/usecases/refresh_places.dart';
import 'map_event.dart';
import 'map_state.dart';

class MapBloc extends Bloc<MapEvent, MapState> {
  final GetInitialMapConfig getInitialMapConfig;
  final GetPlaces getPlaces;
  final RefreshPlaces refreshPlaces;
  final GetPlacesInBounds getPlacesInBounds;
  final GetFirstPolygonMetaFromGeoJson getFirstPolygonMeta;
  final GetAllPolygonsMetaFromGeoJson getAllPolygonsMeta;

  MapBloc({
    required this.getInitialMapConfig,
    required this.getPlaces,
    required this.refreshPlaces,
    required this.getFirstPolygonMeta,
    required this.getAllPolygonsMeta,
    required this.getPlacesInBounds,
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
  }

  Future<void> _onInit(MapInitRequested event, Emitter<MapState> emit) async {
    emit(state.copyWith(status: MapStatus.loading));
    try {
      final config = await getInitialMapConfig();
      emit(state.copyWith(status: MapStatus.success, config: config));
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
      emit(state.copyWith(places: list));
    } catch (e) {
      emit(state.copyWith(error: e.toString()));
    }
  }

  Future<void> _onPlacesRefreshRequested(
    PlacesRefreshRequested event,
    Emitter<MapState> emit,
  ) async {
    try {
      final list = await refreshPlaces(onlyToday: event.onlyToday);
      emit(state.copyWith(places: list));
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
      emit(state.copyWith(places: list));
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
      String label = meta.name ?? 'Polygon';
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
      debugPrint('BLoC: polygons list loaded count = ${list.length}');
      // Keep current selection if any, but don't auto-select first item
      var selPoints = state.polygon;
      String? selLabel = state.polygonLabel;
      var selMeta = state.selectedPolygonMeta;

      emit(
        state.copyWith(
          polygonsMeta: list,
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

  void _onPolygonSelectedByIndex(
    PolygonSelectedByIndex event,
    Emitter<MapState> emit,
  ) {
    if (event.index < 0 || event.index >= state.polygonsMeta.length) return;
    final sel = state.polygonsMeta[event.index];

    // Buat label yang lebih informatif dengan nmsls, nmkec, dan nmdesa
    String label = sel.name ?? 'Polygon ${event.index + 1}';
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

  void _onPolygonSelected(PolygonSelected event, Emitter<MapState> emit) {
    // Buat label yang lebih informatif dengan nmsls, nmkec, dan nmdesa
    String label = event.polygon.name ?? 'Polygon';
    if (event.polygon.kecamatan != null || event.polygon.desa != null) {
      final kecInfo = event.polygon.kecamatan ?? '-';
      final desaInfo = event.polygon.desa ?? '-';
      label = '$label\nKec: $kecInfo\nDesa: $desaInfo';
    }

    emit(
      state.copyWith(
        polygon: event.polygon.points,
        polygonLabel: label,
        selectedPolygonMeta: event.polygon,
        selectedPolygons: [], // Clear multiple selection
      ),
    );
  }

  void _onPlaceSelected(PlaceSelected event, Emitter<MapState> emit) {
    emit(state.copyWith(selectedPlace: event.place));
  }

  void _onPlaceCleared(PlaceCleared event, Emitter<MapState> emit) {
    print('DEBUG: _onPlaceCleared called'); // Debug log
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

  void _onMultiplePolygonsSelected(
    MultiplePolygonsSelected event,
    Emitter<MapState> emit,
  ) {
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

    final first = event.polygons.first;
    String label = '';
    final firstId = first.idsls ?? '';
    if (firstId.length >= 10) {
      final prefix = firstId.substring(0, 10);
      final sameDesa = event.polygons.every(
        (p) => (p.idsls ?? '').startsWith(prefix),
      );
      if (sameDesa) {
        label =
            'Kelurahan: ${first.desa ?? '-'}\nKec: ${first.kecamatan ?? '-'}';
      } else {
        label = '${event.polygons.length} Polygons Selected';
      }
    } else {
      label = '${event.polygons.length} Polygons Selected';
    }

    emit(
      state.copyWith(
        selectedPolygons: event.polygons,
        polygon: first.points,
        polygonLabel: label,
        selectedPolygonMeta: first,
      ),
    );
  }
}
