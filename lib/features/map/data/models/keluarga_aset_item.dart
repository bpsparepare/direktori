/// Satu baris hasil get_keluarga_aset(): aset satu keluarga + penanda aset yang
/// melewati ambang wajar.
class KeluargaAsetItem {
  final String assignmentId;
  final String namaKk;
  final String kodeWilayah;
  final String namaKec;
  final String namaDesa;
  final String namaSls;
  final String statusText;
  final String namaPetugas;
  final Map<String, int> nilai; // key aset -> jumlah
  final Set<String> lewat; // key aset yang melewati ambang
  final bool sudahAnomali;
  final String komentarAdmin;

  const KeluargaAsetItem({
    required this.assignmentId,
    required this.namaKk,
    required this.kodeWilayah,
    required this.namaKec,
    required this.namaDesa,
    required this.namaSls,
    required this.statusText,
    required this.namaPetugas,
    required this.nilai,
    required this.lewat,
    required this.sudahAnomali,
    required this.komentarAdmin,
  });

  /// Urutan & kunci aset (harus cocok kolom RPC & penanda aset_lewat).
  static const List<String> asetKeys = [
    'tabung3kg',
    'tabung5kg',
    'kulkas',
    'ac',
    'emas',
    'laptop',
    'motor',
    'mobil',
    'lahan',
    'rumah',
  ];

  static const Map<String, String> asetLabel = {
    'tabung3kg': 'Tabung 3kg',
    'tabung5kg': 'Tabung 5kg',
    'kulkas': 'Kulkas',
    'ac': 'AC',
    'emas': 'Emas',
    'laptop': 'Laptop',
    'motor': 'Motor',
    'mobil': 'Mobil',
    'lahan': 'Lahan',
    'rumah': 'Rumah',
  };

  factory KeluargaAsetItem.fromJson(Map<String, dynamic> json) {
    String s(dynamic v) => (v ?? '').toString();
    int asInt(dynamic v) => v is int ? v : int.tryParse(s(v)) ?? 0;
    final nilai = <String, int>{
      'tabung3kg': asInt(json['jml_tabung3kg']),
      'tabung5kg': asInt(json['jml_tabung5kg']),
      'kulkas': asInt(json['jml_kulkas']),
      'ac': asInt(json['jml_ac']),
      'emas': asInt(json['jml_emas']),
      'laptop': asInt(json['jml_laptop']),
      'motor': asInt(json['jml_motor']),
      'mobil': asInt(json['jml_mobil']),
      'lahan': asInt(json['jml_lahan']),
      'rumah': asInt(json['jml_rumah']),
    };
    final lewat = <String>{};
    final raw = json['aset_lewat'];
    if (raw is List) {
      for (final e in raw) {
        lewat.add(e.toString());
      }
    }
    return KeluargaAsetItem(
      assignmentId: s(json['assignment_id']),
      namaKk: s(json['nama_kk']),
      kodeWilayah: s(json['kode_wilayah']),
      namaKec: s(json['nama_kec']),
      namaDesa: s(json['nama_desa']),
      namaSls: s(json['nama_sls']),
      statusText: s(json['status_text']),
      namaPetugas: s(json['nama_petugas']),
      nilai: nilai,
      lewat: lewat,
      sudahAnomali: json['sudah_anomali'] == true,
      komentarAdmin: s(json['komentar_admin']),
    );
  }

  String get key => assignmentId;
  bool get adaAnomali => lewat.isNotEmpty;

  String get wilayahLabel {
    final parts =
        [namaDesa, namaSls].where((v) => v.trim().isNotEmpty).toList();
    return parts.isEmpty ? kodeWilayah : parts.join(' / ');
  }
}
