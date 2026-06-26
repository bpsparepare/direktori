class AnomaliTemuanItem {
  final int id;
  final String anomaliId;
  final String scope;
  final String assignmentId;
  final String kodeWilayah;
  final String nama;
  final String wilayah;
  final String keterangan;
  final String detail;
  final String statusTindakLanjut;
  final String catatanPetugas;
  final String diperiksaOleh;
  final DateTime? diperiksaAt;
  final DateTime? createdAt;
  final String kategori;
  final String deskripsiRule;

  const AnomaliTemuanItem({
    required this.id,
    required this.anomaliId,
    required this.scope,
    required this.assignmentId,
    required this.kodeWilayah,
    required this.nama,
    required this.wilayah,
    required this.keterangan,
    required this.detail,
    required this.statusTindakLanjut,
    required this.catatanPetugas,
    required this.diperiksaOleh,
    required this.diperiksaAt,
    required this.createdAt,
    required this.kategori,
    required this.deskripsiRule,
  });

  factory AnomaliTemuanItem.fromJson(
    Map<String, dynamic> json, {
    Map<String, dynamic>? kategoriJson,
  }) {
    DateTime? parseDate(dynamic value) {
      final raw = value?.toString();
      if (raw == null || raw.isEmpty) return null;
      return DateTime.tryParse(raw);
    }

    return AnomaliTemuanItem(
      id: json['id'] is int
          ? json['id'] as int
          : int.tryParse(json['id']?.toString() ?? '') ?? 0,
      anomaliId: (json['anomali_id'] ?? '').toString().trim(),
      scope: (json['scope'] ?? '').toString().trim(),
      assignmentId: (json['assignment_id'] ?? '').toString().trim(),
      kodeWilayah: (json['kode_wilayah'] ?? '').toString().trim(),
      nama: (json['nama'] ?? '').toString().trim(),
      wilayah: (json['wilayah'] ?? '').toString().trim(),
      keterangan: (json['keterangan'] ?? '').toString().trim(),
      detail: (json['detail'] ?? '').toString().trim(),
      statusTindakLanjut:
          (json['status_tindak_lanjut'] ?? '').toString().trim(),
      catatanPetugas: (json['catatan_petugas'] ?? '').toString().trim(),
      diperiksaOleh: (json['diperiksa_oleh'] ?? '').toString().trim(),
      diperiksaAt: parseDate(json['diperiksa_at']),
      createdAt: parseDate(json['created_at']),
      kategori: (kategoriJson?['kategori'] ?? '').toString().trim(),
      deskripsiRule: (kategoriJson?['deskripsi_rule'] ?? '').toString().trim(),
    );
  }

  bool get sudahDitindaklanjuti =>
      statusTindakLanjut.isNotEmpty &&
      statusTindakLanjut != 'belum_diperiksa';

  String get kategoriLabel =>
      kategori.isEmpty ? 'Kategori tidak tersedia' : kategori;

  String get detailLabel => detail.isEmpty ? '-' : detail;

  String get catatanLabel => catatanPetugas.isEmpty ? '-' : catatanPetugas;

  String get pemeriksaLabel => diperiksaOleh.isEmpty ? '-' : diperiksaOleh;

  String get ruleLabel => deskripsiRule.isEmpty ? '-' : deskripsiRule;
}
