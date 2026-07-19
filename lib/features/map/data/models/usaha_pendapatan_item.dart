/// Satu baris hasil get_usaha_pendapatan_ekstrem(): usaha kandidat anomali
/// pendapatan (tinggi/rendah).
class UsahaPendapatanItem {
  final String assignmentId;
  final int noUsaha;
  final String namaSubjek;
  final num totalPendapatan;
  final String kodeWilayah;
  final String namaKec;
  final String namaDesa;
  final String namaSls;
  final bool sudahAnomali;

  const UsahaPendapatanItem({
    required this.assignmentId,
    required this.noUsaha,
    required this.namaSubjek,
    required this.totalPendapatan,
    required this.kodeWilayah,
    required this.namaKec,
    required this.namaDesa,
    required this.namaSls,
    required this.sudahAnomali,
  });

  factory UsahaPendapatanItem.fromJson(Map<String, dynamic> json) {
    num asNum(dynamic v) =>
        v is num ? v : num.tryParse(v?.toString() ?? '') ?? 0;
    return UsahaPendapatanItem(
      assignmentId: (json['assignment_id'] ?? '').toString(),
      noUsaha: json['no_usaha'] is int
          ? json['no_usaha'] as int
          : int.tryParse(json['no_usaha']?.toString() ?? '') ?? 0,
      namaSubjek: (json['nama_subjek'] ?? '-').toString(),
      totalPendapatan: asNum(json['total_pendapatan']),
      kodeWilayah: (json['kode_wilayah'] ?? '').toString(),
      namaKec: (json['nama_kec'] ?? '').toString(),
      namaDesa: (json['nama_desa'] ?? '').toString(),
      namaSls: (json['nama_sls'] ?? '').toString(),
      sudahAnomali: json['sudah_anomali'] == true,
    );
  }

  /// Kunci unik baris (assignment + nomor usaha).
  String get key => '$assignmentId#$noUsaha';

  String get wilayahLabel {
    final parts = [namaDesa, namaSls]
        .where((v) => v.trim().isNotEmpty)
        .toList();
    return parts.isEmpty ? kodeWilayah : parts.join(' / ');
  }
}
