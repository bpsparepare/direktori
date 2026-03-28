class WilayahMappingSidrap {
  // ID Server Constants
  // 132 = Provinsi Sulawesi Selatan (Sama seperti Parepare)
  static const String serverProvinsiId = '132';
  // 2573 = Kabupaten Sidenreng Rappang (Sidrap)
  static const String serverKabupatenId = '2573';

  // Mapping Kode BPS (Local) -> ID Server
  // Format: 'KodeBPS': 'IDServer'
  static const Map<String, String> kecamatanMap = {
    '010': '34380', // PANCA LAUTANG
    '020': '34381', // TELLULIMPO E
    '030': '34382', // WATANG PULU
    '040': '34383', // BARANTI
    '050': '34384', // PANCA RIJANG
    '051': '34385', // KULO
    '060': '34386', // MARITENGNGAE
    '061': '34387', // WATANG SIDENRENG
    '070': '34388', // PITU RIAWA
    '080': '34389', // DUAPITUE
    '081': '34390', // PITU RIASE
  };

  // Mapping Kode Desa per Kecamatan
  // Format: 'KodeKecamatan': {'KodeDesa': 'IDServer'}
  static const Map<String, Map<String, String>> desaMap = {
    // PANCA LAUTANG (010)
    '010': {
      '001': '480370', // CENRANA
      '002': '480371', // BAPANGI
      '003': '480372', // WANIO TIMORENG
      '004': '480373', // WANIO
      '005': '480374', // BILOKKA
      '006': '480375', // CORAWALI
      '007': '480376', // LISE
      '008': '480377', // ALLESALEWOE
      '009': '480378', // LAJONGA
      '010': '480379', // WETTEE
    },
    // TELLULIMPO E (020)
    '020': {
      '001': '480380', // TEPPO
      '002': '480381', // MASSEPE
      '004': '480382', // PAJALELE
      '005': '480383', // POLEWALI
      '006': '480384', // TETEAJI
      '007': '480385', // AMPARITA
      '008': '480386', // BAULA
      '009': '480387', // TODANG PULU
      '010': '480388', // ARATENG
    },
    // WATANG PULU (030)
    '030': {
      '001': '480389', // MATTIROTASI
      '002': '480390', // BUAE
      '003': '480391', // LAINUNGAN
      '004': '480392', // LAWAWOI
      '005': '480393', // BANGKAI
      '006': '480394', // ULUALE
      '007': '480395', // ARAWA
      '008': '480396', // BATULAPPA
      '009': '480397', // CIRO-CIROE
      '010': '480398', // CARAWALI
    },
    // BARANTI (040)
    '040': {
      '001': '480399', // MANISA
      '002': '480400', // PANRENG
      '003': '480401', // BENTENG
      '004': '480402', // BARANTI
      '005': '480403', // SIPODECENG
      '006': '480404', // PASSENO
      '007': '480405', // DUAMPANUA
      '008': '480406', // TONRONGE
      '009': '480407', // TONRONG RIJANG
    },
    // PANCA RIJANG (050)
    '050': {
      '001': '480408', // KADIDI
      '002': '480409', // MACORAWALIE
      '003': '480410', // TIMORENG PANUA
      '004': '480411', // CIPOTAKARI
      '005': '480412', // BULO
      '006': '480413', // BULO WATTANG
      '007': '480414', // LALEBATA
      '008': '480415', // RAPPANG
    },
    // KULO (051)
    '051': {
      '001': '480416', // MARIO
      '002': '480417', // RIJANG PANUA
      '003': '480418', // KULO
      '004': '480419', // ABBOKONGANG
      '005': '480420', // MADDENRA
      '006': '480421', // BINA BARU
    },
    // MARITENGNGAE (060)
    '060': {
      '001': '480422', // TAKKALASI
      '002': '480423', // ALLAKUANG
      '003': '480424', // TANETE
      '004': '480425', // LAUTANG BENTENG
      '005': '480426', // RIJANG PITTU
      '006': '480427', // LAKESSI
      '007': '480428', // PANGKAJENE
      '008': '480429', // WALA
      '009': '480430', // MAJJELLING
      '010': '480431', // MAJELLING WATANG
      '011': '480432', // SEREANG
      '012': '480433', // KANIE
    },
    // WATANG SIDENRENG (061)
    '061': {
      '001': '480434', // KANYUARA
      '002': '480435', // SIDENRENG
      '003': '480436', // EMPAGAE
      '004': '480437', // MOJONG
      '005': '480438', // TALUMAE
      '006': '480439', // AKA-AKAE
      '007': '480440', // DAMAI
      '008': '480441', // TALAWE
    },
    // PITU RIAWA (070)
    '070': {
      '001': '480442', // PONRANGAE
      '002': '480443', // LANCIRANG
      '003': '480444', // SUMPANG MANGO
      '004': '480445', // LASIWALA
      '005': '480446', // AJUBISSUE
      '006': '480447', // DONGI
      '007': '480448', // OTTING
      '008': '480449', // ANA BANNA
      '009': '480450', // BULU CENRANA
      '010': '480451', // BETAO
      '014': '480452', // BETAO RIASE
      '015': '480453', // KALEMPANG
    },
    // DUAPITUE (080)
    '080': {
      '001': '480454', // PADANGLOANG
      '002': '480455', // PADANGLOANG ALAU
      '003': '480456', // SALO MALLORI
      '004': '480457', // TANRUTEDONG
      '005': '480458', // KALOSI
      '006': '480459', // KALOSI ALAU
      '007': '480460', // TACCIMPO
      '008': '480461', // SALOBUKKANG
      '010': '480462', // BILA
      '011': '480463', // KAMPALE
    },
    // PITU RIASE (081)
    '081': {
      '001': '480464', // BOLA BULU
      '002': '480465', // BOTTO
      '003': '480466', // BILA RIASE
      '004': '480467', // LAGADING
      '005': '480468', // BATU
      '007': '480469', // TANATORO
      '008': '480470', // COMPONG
      '009': '480471', // LEPPANGENG
      '010': '480472', // LOMBO
      '011': '480473', // DENGENG-DENGENG
      '012': '480474', // BUNTU BUANGING
      '013': '480475', // BELAWAE
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
