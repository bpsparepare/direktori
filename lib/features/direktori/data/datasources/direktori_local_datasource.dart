import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/entities/direktori.dart';
import '../../../map/data/models/direktori_model.dart' as MapDirektori;
import '../models/direktori_model.dart' as DomainDirektori;

abstract class DirektoriLocalDataSource {
  Future<List<Direktori>> loadAll();
  Future<void> saveAll(
    List<Direktori> list, {
    int? totalCount,
    Map<String, int>? stats,
  });
  Future<Map<String, dynamic>?> loadMeta();
  Future<void> clear();
}

class DirektoriLocalDataSourceImpl implements DirektoriLocalDataSource {
  Future<File> _listFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/direktori_cache.json');
  }

  Future<File> _metaFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/direktori_cache_meta.json');
  }

  @override
  Future<List<Direktori>> loadAll() async {
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        final txt = prefs.getString('direktori_cache_list');
        if (txt == null || txt.isEmpty) return [];
        final list = jsonDecode(txt);
        if (list is! List) return [];
        final result = <Direktori>[];
        for (final item in list) {
          if (item is Map<String, dynamic>) {
            final mapModel = MapDirektori.DirektoriModel.fromJson(item);
            final domainModel = DomainDirektori.DirektoriModel.fromMapModel(
              mapModel,
            );
            result.add(domainModel);
          }
        }
        return result;
      } else {
        final file = await _listFile();
        if (!await file.exists()) return [];
        final txt = await file.readAsString();
        final list = jsonDecode(txt);
        if (list is! List) return [];
        final result = <Direktori>[];
        for (final item in list) {
          if (item is Map<String, dynamic>) {
            final mapModel = MapDirektori.DirektoriModel.fromJson(item);
            final domainModel = DomainDirektori.DirektoriModel.fromMapModel(
              mapModel,
            );
            result.add(domainModel);
          }
        }
        return result;
      }
    } catch (_) {
      return [];
    }
  }

  @override
  Future<void> saveAll(
    List<Direktori> list, {
    int? totalCount,
    Map<String, int>? stats,
  }) async {
    try {
      final jsonList = list.map((d) => _toJson(d)).toList();
      final meta = {
        'saved_at': DateTime.now().toUtc().toIso8601String(),
        if (totalCount != null) 'total_count': totalCount,
        if (stats != null) 'stats': stats,
      };
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('direktori_cache_list', jsonEncode(jsonList));
        await prefs.setString('direktori_cache_meta', jsonEncode(meta));
      } else {
        final file = await _listFile();
        await file.writeAsString(jsonEncode(jsonList));
        final metaFile = await _metaFile();
        await metaFile.writeAsString(jsonEncode(meta));
      }
    } catch (_) {}
  }

  @override
  Future<Map<String, dynamic>?> loadMeta() async {
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        final txt = prefs.getString('direktori_cache_meta');
        if (txt == null || txt.isEmpty) return null;
        final obj = jsonDecode(txt);
        if (obj is Map<String, dynamic>) return obj;
        return null;
      } else {
        final file = await _metaFile();
        if (!await file.exists()) return null;
        final txt = await file.readAsString();
        final obj = jsonDecode(txt);
        if (obj is Map<String, dynamic>) return obj;
        return null;
      }
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> clear() async {
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('direktori_cache_list');
        await prefs.remove('direktori_cache_meta');
      } else {
        final f1 = await _listFile();
        final f2 = await _metaFile();
        if (await f1.exists()) await f1.delete();
        if (await f2.exists()) await f2.delete();
      }
    } catch (_) {}
  }

  Map<String, dynamic> _toJson(Direktori d) {
    return {
      'id': d.id,
      'id_sbr': d.idSbr,
      'nama_usaha': d.namaUsaha,
      'alamat': d.alamat,
      'id_sls': d.idSls,
      'kegiatan_usaha': d.kegiatanUsaha,
      'skala_usaha': d.skalaUsaha,
      'keterangan': d.keterangan,
      'nib': d.nib,
      'latitude': d.latitude ?? d.lat,
      'longitude': d.longitude ?? d.long,
      'url_gambar': d.urlGambar,
      'kode_pos': d.kodePos,
      'jenis_perusahaan': d.jenisPerusahaan,
      'pemilik': d.pemilik,
      'nik_pemilik': d.nikPemilik,
      'nohp_pemilik': d.nohpPemilik,
      'tenaga_kerja': d.tenagaKerja,
      'created_at': d.createdAt?.toIso8601String(),
      'updated_at': d.updatedAt?.toIso8601String(),
      'nama_komersial_usaha': d.namaKomersialUsaha,
      'nomor_telepon': d.nomorTelepon,
      'nomor_whatsapp': d.nomorWhatsapp,
      'email': d.email,
      'website': d.website,
      'sumber_data': d.sumberData,
      'keberadaan_usaha': d.keberadaanUsaha,
      'jenis_kepemilikan_usaha': d.jenisKepemilikanUsaha,
      'bentuk_badan_hukum_usaha': d.bentukBadanHukumUsaha,
      'deskripsi_badan_usaha_lainnya': d.deskripsiBadanUsahaLainnya,
      'tahun_berdiri': d.tahunBerdiri,
      'jaringan_usaha': d.jaringanUsaha,
      'sektor_institusi': d.sektorInstitusi,
      'nm_prov': d.nmProv,
      'nm_kab': d.nmKab,
    };
  }
}
