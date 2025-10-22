import 'package:equatable/equatable.dart';
import 'package:latlong2/latlong.dart';
import '../../domain/entities/place.dart';
import '../../domain/entities/polygon_data.dart';

abstract class MapEvent extends Equatable {
  const MapEvent();
  @override
  List<Object?> get props => [];
}

class MapInitRequested extends MapEvent {
  const MapInitRequested();
}

class PlacesRequested extends MapEvent {
  const PlacesRequested();
}

class PlaceSelected extends MapEvent {
  final Place place;
  const PlaceSelected(this.place);
  @override
  List<Object?> get props => [place];
}

class PlaceCleared extends MapEvent {
  const PlaceCleared();
}

class PolygonRequested extends MapEvent {
  final String assetPath;
  const PolygonRequested({this.assetPath = 'assets/geojson/final_sls.geojson'});
  @override
  List<Object?> get props => [assetPath];
}

class PolygonsListRequested extends MapEvent {
  final String assetPath;
  const PolygonsListRequested({this.assetPath = 'assets/geojson/final_sls.geojson'});
  @override
  List<Object?> get props => [assetPath];
}

class PolygonSelectedByIndex extends MapEvent {
  final int index;
  const PolygonSelectedByIndex(this.index);
  @override
  List<Object?> get props => [index];
}

class PolygonSelected extends MapEvent {
  final PolygonData polygon;
  const PolygonSelected(this.polygon);
  @override
  List<Object?> get props => [polygon];
}

class TemporaryMarkerSet extends MapEvent {
  final LatLng? position;
  const TemporaryMarkerSet(this.position);
  @override
  List<Object?> get props => [position];
}

class TemporaryMarkerCleared extends MapEvent {
  const TemporaryMarkerCleared();
}