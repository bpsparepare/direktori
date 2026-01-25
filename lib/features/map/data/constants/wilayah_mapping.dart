class WilayahMapping {
  // ID Server Constants
  static const String serverProvinsiId = '132';
  static const String serverKabupatenId = '2582';

  // Mapping Kode BPS (Local) -> ID Server
  // Format: 'KodeBPS': 'IDServer'
  static const Map<String, String> kecamatanMap = {
    '010': '34518', // BACUKIKI
    '011': '34519', // BACUKIKI BARAT
    '020': '34520', // UJUNG
    '030': '34521', // SOREANG
  };

  // Mapping Kode Desa per Kecamatan
  // Format: 'KodeKecamatan': {'KodeDesa': 'IDServer'}
  static const Map<String, Map<String, String>> desaMap = {
    // BACUKIKI (010)
    '010': {
      '002': '481707', // WATANG BACUKIKI
      '003': '481708', // LEMOE
      '004': '481709', // LOMPOE
      '005': '481710', // GALUNG MALOANG
    },
    // BACUKIKI BARAT (011)
    '011': {
      '001': '481711', // LUMPUE
      '002': '481712', // BUMI HARAPAN
      '003': '481713', // SUMPANG MINANGAE
      '004': '481714', // CAPPAGALUNG
      '005': '481715', // TIRO SOMPE
      '006': '481716', // KAMPUNG BARU
    },
    // UJUNG (020)
    '020': {
      '001': '481717', // LABUKKANG
      '002': '481718', // MALLUSETASI
      '003': '481719', // UJUNG SABBANG
      '004': '481720', // UJUNG BULU
      '005': '481721', // LAPADDE
    },
    // SOREANG (030)
    '030': {
      '001': '481722', // KAMPUNG PISANG
      '002': '481723', // LAKESSI
      '003': '481724', // UJUNG BARU
      '004': '481725', // UJUNG LARE
      '005': '481726', // BIKIT INDAH
      '006': '481727', // WATANG SOREANG
      '007': '481728', // BUKIT HARAPAN
    },
  };

  /// Mengambil ID Kecamatan untuk server berdasarkan Kode BPS
  static String getKecamatanId(String kodeKec) {
    return kecamatanMap[kodeKec] ?? kodeKec;
  }

  /// Mengambil ID Desa untuk server berdasarkan Kode Kecamatan dan Kode Desa BPS
  static String getDesaId(String kodeKec, String kodeDesa) {
    return desaMap[kodeKec]?[kodeDesa] ?? kodeDesa;
  }
}
