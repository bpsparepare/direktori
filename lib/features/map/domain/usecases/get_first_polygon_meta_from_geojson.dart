import '../entities/polygon_data.dart';
import '../repositories/map_repository.dart';

class GetFirstPolygonMetaFromGeoJson {
  final MapRepository repository;
  GetFirstPolygonMetaFromGeoJson(this.repository);

  Future<PolygonData> call(String assetPath) {
    return repository.getFirstPolygonMetaFromGeoJson(assetPath);
  }
}