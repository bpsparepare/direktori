import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:latlong2/latlong.dart';
import '../../domain/entities/map_config.dart';
import '../../domain/entities/place.dart';
import '../../domain/repositories/map_repository.dart';
import '../../domain/entities/polygon_data.dart';
import 'package:flutter/foundation.dart';

class MapRepositoryImpl implements MapRepository {
  @override
  Future<MapConfig> getInitialConfig() async {
    // Pusat peta di Parepare
    return const MapConfig(
      center: LatLng(-4.0328772052560335, 119.63160510345742),
      zoom: 13,
    );
  }

  @override
  Future<List<Place>> getPlaces() async {
    // Dummy data titik tempat di Parepare
    return const [
      Place(
        id: 'p1',
        name: 'Alun-Alun Parepare',
        description: 'Ruang publik utama di pusat Parepare.',
        position: LatLng(-4.0145, 119.6230),
      ),
      Place(
        id: 'p2',
        name: 'Pelabuhan Nusantara',
        description: 'Pelabuhan utama Parepare dengan aktivitas maritim.',
        position: LatLng(-4.0208, 119.6505),
      ),
      Place(
        id: 'p3',
        name: 'Monumen Cinta Sejati Habibie Ainun',
        description: 'Ikon kota Parepare.',
        position: LatLng(-4.0139, 119.6292),
      ),
    ];
  }

  @override
  Future<List<LatLng>> getFirstPolygonFromGeoJson(String assetPath) async {
    final String cleanPath = assetPath.trim().replaceAll(RegExp(r'^"|"$'), '');
    debugPrint('GeoJSON: attempting to load asset: $cleanPath');
    String jsonStr;
    try {
      jsonStr = await rootBundle.loadString(cleanPath);
    } catch (e) {
      debugPrint('GeoJSON: loadString failed for $cleanPath: $e');
      rethrow;
    }
    final dynamic data = json.decode(jsonStr);
    if (data is! Map ||
        data['features'] is! List ||
        (data['features'] as List).isEmpty) {
      debugPrint('GeoJSON: no features found in $cleanPath');
      return <LatLng>[];
    }
    final Map<String, dynamic> firstFeature =
        (data['features'] as List).first as Map<String, dynamic>;
    final Map<String, dynamic>? geometry =
        firstFeature['geometry'] as Map<String, dynamic>?;
    if (geometry == null) {
      debugPrint('GeoJSON: geometry is null in first feature');
      return <LatLng>[];
    }
    final String? type = geometry['type'] as String?;
    final dynamic coordinates = geometry['coordinates'];

    List<dynamic> ring;
    if (type == 'MultiPolygon') {
      if (coordinates is List &&
          coordinates.isNotEmpty &&
          coordinates[0] is List &&
          (coordinates[0] as List).isNotEmpty &&
          (coordinates[0] as List)[0] is List) {
        ring = (coordinates[0] as List)[0] as List;
      } else {
        debugPrint('GeoJSON: invalid coordinates for MultiPolygon');
        return <LatLng>[];
      }
    } else if (type == 'Polygon') {
      if (coordinates is List &&
          coordinates.isNotEmpty &&
          coordinates[0] is List) {
        ring = coordinates[0] as List;
      } else {
        debugPrint('GeoJSON: invalid coordinates for Polygon');
        return <LatLng>[];
      }
    } else {
      debugPrint('GeoJSON: unsupported geometry type: $type');
      return <LatLng>[];
    }

    final List<LatLng> points = <LatLng>[];
    for (final dynamic coord in ring) {
      if (coord is List && coord.length >= 2) {
        final double lon = (coord[0] as num).toDouble();
        final double lat = (coord[1] as num).toDouble();
        points.add(LatLng(lat, lon));
      }
    }
    debugPrint(
      'GeoJSON: loaded first polygon with ${points.length} points from $cleanPath',
    );
    return points;
  }

  @override
  Future<PolygonData> getFirstPolygonMetaFromGeoJson(String assetPath) async {
    final String cleanPath = assetPath.trim().replaceAll(RegExp(r'^"|"$'), '');
    debugPrint('GeoJSON(meta): attempting to load asset: $cleanPath');
    String jsonStr;
    try {
      jsonStr = await rootBundle.loadString(cleanPath);
    } catch (e) {
      debugPrint('GeoJSON(meta): loadString failed for $cleanPath: $e');
      rethrow;
    }
    final dynamic data = json.decode(jsonStr);
    if (data is! Map ||
        data['features'] is! List ||
        (data['features'] as List).isEmpty) {
      debugPrint('GeoJSON(meta): no features found in $cleanPath');
      return const PolygonData(
        points: <LatLng>[],
        name: null,
        kecamatan: null,
        desa: null,
        idsls: null,
      );
    }
    final Map<String, dynamic> firstFeature =
        (data['features'] as List).first as Map<String, dynamic>;
    final Map<String, dynamic>? properties =
        firstFeature['properties'] as Map<String, dynamic>?;
    final String? name = properties != null
        ? properties['nmsls'] as String?
        : null;
    final String? kec = properties != null
        ? properties['nmkec'] as String?
        : null;
    final String? desa = properties != null
        ? properties['nmdesa'] as String?
        : null;
    final String? idsls = properties != null
        ? properties['idsls'] as String?
        : null;

    final Map<String, dynamic>? geometry =
        firstFeature['geometry'] as Map<String, dynamic>?;
    if (geometry == null) {
      debugPrint('GeoJSON(meta): geometry is null in first feature');
      return PolygonData(
        points: const <LatLng>[],
        name: name,
        kecamatan: kec,
        desa: desa,
        idsls: idsls,
      );
    }
    final String? type = geometry['type'] as String?;
    final dynamic coordinates = geometry['coordinates'];

    List<dynamic> ring;
    if (type == 'MultiPolygon') {
      if (coordinates is List &&
          coordinates.isNotEmpty &&
          coordinates[0] is List &&
          (coordinates[0] as List).isNotEmpty &&
          (coordinates[0] as List)[0] is List) {
        ring = (coordinates[0] as List)[0] as List;
      } else {
        debugPrint('GeoJSON(meta): invalid coordinates for MultiPolygon');
        return PolygonData(
          points: const <LatLng>[],
          name: name,
          kecamatan: kec,
          desa: desa,
          idsls: idsls,
        );
      }
    } else if (type == 'Polygon') {
      if (coordinates is List &&
          coordinates.isNotEmpty &&
          coordinates[0] is List) {
        ring = coordinates[0] as List;
      } else {
        debugPrint('GeoJSON(meta): invalid coordinates for Polygon');
        return PolygonData(
          points: const <LatLng>[],
          name: name,
          kecamatan: kec,
          desa: desa,
          idsls: idsls,
        );
      }
    } else {
      debugPrint('GeoJSON(meta): unsupported geometry type: $type');
      return PolygonData(
        points: const <LatLng>[],
        name: name,
        kecamatan: kec,
        desa: desa,
        idsls: idsls,
      );
    }

    final List<LatLng> points = <LatLng>[];
    for (final dynamic coord in ring) {
      if (coord is List && coord.length >= 2) {
        final double lon = (coord[0] as num).toDouble();
        final double lat = (coord[1] as num).toDouble();
        points.add(LatLng(lat, lon));
      }
    }
    debugPrint(
      'GeoJSON(meta): loaded first polygon with ${points.length} points and name "$name" from $cleanPath',
    );
    return PolygonData(
      points: points,
      name: name,
      kecamatan: kec,
      desa: desa,
      idsls: idsls,
    );
  }

  @override
  Future<List<PolygonData>> getAllPolygonsMetaFromGeoJson(
    String assetPath,
  ) async {
    final String cleanPath = assetPath.trim().replaceAll(RegExp(r'^"|\"$'), '');
    debugPrint('GeoJSON(list): attempting to load asset: $cleanPath');
    String jsonStr;
    try {
      jsonStr = await rootBundle.loadString(cleanPath);
    } catch (e) {
      debugPrint('GeoJSON(list): loadString failed for $cleanPath: $e');
      rethrow;
    }
    final dynamic data = json.decode(jsonStr);

    final List<PolygonData> results = <PolygonData>[];

    List<dynamic> features;
    if (data is Map && data['features'] is List) {
      features = data['features'] as List<dynamic>;
    } else if (data is List) {
      features = data;
    } else if (data is Map) {
      features = [data];
    } else {
      debugPrint('GeoJSON(list): unsupported root format');
      return results;
    }

    for (final dynamic f in features) {
      if (f is! Map<String, dynamic>) continue;
      final Map<String, dynamic> feature = f;
      final Map<String, dynamic>? properties =
          feature['properties'] as Map<String, dynamic>?;
      final String? name = properties != null
          ? properties['nmsls'] as String?
          : null;
      final String? kec = properties != null
          ? properties['nmkec'] as String?
          : null;
      final String? desa = properties != null
          ? properties['nmdesa'] as String?
          : null;
      final String? idsls = properties != null
          ? properties['idsls'] as String?
          : null;

      final Map<String, dynamic>? geometry =
          feature['geometry'] as Map<String, dynamic>?;
      if (geometry == null) {
        results.add(
          PolygonData(
            points: const <LatLng>[],
            name: name,
            kecamatan: kec,
            desa: desa,
            idsls: idsls,
          ),
        );
        continue;
      }
      final String? type = geometry['type'] as String?;
      final dynamic coordinates = geometry['coordinates'];

      List<dynamic>? ring;
      if (type == 'MultiPolygon') {
        if (coordinates is List &&
            coordinates.isNotEmpty &&
            coordinates[0] is List &&
            (coordinates[0] as List).isNotEmpty &&
            (coordinates[0] as List)[0] is List) {
          ring = (coordinates[0] as List)[0] as List;
        }
      } else if (type == 'Polygon') {
        if (coordinates is List &&
            coordinates.isNotEmpty &&
            coordinates[0] is List) {
          ring = coordinates[0] as List;
        }
      }

      if (ring == null) {
        debugPrint('GeoJSON(list): invalid geometry for a feature, type=$type');
        results.add(
          PolygonData(
            points: const <LatLng>[],
            name: name,
            kecamatan: kec,
            desa: desa,
            idsls: idsls,
          ),
        );
        continue;
      }

      final List<LatLng> points = <LatLng>[];
      for (final dynamic coord in ring) {
        if (coord is List && coord.length >= 2) {
          final double lon = (coord[0] as num).toDouble();
          final double lat = (coord[1] as num).toDouble();
          points.add(LatLng(lat, lon));
        }
      }
      results.add(
        PolygonData(
          points: points,
          name: name,
          kecamatan: kec,
          desa: desa,
          idsls: idsls,
        ),
      );
    }

    debugPrint(
      'GeoJSON(list): loaded ${results.length} polygons with names from $cleanPath',
    );
    return results;
  }
}
