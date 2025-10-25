import 'package:latlong2/latlong.dart';
import '../entities/map_config.dart';
import '../entities/place.dart';
import '../entities/polygon_data.dart';
import '../../data/models/direktori_model.dart';

abstract class MapRepository {
  Future<MapConfig> getInitialConfig();
  Future<List<Place>> getPlaces();
  Future<List<LatLng>> getFirstPolygonFromGeoJson(String assetPath);
  Future<PolygonData> getFirstPolygonMetaFromGeoJson(String assetPath);
  Future<List<PolygonData>> getAllPolygonsMetaFromGeoJson(String assetPath);
  Future<List<DirektoriModel>> searchDirectoriesWithoutCoordinates(
    String query,
  );
  Future<bool> updateDirectoryCoordinates(String id, double lat, double lng);
  Future<bool> insertDirectory(DirektoriModel directory);
  // New method to support delete-or-close behavior per id_sbr
  Future<bool> deleteOrCloseDirectoryById(String id);
}
