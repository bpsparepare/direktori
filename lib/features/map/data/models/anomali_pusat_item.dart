class AnomaliPusatItem {
  final String assignmentId;
  final String nama;
  final String alamat;
  final String namaAnomali;
  final String kategori;
  final String tindakLanjut;
  final String statusText;
  final String kodeWilayah;
  final String nmKec;
  final String nmDesa;
  final String nmSls;
  final String pplId;
  final String pmlId;
  final String namaPpl;
  final String namaPml;

  const AnomaliPusatItem({
    required this.assignmentId,
    required this.nama,
    required this.alamat,
    required this.namaAnomali,
    required this.kategori,
    required this.tindakLanjut,
    required this.statusText,
    required this.kodeWilayah,
    required this.nmKec,
    required this.nmDesa,
    required this.nmSls,
    required this.pplId,
    required this.pmlId,
    required this.namaPpl,
    required this.namaPml,
  });

  factory AnomaliPusatItem.fromJson(Map<String, dynamic> json) {
    return AnomaliPusatItem(
      assignmentId: (json['assignment_id'] ?? '').toString(),
      nama: (json['nama'] ?? '').toString(),
      alamat: (json['alamat'] ?? '').toString(),
      namaAnomali: (json['nama_anomali'] ?? '').toString(),
      kategori: (json['kategori'] ?? '').toString(),
      tindakLanjut: (json['tindak_lanjut'] ?? '').toString(),
      statusText: (json['status_text'] ?? '').toString(),
      kodeWilayah: (json['kode_wilayah'] ?? '').toString(),
      nmKec: (json['nm_kec'] ?? '').toString(),
      nmDesa: (json['nm_desa'] ?? '').toString(),
      nmSls: (json['nm_sls'] ?? '').toString(),
      pplId: (json['ppl_id'] ?? '').toString(),
      pmlId: (json['pml_id'] ?? '').toString(),
      namaPpl: (json['nama_ppl'] ?? '').toString(),
      namaPml: (json['nama_pml'] ?? '').toString(),
    );
  }

  String get lokasiLabel {
    final parts = [nmKec, nmDesa, nmSls].where((s) => s.isNotEmpty).toList();
    return parts.isEmpty ? kodeWilayah : parts.join(' / ');
  }

  bool get sudahDitindak =>
      tindakLanjut.isNotEmpty && tindakLanjut != 'belum_diperiksa';
}
