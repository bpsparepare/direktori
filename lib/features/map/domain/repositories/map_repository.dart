import 'package:latlong2/latlong.dart';
import '../entities/map_config.dart';
import '../entities/place.dart';
import '../entities/polygon_data.dart';

abstract class MapRepository {
  Future<MapConfig> getInitialConfig();
  Future<List<Place>> getPlaces();
  Future<List<LatLng>> getFirstPolygonFromGeoJson(String assetPath);
  Future<PolygonData> getFirstPolygonMetaFromGeoJson(String assetPath);
  Future<List<PolygonData>> getAllPolygonsMetaFromGeoJson(String assetPath);
}