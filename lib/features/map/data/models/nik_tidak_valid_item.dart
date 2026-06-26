class NikTidakValidItem {
  final String assignmentId;
  final String? nikDtsen;
  final String kategori;
  final String namaDtsen;
  final int noUrut;
  final String status;
  final String kodeWilayah;
  final String namaKk;
  final String nmKec;
  final String nmDesa;
  final String nmSls;
  final String? kodeSubsls;
  final String? namaPpl;

  const NikTidakValidItem({
    required this.assignmentId,
    required this.nikDtsen,
    required this.kategori,
    required this.namaDtsen,
    required this.noUrut,
    required this.status,
    required this.kodeWilayah,
    required this.namaKk,
    required this.nmKec,
    required this.nmDesa,
    required this.nmSls,
    required this.kodeSubsls,
    required this.namaPpl,
  });

  factory NikTidakValidItem.fromJson(Map<String, dynamic> json) {
    return NikTidakValidItem(
      assignmentId: (json['assignment_id'] ?? '').toString(),
      nikDtsen: json['nik_dtsen']?.toString(),
      kategori: (json['kategori'] ?? '').toString(),
      namaDtsen: (json['nama_dtsen'] ?? '').toString(),
      noUrut: (json['no_urut'] as num?)?.toInt() ?? 0,
      status: (json['status'] ?? '').toString(),
      kodeWilayah: (json['kode_wilayah'] ?? '').toString(),
      namaKk: (json['nama_kk'] ?? '').toString(),
      nmKec: (json['nm_kec'] ?? '').toString(),
      nmDesa: (json['nm_desa'] ?? '').toString(),
      nmSls: (json['nm_sls'] ?? '').toString(),
      kodeSubsls: json['kode_subsls']?.toString(),
      namaPpl: json['nama_ppl']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'assignment_id': assignmentId,
      'nik_dtsen': nikDtsen,
      'kategori': kategori,
      'nama_dtsen': namaDtsen,
      'no_urut': noUrut,
      'status': status,
      'kode_wilayah': kodeWilayah,
      'nama_kk': namaKk,
      'nm_kec': nmKec,
      'nm_desa': nmDesa,
      'nm_sls': nmSls,
      'kode_subsls': kodeSubsls,
      'nama_ppl': namaPpl,
    };
  }
}
