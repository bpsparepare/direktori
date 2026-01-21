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

class PlacesRefreshRequested extends MapEvent {
  final bool onlyToday;
  const PlacesRefreshRequested({this.onlyToday = false});
  @override
  List<Object?> get props => [onlyToday];
}

class PlacesInBoundsRequested extends MapEvent {
  final double south;
  final double north;
  final double west;
  final double east;
  const PlacesInBoundsRequested(this.south, this.north, this.west, this.east);
  @override
  List<Object?> get props => [south, north, west, east];
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
  const PolygonsListRequested({
    this.assetPath = 'assets/geojson/final_sls.geojson',
  });
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

class MultiplePolygonsSelected extends MapEvent {
  final List<PolygonData> polygons;
  const MultiplePolygonsSelected(this.polygons);
  @override
  List<Object?> get props => [polygons];
}

class TemporaryMarkerAdded extends MapEvent {
  final LatLng position;
  const TemporaryMarkerAdded(this.position);
  @override
  List<Object?> get props => [position];
}

class TemporaryMarkerRemoved extends MapEvent {
  const TemporaryMarkerRemoved();
}
