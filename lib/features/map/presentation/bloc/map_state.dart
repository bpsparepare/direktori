import 'package:equatable/equatable.dart';
import 'package:latlong2/latlong.dart';
import '../../domain/entities/map_config.dart';
import '../../domain/entities/map_focus_bounds.dart';
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
  final List<PolygonData> assignmentPolygons;
  final PolygonData? selectedPolygonMeta;
  final List<PolygonData> selectedPolygons; // New field for multiple selection
  final bool showAssignmentPolygons;
  final MapFocusBounds? assignmentFocusBounds;
  final int assignmentWilayahCount;
  final LatLng? temporaryMarker;
  final String? error;
  // Store last bounds to preserve view during refresh
  final double? lastSouth;
  final double? lastNorth;
  final double? lastWest;
  final double? lastEast;

  const MapState({
    this.status = MapStatus.initial,
    this.config,
    this.places = const [],
    this.selectedPlace,
    this.polygon = const [],
    this.polygonLabel,
    this.polygonsMeta = const [],
    this.assignmentPolygons = const [],
    this.selectedPolygonMeta,
    this.selectedPolygons = const [], // Initialize
    this.showAssignmentPolygons = false,
    this.assignmentFocusBounds,
    this.assignmentWilayahCount = 0,
    this.temporaryMarker,
    this.error,
    this.lastSouth,
    this.lastNorth,
    this.lastWest,
    this.lastEast,
  });

  MapState copyWith({
    MapStatus? status,
    MapConfig? config,
    List<Place>? places,
    Place? selectedPlace,
    List<LatLng>? polygon,
    String? polygonLabel,
    List<PolygonData>? polygonsMeta,
    List<PolygonData>? assignmentPolygons,
    PolygonData? selectedPolygonMeta,
    List<PolygonData>? selectedPolygons, // Parameter
    bool? showAssignmentPolygons,
    MapFocusBounds? assignmentFocusBounds,
    int? assignmentWilayahCount,
    LatLng? temporaryMarker,
    String? error,
    bool clearSelectedPlace = false,
    bool clearTemporaryMarker = false,
    bool clearSelectedPolygonMeta = false,
    bool clearAssignmentFocusBounds = false,
    double? lastSouth,
    double? lastNorth,
    double? lastWest,
    double? lastEast,
  }) {
    return MapState(
      status: status ?? this.status,
      config: config ?? this.config,
      places: places ?? this.places,
      selectedPlace: clearSelectedPlace
          ? null
          : (selectedPlace ?? this.selectedPlace),
      polygon: polygon ?? this.polygon,
      polygonLabel: polygonLabel ?? this.polygonLabel,
      polygonsMeta: polygonsMeta ?? this.polygonsMeta,
      assignmentPolygons: assignmentPolygons ?? this.assignmentPolygons,
      selectedPolygonMeta: clearSelectedPolygonMeta
          ? null
          : (selectedPolygonMeta ?? this.selectedPolygonMeta),
      selectedPolygons: selectedPolygons ?? this.selectedPolygons, // Assign
      showAssignmentPolygons:
          showAssignmentPolygons ?? this.showAssignmentPolygons,
      assignmentFocusBounds: clearAssignmentFocusBounds
          ? null
          : (assignmentFocusBounds ?? this.assignmentFocusBounds),
      assignmentWilayahCount:
          assignmentWilayahCount ?? this.assignmentWilayahCount,
      temporaryMarker: clearTemporaryMarker
          ? null
          : (temporaryMarker ?? this.temporaryMarker),
      error: error ?? this.error,
      lastSouth: lastSouth ?? this.lastSouth,
      lastNorth: lastNorth ?? this.lastNorth,
      lastWest: lastWest ?? this.lastWest,
      lastEast: lastEast ?? this.lastEast,
    );
  }

  @override
  List<Object?> get props => [
    status,
    config,
    places,
    selectedPlace,
    polygon,
    polygonLabel,
    polygonsMeta,
    assignmentPolygons,
    selectedPolygonMeta,
    selectedPolygons, // Add to props
    showAssignmentPolygons,
    assignmentFocusBounds,
    assignmentWilayahCount,
    temporaryMarker,
    error,
    lastSouth,
    lastNorth,
    lastWest,
    lastEast,
  ];
}
