import 'package:latlong2/latlong.dart';

class MapUtils {
  /// Checks if a point is inside a polygon using the Ray Casting algorithm.
  static bool isPointInPolygon(LatLng point, List<LatLng> polygon) {
    bool c = false;
    for (int i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      if (((polygon[i].latitude > point.latitude) !=
              (polygon[j].latitude > point.latitude)) &&
          (point.longitude <
              (polygon[j].longitude - polygon[i].longitude) *
                      (point.latitude - polygon[i].latitude) /
                      (polygon[j].latitude - polygon[i].latitude) +
                  polygon[i].longitude)) {
        c = !c;
      }
    }
    return c;
  }
}
