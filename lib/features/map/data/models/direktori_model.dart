import 'package:latlong2/latlong.dart';
import '../../domain/entities/place.dart';

class DirektoriModel {
  final String id;
  final String idSbr;
  final String namaUsaha;
  final String? alamat;
  final String idSls;
  final List<Map<String, dynamic>> kegiatanUsaha;
  final String? skalaUsaha;
  final String? keterangan;
  final String? nib;
  final double? lat;
  final double? long;
  final String? urlGambar;
  final String? kodePos;
  final String? jenisPerusahaan;
  final String? pemilik;
  final String? nikPemilik;
  final String? nohpPemilik;
  final int? tenagaKerja;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  // Kolom baru yang ditambahkan
  final String? namaKomersialUsaha;
  final String? nomorTelepon;
  final String? nomorWhatsapp;
  final String? email;
  final String? website;
  final String? sumberData;

  // Koordinat baru (mengganti lat/long)
  final double? latitude;
  final double? longitude;

  // Field baru sesuai permintaan user
  final int? keberadaanUsaha; // 1-10
  final int? jenisKepemilikanUsaha; // 1-4
  final int? bentukBadanHukumUsaha; // 1-12, 99
  final String?
  deskripsiBadanUsahaLainnya; // untuk bentuk_badan_hukum_usaha = 99
  final int? tahunBerdiri;
  final int? jaringanUsaha; // 1-6
  final int? sektorInstitusi; // 1-5

  // Data wilayah (dari join dengan tabel wilayah)
  final String? nmProv;
  final String? nmKab;
  final String? nmKec;
  final String? nmDesa;
  final String? nmSls;
  final String? alamatLengkap;

  // Kode wilayah (untuk input manual)
  final String? kdProv;
  final String? kdKab;
  final String? kdKec;
  final String? kdDesa;
  final String? kdSls;

  // New fields for KBLI and tags
  final String? kbli; // 5-digit KBLI code
  final List<String>? tag; // Array of tags

  const DirektoriModel({
    required this.id,
    required this.idSbr,
    required this.namaUsaha,
    this.alamat,
    required this.idSls,
    this.kegiatanUsaha = const [],
    this.skalaUsaha,
    this.keterangan,
    this.nib,
    this.lat,
    this.long,
    this.urlGambar,
    this.kodePos,
    this.jenisPerusahaan,
    this.pemilik,
    this.nikPemilik,
    this.nohpPemilik,
    this.tenagaKerja,
    this.createdAt,
    this.updatedAt,
    // Kolom baru
    this.namaKomersialUsaha,
    this.nomorTelepon,
    this.nomorWhatsapp,
    this.email,
    this.website,
    this.sumberData,
    // Koordinat baru
    this.latitude,
    this.longitude,
    // Field baru sesuai permintaan user
    this.keberadaanUsaha,
    this.jenisKepemilikanUsaha,
    this.bentukBadanHukumUsaha,
    this.deskripsiBadanUsahaLainnya,
    this.tahunBerdiri,
    this.jaringanUsaha,
    this.sektorInstitusi,
    // Data wilayah
    this.nmProv,
    this.nmKab,
    this.nmKec,
    this.nmDesa,
    this.nmSls,
    this.alamatLengkap,
    // Kode wilayah
    this.kdProv,
    this.kdKab,
    this.kdKec,
    this.kdDesa,
    this.kdSls,
    // New fields
    this.kbli,
    this.tag,
  });

  factory DirektoriModel.fromJson(Map<String, dynamic> json) {
    // Parse kegiatan_usaha dari JSONB
    List<Map<String, dynamic>> kegiatanUsahaList = [];
    if (json['kegiatan_usaha'] != null) {
      if (json['kegiatan_usaha'] is List) {
        kegiatanUsahaList = List<Map<String, dynamic>>.from(
          json['kegiatan_usaha'].map((x) => Map<String, dynamic>.from(x)),
        );
      }
    }

    return DirektoriModel(
      id: json['id'] ?? '',
      idSbr: json['id_sbr'] ?? '',
      namaUsaha: json['nama_usaha'] ?? '',
      alamat: json['alamat'],
      idSls: json['id_sls'] ?? '',
      kegiatanUsaha: kegiatanUsahaList,
      skalaUsaha: json['skala_usaha'],
      keterangan: json['keterangan'],
      nib: json['nib'],
      lat: json['latitude']?.toDouble() ?? json['lat']?.toDouble(),
      long: json['longitude']?.toDouble() ?? json['long']?.toDouble(),
      urlGambar: json['url_gambar'],
      kodePos: json['kode_pos'],
      jenisPerusahaan: json['jenis_perusahaan'],
      pemilik: json['pemilik'],
      nikPemilik: json['nik_pemilik'],
      nohpPemilik: json['nohp_pemilik'],
      tenagaKerja: json['tenaga_kerja']?.toInt(),
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'])
          : null,
      // Kolom baru
      namaKomersialUsaha: json['nama_komersial_usaha'],
      nomorTelepon: json['nomor_telepon'],
      nomorWhatsapp: json['nomor_whatsapp'],
      email: json['email'],
      website: json['website'],
      sumberData: json['sumber_data'],
      // Koordinat baru
      latitude: json['latitude']?.toDouble(),
      longitude: json['longitude']?.toDouble(),
      // Field baru sesuai permintaan user
      keberadaanUsaha: json['keberadaan_usaha']?.toInt(),
      jenisKepemilikanUsaha: json['jenis_kepemilikan_usaha']?.toInt(),
      bentukBadanHukumUsaha: json['bentuk_badan_hukum_usaha']?.toInt(),
      deskripsiBadanUsahaLainnya: json['deskripsi_badan_usaha_lainnya'],
      tahunBerdiri: json['tahun_berdiri']?.toInt(),
      jaringanUsaha: json['jaringan_usaha']?.toInt(),
      sektorInstitusi: json['sektor_institusi']?.toInt(),
      // Data wilayah dari join
      nmProv: json['nm_prov'],
      nmKab: json['nm_kab'],
      nmKec: json['nm_kec'],
      nmDesa: json['nm_desa'],
      nmSls: json['nama_sls'],
      alamatLengkap: json['alamat_lengkap'],
      // Kode wilayah
      kdProv: json['kd_prov'],
      kdKab: json['kd_kab'],
      kdKec: json['kd_kec'],
      kdDesa: json['kd_desa'],
      kdSls: json['kd_sls'],
      // New fields
      kbli: json['kbli'],
      tag: json['tag'] != null ? List<String>.from(json['tag']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'id_sbr': idSbr,
      'nama_usaha': namaUsaha,
      'alamat': alamat,
      'id_sls': idSls,
      'kegiatan_usaha': kegiatanUsaha,
      'skala_usaha': skalaUsaha,
      'keterangan': keterangan,
      'nib': nib,
      'latitude': latitude ?? lat,
      'longitude': longitude ?? long,
      'url_gambar': urlGambar,
      'kode_pos': kodePos,
      'jenis_perusahaan': jenisPerusahaan,
      'pemilik': pemilik,
      'nik_pemilik': nikPemilik,
      'nohp_pemilik': nohpPemilik,
      'tenaga_kerja': tenagaKerja,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      // Kolom baru
      'nama_komersial_usaha': namaKomersialUsaha,
      'nomor_telepon': nomorTelepon,
      'nomor_whatsapp': nomorWhatsapp,
      'email': email,
      'website': website,
      'sumber_data': sumberData,
      // Koordinat baru
      'latitude': latitude,
      'longitude': longitude,
      // Field baru sesuai permintaan user
      'keberadaan_usaha': keberadaanUsaha,
      'jenis_kepemilikan_usaha': jenisKepemilikanUsaha,
      'bentuk_badan_hukum_usaha': bentukBadanHukumUsaha,
      'deskripsi_badan_usaha_lainnya': deskripsiBadanUsahaLainnya,
      'tahun_berdiri': tahunBerdiri,
      'jaringan_usaha': jaringanUsaha,
      'sektor_institusi': sektorInstitusi,
      // Data wilayah
      'nm_prov': nmProv,
      'nm_kab': nmKab,
      'nm_kec': nmKec,
      'nm_desa': nmDesa,
      'nama_sls': nmSls,
      'alamat_lengkap': alamatLengkap,
      // Kode wilayah
      'kd_prov': kdProv,
      'kd_kab': kdKab,
      'kd_kec': kdKec,
      'kd_desa': kdDesa,
      'kd_sls': kdSls,
      // New fields
      'kbli': kbli,
      'tag': tag,
    };
  }

  /// Konversi DirektoriModel ke Place untuk ditampilkan di peta
  Place toPlace() {
    // Buat deskripsi yang informatif
    String description = _buildDescription();

    // Gunakan koordinat jika tersedia, prioritas latitude/longitude baru
    LatLng position = LatLng(
      latitude ?? lat ?? -4.0328772052560335, // Default lat Parepare
      longitude ?? long ?? 119.63160510345742, // Default long Parepare
    );

    return Place(
      id: id,
      name: namaUsaha,
      description: description,
      position: position,
      urlGambar: urlGambar,
    );
  }

  String _buildDescription() {
    List<String> descriptionParts = [];

    // Nama komersial (jika berbeda dari nama usaha)
    if (namaKomersialUsaha != null &&
        namaKomersialUsaha!.isNotEmpty &&
        namaKomersialUsaha != namaUsaha) {
      descriptionParts.add('🏪 Nama Komersial: $namaKomersialUsaha');
    }

    // Alamat
    if (alamat != null && alamat!.isNotEmpty) {
      descriptionParts.add('📍 $alamat');
    }

    // Wilayah
    if (alamatLengkap != null && alamatLengkap!.isNotEmpty) {
      descriptionParts.add('🏘️ $alamatLengkap');
    }

    // Kontak
    if (nomorTelepon != null && nomorTelepon!.isNotEmpty) {
      descriptionParts.add('📞 Telepon: $nomorTelepon');
    }

    if (nomorWhatsapp != null && nomorWhatsapp!.isNotEmpty) {
      descriptionParts.add('📱 WhatsApp: $nomorWhatsapp');
    }

    // Kegiatan usaha (ambil yang pertama jika ada)
    if (kegiatanUsaha.isNotEmpty) {
      final kegiatan = kegiatanUsaha.first;
      if (kegiatan['kegiatan_usaha'] != null) {
        descriptionParts.add('💼 ${kegiatan['kegiatan_usaha']}');
      }
    }

    // Sektor institusi
    if (sektorInstitusi != null) {
      String sektor = _getSektorInstitusiText(sektorInstitusi!);
      descriptionParts.add('🏢 Sektor: $sektor');
    }

    return descriptionParts.join('\n');
  }

  /// Check apakah direktori memiliki koordinat yang valid
  bool get hasValidCoordinates {
    // Prioritas koordinat baru, fallback ke koordinat lama
    double? currentLat = latitude ?? lat;
    double? currentLong = longitude ?? long;

    return currentLat != null &&
        currentLong != null &&
        currentLat >= -90 &&
        currentLat <= 90 &&
        currentLong >= -180 &&
        currentLong <= 180;
  }

  /// Check apakah direktori aktif
  bool get isActive {
    return keberadaanUsaha == 1; // 1 = Aktif
  }

  // Helper methods untuk mengkonversi kode ke teks
  String _getKeberadaanUsahaText(int kode) {
    switch (kode) {
      case 1:
        return 'Aktif';
      case 2:
        return 'Tutup Sementara';
      case 3:
        return 'Belum Beroperasi/Berproduksi';
      case 4:
        return 'Tutup';
      case 5:
        return 'Alih Usaha';
      case 6:
        return 'Tidak Ditemukan';
      case 7:
        return 'Aktif Pindah';
      case 8:
        return 'Aktif Nonrespon';
      case 9:
        return 'Duplikat';
      case 10:
        return 'Salah Kode Wilayah';
      default:
        return 'Tidak Diketahui';
    }
  }

  String _getJenisKepemilikanText(int kode) {
    switch (kode) {
      case 1:
        return 'BUMN';
      case 2:
        return 'Non BUMN';
      case 3:
        return 'BUMD';
      case 4:
        return 'BUMDes';
      default:
        return 'Tidak Diketahui';
    }
  }

  String _getBentukBadanHukumText(int kode) {
    switch (kode) {
      case 1:
        return 'Perseroan (PT/ PT Persero..)';
      case 2:
        return 'Yayasan';
      case 3:
        return 'Koperasi';
      case 4:
        return 'Dana Pensiun';
      case 5:
        return 'Perum/Perumda';
      case 6:
        return 'BUM Desa';
      case 7:
        return 'CV';
      case 8:
        return 'Firma';
      case 9:
        return 'Persekutuan Perdata (Maatschap)';
      case 10:
        return 'Kantor Perwakilan Luar Negeri';
      case 11:
        return 'Badan Usaha Luar Negeri';
      case 12:
        return 'Usaha Orang Perseorangan';
      case 99:
        return 'Lainnya';
      default:
        return 'Tidak Diketahui';
    }
  }

  String _getJaringanUsahaText(int kode) {
    switch (kode) {
      case 1:
        return 'Tunggal';
      case 2:
        return 'Kantor Pusat';
      case 3:
        return 'Kantor Cabang';
      case 4:
        return 'Perwakilan';
      case 5:
        return 'Pabrik/Unit Kegiatan';
      case 6:
        return 'Unit Pembantu/Penunjang';
      default:
        return 'Tidak Diketahui';
    }
  }

  String _getSektorInstitusiText(int kode) {
    switch (kode) {
      case 1:
        return 'S11 – Korporasi Finansial';
      case 2:
        return 'S12 – Korporasi Non Finansial';
      case 3:
        return 'S13 – Pemerintahan Umum';
      case 4:
        return 'S14 – Rumah Tangga';
      case 5:
        return 'S15 – LNPRT';
      default:
        return 'Tidak Diketahui';
    }
  }

  @override
  String toString() {
    return 'DirektoriModel(id: $id, namaUsaha: $namaUsaha, alamat: $alamat, lat: $lat, long: $long)';
  }
}
