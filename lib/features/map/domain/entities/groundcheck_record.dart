class GroundcheckRecord {
  final String idsbr;
  final String namaUsaha;
  final String alamatUsaha;
  final String kodeWilayah;
  final String statusPerusahaan;
  final String skalaUsaha;
  final String gcsResult;
  final String sumberData;
  final String latitude;
  final String longitude;
  final String perusahaanId;
  final String? userId;
  final String? kdProv;
  final String? kdKab;
  final String? kdKec;
  final String? kdDesa;
  final bool isUploaded;
  final bool isRevisi;
  final bool allowCancel;

  GroundcheckRecord({
    required this.idsbr,
    required this.namaUsaha,
    required this.alamatUsaha,
    required this.kodeWilayah,
    required this.statusPerusahaan,
    required this.skalaUsaha,
    required this.gcsResult,
    this.sumberData = '',
    required this.latitude,
    required this.longitude,
    required this.perusahaanId,
    this.userId,
    this.kdProv,
    this.kdKab,
    this.kdKec,
    this.kdDesa,
    this.isUploaded = false,
    this.isRevisi = false,
    this.allowCancel = true,
  });

  factory GroundcheckRecord.fromJson(Map<String, dynamic> json) {
    final lat = (json['latitude'] ?? '').toString();
    final lon = (json['longitude'] ?? '').toString();
    final perusahaan = (json['perusahaan_id'] ?? json['idsbr'] ?? '')
        .toString();
    return GroundcheckRecord(
      idsbr: (json['idsbr'] ?? '').toString(),
      namaUsaha: (json['nama_usaha'] ?? '').toString(),
      alamatUsaha: (json['alamat_usaha'] ?? '').toString(),
      kodeWilayah: (json['kode_wilayah'] ?? '').toString(),
      statusPerusahaan: (json['status_perusahaan'] ?? '').toString(),
      skalaUsaha: (json['skala_usaha'] ?? '').toString(),
      gcsResult: (json['gcs_result'] ?? '').toString(),
      sumberData: (json['sumber_data'] ?? '').toString(),
      latitude: lat,
      longitude: lon,
      perusahaanId: perusahaan,
      userId: json['user_id']?.toString(),
      kdProv: json['kd_prov']?.toString(),
      kdKab: json['kd_kab']?.toString(),
      kdKec: json['kd_kec']?.toString(),
      kdDesa: json['kd_desa']?.toString(),
      isUploaded: json['isUploaded'] == true,
      isRevisi: json['is_revisi'] == true || json['isRevisi'] == true,
      allowCancel: json['allow_cancel'] != false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'idsbr': idsbr,
      'nama_usaha': namaUsaha,
      'alamat_usaha': alamatUsaha,
      'kode_wilayah': kodeWilayah,
      'status_perusahaan': statusPerusahaan,
      'skala_usaha': skalaUsaha,
      'gcs_result': gcsResult,
      'sumber_data': sumberData,
      'latitude': latitude,
      'longitude': longitude,
      'perusahaan_id': perusahaanId,
      'user_id': userId,
      'kd_prov': kdProv,
      'kd_kab': kdKab,
      'kd_kec': kdKec,
      'kd_desa': kdDesa,
      'isUploaded': isUploaded,
      'isRevisi': isRevisi,
      'allow_cancel': allowCancel,
    };
  }

  GroundcheckRecord copyWith({
    String? idsbr,
    String? namaUsaha,
    String? alamatUsaha,
    String? kodeWilayah,
    String? statusPerusahaan,
    String? skalaUsaha,
    String? gcsResult,
    String? sumberData,
    String? latitude,
    String? longitude,
    String? perusahaanId,
    String? userId,
    String? kdProv,
    String? kdKab,
    String? kdKec,
    String? kdDesa,
    bool? isUploaded,
    bool? isRevisi,
    bool? allowCancel,
  }) {
    return GroundcheckRecord(
      idsbr: idsbr ?? this.idsbr,
      namaUsaha: namaUsaha ?? this.namaUsaha,
      alamatUsaha: alamatUsaha ?? this.alamatUsaha,
      kodeWilayah: kodeWilayah ?? this.kodeWilayah,
      statusPerusahaan: statusPerusahaan ?? this.statusPerusahaan,
      skalaUsaha: skalaUsaha ?? this.skalaUsaha,
      gcsResult: gcsResult ?? this.gcsResult,
      sumberData: sumberData ?? this.sumberData,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      perusahaanId: perusahaanId ?? this.perusahaanId,
      userId: userId ?? this.userId,
      kdProv: kdProv ?? this.kdProv,
      kdKab: kdKab ?? this.kdKab,
      kdKec: kdKec ?? this.kdKec,
      kdDesa: kdDesa ?? this.kdDesa,
      isUploaded: isUploaded ?? this.isUploaded,
      isRevisi: isRevisi ?? this.isRevisi,
      allowCancel: allowCancel ?? this.allowCancel,
    );
  }
}
