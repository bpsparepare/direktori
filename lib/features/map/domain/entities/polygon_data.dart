import 'package:latlong2/latlong.dart';

class PolygonData {
  final List<LatLng> points;
  final String? name; // nmsls
  final String? kecamatan; // nmkec
  final String? desa; // nmdesa

  const PolygonData({required this.points, this.name, this.kecamatan, this.desa});
}