import 'package:latlong2/latlong.dart';

class MapConfig {
  final LatLng center;
  final double zoom;
  final double defaultOffsetX;
  final double defaultOffsetY;

  const MapConfig({
    required this.center,
    required this.zoom,
    this.defaultOffsetX = 0.0,
    this.defaultOffsetY = 0.0,
  });

  MapConfig copyWith({
    LatLng? center,
    double? zoom,
    double? defaultOffsetX,
    double? defaultOffsetY,
  }) {
    return MapConfig(
      center: center ?? this.center,
      zoom: zoom ?? this.zoom,
      defaultOffsetX: defaultOffsetX ?? this.defaultOffsetX,
      defaultOffsetY: defaultOffsetY ?? this.defaultOffsetY,
    );
  }
}
