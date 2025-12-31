import 'package:latlong2/latlong.dart';
import '../entities/map_config.dart';
import '../entities/place.dart';
import '../entities/polygon_data.dart';
import '../../data/models/direktori_model.dart';

abstract class MapRepository {
  Future<MapConfig> getInitialConfig();
  Future<List<Place>> getPlaces();
  Future<List<Place>> getPlacesInBounds(
    double south,
    double north,
    double west,
    double east,
  );
  Future<List<LatLng>> getFirstPolygonFromGeoJson(String assetPath);
  Future<PolygonData> getFirstPolygonMetaFromGeoJson(String assetPath);
  Future<List<PolygonData>> getAllPolygonsMetaFromGeoJson(String assetPath);
  Future<List<DirektoriModel>> searchDirectoriesWithoutCoordinates(
    String query,
  );
  Future<List<DirektoriModel>> listDirectoriesWithoutCoordinates({
    required int page,
    required int limit,
    String? orderBy,
    bool ascending,
  });
  Future<List<DirektoriModel>> searchDirectoriesWithoutCoordinatesPaged({
    required String query,
    required int page,
    required int limit,
    String? orderBy,
    bool ascending,
  });
  Future<List<DirektoriModel>> listAllDirectories({
    required int page,
    required int limit,
    String? orderBy,
    bool ascending,
  });
  Future<List<DirektoriModel>> searchAllDirectoriesPaged({
    required String query,
    required int page,
    required int limit,
    String? orderBy,
    bool ascending,
  });
  Future<int> countDirectoriesWithoutCoordinates();
  Future<Map<String, int>> getDirektoriStats({DateTime? updatedThreshold});
  Future<int> countAllDirectories({String? search});
  Future<bool> updateDirectoryCoordinates(String id, double lat, double lng);
  Future<bool> insertDirectory(DirektoriModel directory);
  Future<String?> insertDirectoryAndGetId(DirektoriModel directory);
  Future<bool> updateDirectory(DirektoriModel directory);
  Future<DirektoriModel?> getDirectoryById(String id);
  // New method to support delete-or-close behavior per id_sbr
  Future<bool> deleteOrCloseDirectoryById(String id);
  // Get KBLI title by code
  Future<String?> getKbliJudul(String kodeKbli);
  Future<bool> markDirectoryAsDuplicate(String id, String parentIdSbr);
  Future<List<Map<String, dynamic>>> getDirektoriLengkapData();
  Future<List<Map<String, dynamic>>> getDirektoriLengkapSbrData();
}
