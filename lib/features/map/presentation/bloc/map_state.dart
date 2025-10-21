import 'package:equatable/equatable.dart';
import 'package:latlong2/latlong.dart';
import '../../domain/entities/map_config.dart';
import '../../domain/entities/place.dart';
import '../../domain/entities/polygon_data.dart';

enum MapStatus { initial, loading, success, failure }

class MapState extends Equatable {
  final MapStatus status;
  final MapConfig? config;
  final List<Place> places;
  final Place? selectedPlace;
  final List<LatLng> polygon;
  final String? polygonLabel;
  final List<PolygonData> polygonsMeta;
  final PolygonData? selectedPolygonMeta;
  final String? error;

  const MapState({
    this.status = MapStatus.initial,
    this.config,
    this.places = const [],
    this.selectedPlace,
    this.polygon = const [],
    this.polygonLabel,
    this.polygonsMeta = const [],
    this.selectedPolygonMeta,
    this.error,
  });

  MapState copyWith({
    MapStatus? status,
    MapConfig? config,
    List<Place>? places,
    Place? selectedPlace,
    List<LatLng>? polygon,
    String? polygonLabel,
    List<PolygonData>? polygonsMeta,
    PolygonData? selectedPolygonMeta,
    String? error,
  }) {
    return MapState(
      status: status ?? this.status,
      config: config ?? this.config,
      places: places ?? this.places,
      selectedPlace: selectedPlace ?? this.selectedPlace,
      polygon: polygon ?? this.polygon,
      polygonLabel: polygonLabel ?? this.polygonLabel,
      polygonsMeta: polygonsMeta ?? this.polygonsMeta,
      selectedPolygonMeta: selectedPolygonMeta ?? this.selectedPolygonMeta,
      error: error ?? this.error,
    );
  }

  @override
  List<Object?> get props => [status, config, places, selectedPlace, polygon, polygonLabel, polygonsMeta, selectedPolygonMeta, error];
}