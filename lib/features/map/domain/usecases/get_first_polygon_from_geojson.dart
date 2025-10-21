import 'package:latlong2/latlong.dart';
import '../repositories/map_repository.dart';

class GetFirstPolygonFromGeoJson {
  final MapRepository repository;
  GetFirstPolygonFromGeoJson(this.repository);

  Future<List<LatLng>> call(String assetPath) {
    return repository.getFirstPolygonFromGeoJson(assetPath);
  }
}