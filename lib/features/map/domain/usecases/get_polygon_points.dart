import 'package:latlong2/latlong.dart';
import '../repositories/map_repository.dart';

class GetPolygonPoints {
  final MapRepository repository;

  GetPolygonPoints(this.repository);

  Future<List<LatLng>> call(String idsls) {
    return repository.getPolygonPoints(idsls);
  }
}
