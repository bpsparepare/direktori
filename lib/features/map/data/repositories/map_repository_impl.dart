import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/entities/map_config.dart';
import '../../domain/entities/place.dart';
import '../../domain/repositories/map_repository.dart';
import '../../domain/entities/polygon_data.dart';
import '../models/direktori_model.dart';
import '../../../../core/config/supabase_config.dart';
import 'package:flutter/foundation.dart';
import 'scraping_repository_impl.dart';

class MapRepositoryImpl implements MapRepository {
  final SupabaseClient _supabaseClient = SupabaseConfig.client;

  @override
  Future<MapConfig> getInitialConfig() async {
    // Pusat peta di Parepare
    return const MapConfig(
      center: LatLng(-4.0328772052560335, 119.63160510345742),
      zoom: 13,
      // Default offset untuk Esri satellite maps
      // Nilai disesuaikan berdasarkan hasil debug: X: -4.6, Y: 15
      defaultOffsetX: -32,
      defaultOffsetY: 17.0,
    );
  }

  @override
  Future<bool> updateDirectory(DirektoriModel directory) async {
    try {
      await _supabaseClient
          .from('direktori')
          .update({
            'id_sbr': directory.idSbr,
            'nama_usaha': directory.namaUsaha,
            'nama_komersial_usaha': directory.namaKomersialUsaha,
            'alamat': directory.alamat,
            'pemilik': directory.pemilik,
            'nik_pemilik': directory.nikPemilik,
            'nomor_telepon': directory.nomorTelepon,
            'nomor_whatsapp': directory.nomorWhatsapp,
            'email': directory.email,
            'website': directory.website,
            'latitude': directory.latitude ?? directory.lat,
            'longitude': directory.longitude ?? directory.long,
            'id_sls': directory.idSls,
            'kd_prov': directory.kdProv,
            'kd_kab': directory.kdKab,
            'kd_kec': directory.kdKec,
            'kd_desa': directory.kdDesa,
            'kd_sls': directory.kdSls,
            'kode_pos': directory.kodePos,
            'nama_sls': directory.nmSls,
            'skala_usaha': directory.skalaUsaha,
            'jenis_perusahaan': directory.jenisPerusahaan,
            'keterangan': directory.keterangan,
            'nib': directory.nib,
            'url_gambar': directory.urlGambar,
            'sumber_data': directory.sumberData,
            'keberadaan_usaha': directory.keberadaanUsaha ?? 1,
            'jenis_kepemilikan_usaha': directory.jenisKepemilikanUsaha,
            'bentuk_badan_hukum_usaha': directory.bentukBadanHukumUsaha,
            'deskripsi_badan_usaha_lainnya':
                directory.deskripsiBadanUsahaLainnya,
            'tahun_berdiri': directory.tahunBerdiri,
            'jaringan_usaha': directory.jaringanUsaha,
            'sektor_institusi': directory.sektorInstitusi,
            'tenaga_kerja': directory.tenagaKerja,
            'kbli': directory.kbli,
            'tag': directory.tag,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', directory.id!);
      return true;
    } catch (e) {
      print('Error updating directory: $e');
      return false;
    }
  }

  @override
  Future<List<DirektoriModel>> searchDirectoriesWithoutCoordinates(
    String query,
  ) async {
    try {
      final response = await _supabaseClient
          .from('direktori')
          .select('*, wilayah(*)')
          .or('latitude.is.null,longitude.is.null')
          .ilike('nama_usaha', '%$query%')
          .limit(20);

      return (response as List)
          .map((json) => DirektoriModel.fromJson(json))
          .toList();
    } catch (e) {
      print('Error searching directories without coordinates: $e');
      return [];
    }
  }

  @override
  Future<bool> updateDirectoryCoordinates(
    String id,
    double lat,
    double lng,
  ) async {
    try {
      await _supabaseClient
          .from('direktori')
          .update({
            'latitude': lat,
            'longitude': lng,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', id);
      return true;
    } catch (e) {
      print('Error updating directory coordinates: $e');
      return false;
    }
  }

  Future<bool> updateDirectoryCoordinatesWithRegionalData(
    String id,
    double lat,
    double lng,
    String idSls,
    String kdProv,
    String kdKab,
    String kdKec,
    String kdDesa,
    String kdSls,
    String? kodePos,
    String? namaSls,
  ) async {
    try {
      await _supabaseClient
          .from('direktori')
          .update({
            'latitude': lat,
            'longitude': lng,
            'id_sls': idSls,
            'kd_prov': kdProv,
            'kd_kab': kdKab,
            'kd_kec': kdKec,
            'kd_desa': kdDesa,
            'kd_sls': kdSls,
            'kode_pos': kodePos,
            'nama_sls': namaSls,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', id);
      return true;
    } catch (e) {
      print('Error updating directory coordinates with regional data: $e');
      return false;
    }
  }

  @override
  Future<bool> insertDirectory(DirektoriModel directory) async {
    try {
      await _supabaseClient.from('direktori').insert({
        'id_sbr': directory.idSbr,
        'nama_usaha': directory.namaUsaha,
        'nama_komersial_usaha': directory.namaKomersialUsaha,
        'alamat': directory.alamat,
        'pemilik': directory.pemilik,
        'nik_pemilik': directory.nikPemilik,
        'nomor_telepon': directory.nomorTelepon,
        'nomor_whatsapp': directory.nomorWhatsapp,
        'email': directory.email,
        'website': directory.website,
        'latitude': directory.latitude ?? directory.lat,
        'longitude': directory.longitude ?? directory.long,
        'id_sls': directory.idSls,
        'kd_prov': directory.kdProv,
        'kd_kab': directory.kdKab,
        'kd_kec': directory.kdKec,
        'kd_desa': directory.kdDesa,
        'kd_sls': directory.kdSls,
        'kode_pos': directory.kodePos,
        'nama_sls': directory.nmSls,
        'skala_usaha': directory.skalaUsaha,
        'jenis_perusahaan': directory.jenisPerusahaan,
        'keterangan': directory.keterangan,
        'nib': directory.nib,
        'url_gambar': directory.urlGambar,
        'sumber_data': directory.sumberData,
        'keberadaan_usaha': directory.keberadaanUsaha ?? 1,
        'jenis_kepemilikan_usaha': directory.jenisKepemilikanUsaha,
        'bentuk_badan_hukum_usaha': directory.bentukBadanHukumUsaha,
        'deskripsi_badan_usaha_lainnya': directory.deskripsiBadanUsahaLainnya,
        'tahun_berdiri': directory.tahunBerdiri,
        'jaringan_usaha': directory.jaringanUsaha,
        'sektor_institusi': directory.sektorInstitusi,
        'tenaga_kerja': directory.tenagaKerja,
        'kbli': directory.kbli,
        'tag': directory.tag,
        'created_at':
            directory.createdAt?.toIso8601String() ??
            DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });
      return true;
    } catch (e) {
      print('Error inserting directory: $e');
      return false;
    }
  }

  // New method to insert directory and return the new ID
  Future<String?> insertDirectoryAndGetId(DirektoriModel directory) async {
    try {
      final response = await _supabaseClient
          .from('direktori')
          .insert({
            'id_sbr': directory.idSbr,
            'nama_usaha': directory.namaUsaha,
            'nama_komersial_usaha': directory.namaKomersialUsaha,
            'alamat': directory.alamat,
            'pemilik': directory.pemilik,
            'nik_pemilik': directory.nikPemilik,
            'nomor_telepon': directory.nomorTelepon,
            'nomor_whatsapp': directory.nomorWhatsapp,
            'email': directory.email,
            'website': directory.website,
            'latitude': directory.latitude ?? directory.lat,
            'longitude': directory.longitude ?? directory.long,
            'id_sls': directory.idSls,
            'kd_prov': directory.kdProv,
            'kd_kab': directory.kdKab,
            'kd_kec': directory.kdKec,
            'kd_desa': directory.kdDesa,
            'kd_sls': directory.kdSls,
            'kode_pos': directory.kodePos,
            'nama_sls': directory.nmSls,
            'skala_usaha': directory.skalaUsaha,
            'jenis_perusahaan': directory.jenisPerusahaan,
            'keterangan': directory.keterangan,
            'nib': directory.nib,
            'url_gambar': directory.urlGambar,
            'sumber_data': directory.sumberData,
            'keberadaan_usaha': directory.keberadaanUsaha ?? 1,
            'jenis_kepemilikan_usaha': directory.jenisKepemilikanUsaha,
            'bentuk_badan_hukum_usaha': directory.bentukBadanHukumUsaha,
            'deskripsi_badan_usaha_lainnya':
                directory.deskripsiBadanUsahaLainnya,
            'tahun_berdiri': directory.tahunBerdiri,
            'jaringan_usaha': directory.jaringanUsaha,
            'sektor_institusi': directory.sektorInstitusi,
            'tenaga_kerja': directory.tenagaKerja,
            'kbli': directory.kbli,
            'tag': directory.tag,
            'created_at':
                directory.createdAt?.toIso8601String() ??
                DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .select('id')
          .single();

      if (response != null && response['id'] != null) {
        final newId = response['id'].toString();
        print('✅ [DEBUG] Directory inserted with new ID: $newId');
        return newId;
      }

      return null;
    } catch (e) {
      print('Error inserting directory and getting ID: $e');
      return null;
    }
  }

  @override
  Future<List<Place>> getPlaces() async {
    try {
      // Query data direktori dari Supabase dengan join ke tabel wilayah
      final response = await _supabaseClient
          .from('direktori')
          .select('''
            *,
            wilayah(*)
          ''')
          .eq('keberadaan_usaha', 1) // hanya ambil yang aktif (asumsi: 1)
          .not('latitude', 'is', null) // hanya yang punya koordinat baru
          .not('longitude', 'is', null)
          .order('updated_at', ascending: false)
          .order('created_at', ascending: false)
          .limit(500); // Batasi untuk performa

      if (response.isEmpty) {
        debugPrint('MapRepository: No data found in direktori table');
        return [];
      }

      // Konversi response ke DirektoriModel lalu ke Place
      final List<Place> places = [];

      for (final item in response) {
        try {
          // Flatten data wilayah ke level utama untuk kemudahan parsing
          final Map<String, dynamic> flattenedData = Map<String, dynamic>.from(
            item,
          );

          if (item['wilayah'] != null && item['wilayah'] is Map) {
            final wilayahData = item['wilayah'] as Map<String, dynamic>;
            flattenedData.addAll(wilayahData);
          }

          final direktori = DirektoriModel.fromJson(flattenedData);

          // Hanya tambahkan jika memiliki koordinat yang valid
          if (direktori.hasValidCoordinates) {
            places.add(direktori.toPlace());
          }
        } catch (e) {
          debugPrint('MapRepository: Error parsing direktori item: $e');
          // Skip item yang error, lanjutkan ke item berikutnya
          continue;
        }
      }

      debugPrint(
        'MapRepository: Successfully loaded ${places.length} places from Supabase',
      );

      // Jika tidak ada data yang valid, return list kosong
      if (places.isEmpty) {
        debugPrint(
          'MapRepository: No valid places found, returning empty list',
        );
        // Tetap coba load scraped places meski direktori kosong
        try {
          final scraped = await ScrapingRepositoryImpl()
              .getScrapedPlacesAsPlace();
          debugPrint('MapRepository: Loaded ${scraped.length} scraped places');
          return scraped;
        } catch (e) {
          debugPrint('MapRepository: Failed to load scraped places: $e');
          return [];
        }
      }
      // Gabungkan dengan tempat hasil scraping
      try {
        final scraped = await ScrapingRepositoryImpl()
            .getScrapedPlacesAsPlace();
        debugPrint('MapRepository: Loaded ${scraped.length} scraped places');
        places.addAll(scraped);
      } catch (e) {
        debugPrint('MapRepository: Failed to load scraped places: $e');
      }

      return places;
    } catch (e) {
      debugPrint('MapRepository: Error fetching places from Supabase: $e');
      // Jika ada error, return list kosong
      return [];
    }
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
        kodePos: null,
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
    final String? kodePos = properties != null
        ? properties['kode_pos']?.toString()
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
        kodePos: kodePos,
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
          kodePos: kodePos,
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
          kodePos: kodePos,
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
        kodePos: kodePos,
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
      kodePos: kodePos,
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
      final String? kodePos = properties != null
          ? properties['kode_pos']?.toString()
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
            kodePos: kodePos,
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
            kodePos: kodePos,
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
          kodePos: kodePos,
        ),
      );
    }

    debugPrint(
      'GeoJSON(list): loaded ${results.length} polygons with names from $cleanPath',
    );
    return results;
  }

  @override
  Future<DirektoriModel?> getDirectoryById(String id) async {
    try {
      final response = await _supabaseClient
          .from('direktori')
          .select('''
            *,
            wilayah(*)
          ''')
          .eq('id', id)
          .limit(1);

      if (response.isEmpty) {
        debugPrint('MapRepository: No directory found with id: $id');
        return null;
      }

      final item = response.first;

      // Flatten data wilayah ke level utama untuk kemudahan parsing
      final Map<String, dynamic> flattenedData = Map<String, dynamic>.from(
        item,
      );

      if (item['wilayah'] != null && item['wilayah'] is Map) {
        final wilayahData = item['wilayah'] as Map<String, dynamic>;
        flattenedData.addAll(wilayahData);
      }

      return DirektoriModel.fromJson(flattenedData);
    } catch (e) {
      debugPrint('MapRepository: Error fetching directory by id: $e');
      return null;
    }
  }

  // New method: delete if id_sbr == 0 or empty, else mark closed (keberadaan_usaha = 4)
  Future<bool> deleteOrCloseDirectoryById(String id) async {
    try {
      final response = await _supabaseClient
          .from('direktori')
          .select('id,id_sbr')
          .eq('id', id)
          .limit(1);

      if (response is List && response.isNotEmpty) {
        final row = response.first as Map<String, dynamic>;
        final dynamic idSbrVal = row['id_sbr'];
        final bool isPending =
            idSbrVal == null ||
            idSbrVal == '' ||
            idSbrVal == '0' ||
            idSbrVal == 0;

        if (isPending) {
          await _supabaseClient.from('direktori').delete().eq('id', id);
        } else {
          await _supabaseClient
              .from('direktori')
              .update({
                'keberadaan_usaha': 4, // 4 = Tutup
                'updated_at': DateTime.now().toIso8601String(),
              })
              .eq('id', id);
        }
        return true;
      }

      debugPrint('MapRepository: No direktori found with id: $id');
      return false;
    } catch (e) {
      debugPrint('MapRepository: Error deleteOrCloseDirectoryById: $e');
      return false;
    }
  }
}
