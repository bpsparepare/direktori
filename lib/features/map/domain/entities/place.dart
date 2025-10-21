import 'package:latlong2/latlong.dart';

class Place {
  final String id;
  final String name;
  final String description;
  final LatLng position;

  const Place({
    required this.id,
    required this.name,
    required this.description,
    required this.position,
  });
}