class RespondenSulitItem {
  final String id;
  final String kodeWilayah;
  final String nmKec;
  final String nmDesa;
  final String nmSls;
  final String subSls;
  final String pplNama;
  final String pmlNama;
  final String createdByNama;
  final String nama;
  final String alamat;
  final String penjelasan;
  final String tindakLanjut;
  final bool canEdit;
  final DateTime updatedAt;

  const RespondenSulitItem({
    required this.id,
    required this.kodeWilayah,
    required this.nmKec,
    required this.nmDesa,
    required this.nmSls,
    required this.subSls,
    required this.pplNama,
    required this.pmlNama,
    required this.createdByNama,
    required this.nama,
    required this.alamat,
    required this.penjelasan,
    required this.tindakLanjut,
    required this.canEdit,
    required this.updatedAt,
  });

  factory RespondenSulitItem.fromJson(Map<String, dynamic> json) {
    return RespondenSulitItem(
      id: (json['id'] ?? '').toString(),
      kodeWilayah: (json['kode_wilayah'] ?? '').toString(),
      nmKec: (json['nm_kec'] ?? '').toString(),
      nmDesa: (json['nm_desa'] ?? '').toString(),
      nmSls: (json['nm_sls'] ?? '').toString(),
      subSls: (json['sub_sls'] ?? '').toString(),
      pplNama: (json['ppl_nama'] ?? '').toString(),
      pmlNama: (json['pml_nama'] ?? '').toString(),
      createdByNama: (json['created_by_nama'] ?? '').toString(),
      nama: (json['nama'] ?? '').toString(),
      alamat: (json['alamat'] ?? '').toString(),
      penjelasan: (json['penjelasan'] ?? '').toString(),
      tindakLanjut: (json['tindak_lanjut'] ?? '').toString(),
      canEdit: json['can_edit'] == true,
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  /// Label wilayah singkat (SLS + sub-SLS / desa / kecamatan) untuk chip.
  String get wilayahLabel {
    final sls = formatSlsLabel(nmSls, subSls);
    final parts = [sls, nmDesa, nmKec]
        .where((value) => value.trim().isNotEmpty)
        .toList();
    return parts.isEmpty ? '' : parts.join(' · ');
  }

  /// Gabungkan nama SLS dengan kode sub-SLS di sampingnya. Sub-SLS 0/00
  /// dianggap tanpa sub sehingga tidak ditulis.
  static String formatSlsLabel(String nmSls, String subSls) {
    final nama = nmSls.trim();
    final sub = subSls.trim();
    final hasSub = sub.isNotEmpty && (int.tryParse(sub) ?? 0) != 0;
    if (nama.isEmpty) return hasSub ? sub : '';
    return hasSub ? '$nama $sub' : nama;
  }
}
