/// Baris hasil RPC get_anomali_gabungan(): satu list gabungan sumber
/// 'kualitas' (wilayah/rule-engine) dan 'pusat_baru' (excel Fasih
/// usaha/keluarga, anomali_pusat_temuan).
class AnomaliGabunganItem {
  final String sumber;
  final String assignmentId;
  final String kodeWilayah;
  final String namaWilayah;
  final String kategoriBesar;
  final String kategoriKode;
  final String kategoriLabel;
  final String subjek;
  final int? noAnomali;
  final String deskripsi;
  final String statusTindakLanjut;
  final String? jenisRespons;
  final String? keterangan;
  final String? diperiksaOleh;
  final DateTime? diperiksaAt;
  final String? statusAssignment;
  final int jumlahRespons;
  final String namaSls;
  final String subSls;
  final String namaPetugas;

  const AnomaliGabunganItem({
    required this.sumber,
    required this.assignmentId,
    required this.kodeWilayah,
    required this.namaWilayah,
    required this.kategoriBesar,
    required this.kategoriKode,
    required this.kategoriLabel,
    required this.subjek,
    required this.noAnomali,
    required this.deskripsi,
    required this.statusTindakLanjut,
    required this.jenisRespons,
    required this.keterangan,
    required this.diperiksaOleh,
    required this.diperiksaAt,
    this.statusAssignment,
    this.jumlahRespons = 0,
    this.namaSls = '',
    this.subSls = '',
    this.namaPetugas = '',
  });

  factory AnomaliGabunganItem.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic v) {
      final s = v?.toString();
      if (s == null || s.isEmpty) return null;
      return DateTime.tryParse(s);
    }

    String? nullableString(dynamic v) {
      final s = v?.toString();
      return (s == null || s.isEmpty) ? null : s;
    }

    return AnomaliGabunganItem(
      sumber: (json['sumber'] ?? '').toString(),
      assignmentId: (json['assignment_id'] ?? '').toString(),
      kodeWilayah: (json['kode_wilayah'] ?? '').toString(),
      namaWilayah: (json['nama_wilayah'] ?? '').toString(),
      kategoriBesar: (json['kategori_besar'] ?? '').toString(),
      kategoriKode: (json['kategori_kode'] ?? '').toString(),
      kategoriLabel: (json['kategori_label'] ?? '').toString(),
      subjek: (json['subjek'] ?? '').toString(),
      noAnomali:
          json['no_anomali'] is int ? json['no_anomali'] as int : null,
      deskripsi: (json['deskripsi'] ?? '').toString(),
      statusTindakLanjut:
          (json['status_tindak_lanjut'] ?? 'belum_diperiksa').toString(),
      jenisRespons: nullableString(json['jenis_respons']),
      keterangan: nullableString(json['keterangan']),
      diperiksaOleh: nullableString(json['diperiksa_oleh']),
      diperiksaAt: parseDate(json['diperiksa_at']),
      statusAssignment: nullableString(json['status_assignment']),
      jumlahRespons: json['jumlah_respons'] is int
          ? json['jumlah_respons'] as int
          : int.tryParse(json['jumlah_respons']?.toString() ?? '') ?? 0,
      namaSls: (json['nm_sls'] ?? '').toString(),
      subSls: (json['sub_sls'] ?? '').toString(),
      namaPetugas: (json['nama_petugas'] ?? '').toString(),
    );
  }

  bool get isWilayah => sumber == 'kualitas';
  bool get isPusatBaru => sumber == 'pusat_baru';

  /// Scope pusat_baru ('usaha'/'keluarga') -- kategori_besar sudah berisi
  /// scope-nya langsung dari anomali_pusat_temuan.scope.
  String get scopePusatBaru => kategoriBesar;

  /// nama_subjek dipakai sbg bagian kunci respons gabungan -- '' utk
  /// wilayah (1 subjek/assignment via mv_anomali), subjek asli utk
  /// pusat_baru (1 assignment bisa >1 usaha/keluarga).
  String get responsNamaSubjek => isWilayah ? '' : subjek;

  /// "Sudah diperiksa" berarti ADA respons dari petugas manapun (jumlah_respons
  /// agregat), bukan cuma respons milik petugas yang sedang login --
  /// status_tindak_lanjut/jenis_respons di objek ini tetap spesifik ke
  /// petugas yang login (dipakai form edit di detail sheet).
  bool get sudahDitindaklanjuti => jumlahRespons > 0;

  /// Status yang ditampilkan di kartu (satu chip). Diselaraskan dengan
  /// [sudahDitindaklanjuti] supaya tidak kontradiktif (mis. latar hijau tapi
  /// chip "Belum Diperiksa"):
  /// - kalau petugas login sudah merespons -> tampilkan respons-nya
  ///   (perbaikan/konfirmasi_valid);
  /// - kalau belum, tapi ADA respons dari petugas lain -> "sudah_diperiksa";
  /// - kalau belum ada respons sama sekali -> "belum_diperiksa".
  String get statusEfektif {
    if (statusTindakLanjut.isNotEmpty &&
        statusTindakLanjut != 'belum_diperiksa') {
      return statusTindakLanjut;
    }
    return jumlahRespons > 0 ? 'sudah_diperiksa' : 'belum_diperiksa';
  }

  String get subjekLabel => subjek.isEmpty ? '-' : subjek;

  String get wilayahLabel => namaWilayah.isEmpty ? kodeWilayah : namaWilayah;

  /// Kelurahan/desa saja (tanpa kecamatan). [namaWilayah] dari RPC berformat
  /// "kecamatan / kelurahan"; ambil bagian setelah pemisah pertama.
  String get _kelurahan {
    if (namaWilayah.isEmpty) return '';
    final idx = namaWilayah.indexOf(' / ');
    return idx >= 0 ? namaWilayah.substring(idx + 3) : namaWilayah;
  }

  /// Label wilayah: kelurahan + nama SLS + sub SLS (tanpa kecamatan).
  /// Fallback ke kode 16 digit kalau semua nama tidak tersedia.
  String get wilayahLengkapLabel {
    final parts = <String>[];
    if (_kelurahan.isNotEmpty) parts.add(_kelurahan);
    if (namaSls.isNotEmpty) parts.add(namaSls);
    if (subSls.isNotEmpty) parts.add('Sub $subSls');
    if (parts.isEmpty) return kodeWilayah.isEmpty ? '-' : kodeWilayah;
    return parts.join(' / ');
  }

  String get sumberLabel => isWilayah ? 'Wilayah' : 'Pusat';

  /// Label ramah untuk kategori_besar: 'keluarga' -> 'Keluarga',
  /// 'usaha' -> 'Usaha', 'anggota' -> 'Anggota Keluarga'.
  String get kategoriBesarLabel {
    switch (kategoriBesar) {
      case 'anggota':
        return 'Anggota Keluarga';
      case 'usaha':
        return 'Usaha';
      case 'keluarga':
        return 'Keluarga';
      default:
        return kategoriBesar.isEmpty ? '-' : kategoriBesar;
    }
  }

  /// Label rincian: kode + nama, mis. "KP4 - Biaya Produksi Dominan".
  String get kategoriRincianLabel {
    if (kategoriKode.isEmpty) return kategoriLabel.isEmpty ? '-' : kategoriLabel;
    if (kategoriLabel.isEmpty) return kategoriKode;
    return '$kategoriKode - $kategoriLabel';
  }
}
