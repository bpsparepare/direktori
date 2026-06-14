import 'package:latlong2/latlong.dart';

class PolygonData {
  final List<LatLng> points;
  final String? name; // nmsls
  final String? kecamatan; // nmkec
  final String? desa; // nmdesa
  final String? idsls; // idsls for sorting
  final String? idsubsls; // idsubsls for assignment matching
  final String? subsls; // suffix subsls for display
  final String? kodePos; // kode_pos from GeoJSON

  const PolygonData({
    required this.points,
    this.name,
    this.kecamatan,
    this.desa,
    this.idsls,
    this.idsubsls,
    this.subsls,
    this.kodePos,
  });
}
