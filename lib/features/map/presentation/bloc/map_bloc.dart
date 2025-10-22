import 'package:bloc/bloc.dart';
import 'package:flutter/foundation.dart';
import '../../domain/usecases/get_initial_map_config.dart';
import '../../domain/usecases/get_places.dart';
import '../../domain/usecases/get_first_polygon_meta_from_geojson.dart';
import '../../domain/usecases/get_all_polygons_meta_from_geojson.dart';
import 'map_event.dart';
import 'map_state.dart';

class MapBloc extends Bloc<MapEvent, MapState> {
  final GetInitialMapConfig getInitialMapConfig;
  final GetPlaces getPlaces;
  final GetFirstPolygonMetaFromGeoJson getFirstPolygonMeta;
  final GetAllPolygonsMetaFromGeoJson getAllPolygonsMeta;

  MapBloc({
    required this.getInitialMapConfig,
    required this.getPlaces,
    required this.getFirstPolygonMeta,
    required this.getAllPolygonsMeta,
  }) : super(const MapState()) {
    on<MapInitRequested>(_onInit);
    on<PlacesRequested>(_onPlacesRequested);
    on<PolygonRequested>(_onPolygonRequested);
    on<PolygonsListRequested>(_onPolygonsListRequested);
    on<PolygonSelectedByIndex>(_onPolygonSelectedByIndex);
    on<PolygonSelected>(_onPolygonSelected);
    on<PlaceSelected>(_onPlaceSelected);
    on<PlaceCleared>(_onPlaceCleared);
    on<TemporaryMarkerSet>(_onTemporaryMarkerSet);
    on<TemporaryMarkerCleared>(_onTemporaryMarkerCleared);
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

  Future<void> _onPolygonRequested(
    PolygonRequested event,
    Emitter<MapState> emit,
  ) async {
    try {
      final meta = await getFirstPolygonMeta(event.assetPath);
      debugPrint(
        'BLoC: polygon points loaded = ${meta.points.length}, label = ${meta.name}',
      );
      emit(
        state.copyWith(
          polygon: meta.points,
          polygonLabel: meta.name,
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
      // default selection: keep current if any, else first item
      var selPoints = state.polygon;
      String? selLabel = state.polygonLabel;
      var selMeta = state.selectedPolygonMeta;
      if (selPoints.isEmpty && list.isNotEmpty) {
        selPoints = list.first.points;
        selLabel = list.first.name;
        selMeta = list.first;
      }
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
    emit(
      state.copyWith(
        polygon: sel.points,
        polygonLabel: sel.name,
        selectedPolygonMeta: sel,
      ),
    );
  }

  void _onPolygonSelected(
    PolygonSelected event,
    Emitter<MapState> emit,
  ) {
    emit(
      state.copyWith(
        polygon: event.polygon.points,
        polygonLabel: event.polygon.name,
        selectedPolygonMeta: event.polygon,
      ),
    );
  }

  void _onPlaceSelected(PlaceSelected event, Emitter<MapState> emit) {
    emit(state.copyWith(selectedPlace: event.place));
  }

  void _onPlaceCleared(PlaceCleared event, Emitter<MapState> emit) {
    emit(state.copyWith(selectedPlace: null));
  }

  void _onTemporaryMarkerSet(TemporaryMarkerSet event, Emitter<MapState> emit) {
    emit(state.copyWith(temporaryMarker: event.position));
  }

  void _onTemporaryMarkerCleared(TemporaryMarkerCleared event, Emitter<MapState> emit) {
    emit(state.copyWith(temporaryMarker: null));
  }
}
