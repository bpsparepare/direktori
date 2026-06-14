import 'package:equatable/equatable.dart';

class MapFocusBounds extends Equatable {
  final double south;
  final double north;
  final double west;
  final double east;

  const MapFocusBounds({
    required this.south,
    required this.north,
    required this.west,
    required this.east,
  });

  bool get isValid =>
      south >= -90 &&
      north <= 90 &&
      west >= -180 &&
      east <= 180 &&
      south <= north &&
      west <= east;

  Map<String, dynamic> toJson() {
    return {'south': south, 'north': north, 'west': west, 'east': east};
  }

  factory MapFocusBounds.fromJson(Map<String, dynamic> json) {
    return MapFocusBounds(
      south: (json['south'] as num).toDouble(),
      north: (json['north'] as num).toDouble(),
      west: (json['west'] as num).toDouble(),
      east: (json['east'] as num).toDouble(),
    );
  }

  @override
  List<Object?> get props => [south, north, west, east];
}
