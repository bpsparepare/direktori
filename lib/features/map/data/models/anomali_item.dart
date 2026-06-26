class AnomalyItem {
  final String assignmentId;
  final String kodeWilayah;
  final String namaWilayah;
  final String kategori;
  final int? noUsaha;
  final String namaSubjek;
  final int noAnomali;
  final String deskripsi;
  final String statusAnomali;
  final Map<String, dynamic> detail;

  // tindak lanjut
  final int? temuanId;
  final String statusTindakLanjut;
  final String catatanPetugas;
  final String diperiksaOleh;
  final DateTime? diperiksaAt;

  const AnomalyItem({
    required this.assignmentId,
    required this.kodeWilayah,
    required this.namaWilayah,
    required this.kategori,
    required this.noUsaha,
    required this.namaSubjek,
    required this.noAnomali,
    required this.deskripsi,
    required this.statusAnomali,
    required this.detail,
    required this.temuanId,
    required this.statusTindakLanjut,
    required this.catatanPetugas,
    required this.diperiksaOleh,
    required this.diperiksaAt,
  });

  factory AnomalyItem.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic v) {
      final s = v?.toString();
      if (s == null || s.isEmpty) return null;
      return DateTime.tryParse(s);
    }

    Map<String, dynamic> parseDetail(dynamic v) {
      if (v is Map<String, dynamic>) return v;
      if (v is Map) return v.map((k, val) => MapEntry(k.toString(), val));
      return const {};
    }

    return AnomalyItem(
      assignmentId: (json['assignment_id'] ?? '').toString(),
      kodeWilayah: (json['kode_wilayah'] ?? '').toString(),
      namaWilayah: (json['nama_wilayah'] ?? '').toString(),
      kategori: (json['kategori'] ?? '').toString(),
      noUsaha: json['no_usaha'] is int ? json['no_usaha'] as int : null,
      namaSubjek: (json['nama_subjek'] ?? '').toString(),
      noAnomali: json['no_anomali'] is int
          ? json['no_anomali'] as int
          : int.tryParse(json['no_anomali']?.toString() ?? '') ?? 0,
      deskripsi: (json['deskripsi'] ?? '').toString(),
      statusAnomali: (json['status_anomali'] ?? '').toString(),
      detail: parseDetail(json['detail']),
      temuanId: json['temuan_id'] is int ? json['temuan_id'] as int : null,
      statusTindakLanjut:
          (json['status_tindak_lanjut'] ?? 'belum_diperiksa').toString(),
      catatanPetugas: (json['catatan_petugas'] ?? '').toString(),
      diperiksaOleh: (json['diperiksa_oleh'] ?? '').toString(),
      diperiksaAt: parseDate(json['diperiksa_at']),
    );
  }

  bool get sudahDitindaklanjuti =>
      statusTindakLanjut.isNotEmpty &&
      statusTindakLanjut != 'belum_diperiksa';

  bool get isFatal => statusAnomali.toLowerCase().contains('fatal');

  String get subjekLabel => namaSubjek.isEmpty ? '-' : namaSubjek;

  String get wilayahLabel => namaWilayah.isEmpty ? kodeWilayah : namaWilayah;
}
