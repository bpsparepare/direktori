import 'dart:io';
import 'dart:convert';

void main() {
  final File inputFile = File(
    '/Users/nasrul/flutter/direktori/assets/geojson/final_sls.geojson',
  );
  final File metadataFile = File(
    '/Users/nasrul/flutter/direktori/assets/json/sls_metadata.json',
  );
  final File optimizedFile = File(
    '/Users/nasrul/flutter/direktori/assets/geojson/final_sls_optimized.json',
  );

  if (!inputFile.existsSync()) {
    print('Input file not found!');
    return;
  }

  print('Reading input file...');
  final String content = inputFile.readAsStringSync();
  final Map<String, dynamic> geoJson = json.decode(content);
  final List<dynamic> features = geoJson['features'];

  final List<Map<String, dynamic>> metadataList = [];
  final List<Map<String, dynamic>> optimizedFeatures = [];

  print('Processing ${features.length} features...');

  for (final feature in features) {
    final Map<String, dynamic> properties = feature['properties'];
    final geometry = feature['geometry'];

    // Extract required properties
    final Map<String, dynamic> optimizedProps = {
      'idsls': properties['idsls'],
      'nmsls': properties['nmsls'],
      'nmdesa': properties['nmdesa'],
      'nmkec': properties['nmkec'],
      'kode_pos': properties['kode_pos'],
    };

    // Metadata (no geometry)
    metadataList.add(optimizedProps);

    // Optimized Feature
    optimizedFeatures.add({
      'type': 'Feature',
      'properties': optimizedProps,
      'geometry': geometry,
    });
  }

  // Write Metadata
  print('Writing metadata to ${metadataFile.path}...');
  metadataFile.writeAsStringSync(json.encode(metadataList));

  // Write Optimized GeoJSON
  final Map<String, dynamic> optimizedGeoJson = {
    'type': 'FeatureCollection',
    'features': optimizedFeatures,
  };

  print('Writing optimized GeoJSON to ${optimizedFile.path}...');
  optimizedFile.writeAsStringSync(json.encode(optimizedGeoJson));

  print('Done!');
}
