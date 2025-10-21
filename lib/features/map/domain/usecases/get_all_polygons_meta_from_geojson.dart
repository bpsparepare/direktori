import '../entities/polygon_data.dart';
import '../repositories/map_repository.dart';

class GetAllPolygonsMetaFromGeoJson {
  final MapRepository repository;
  GetAllPolygonsMetaFromGeoJson(this.repository);

  Future<List<PolygonData>> call(String assetPath) {
    return repository.getAllPolygonsMetaFromGeoJson(assetPath);
  }
}