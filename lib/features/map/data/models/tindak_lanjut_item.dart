/// Satu assignment yang belum submit (REJECTED/DRAFT/OPEN) dari
/// `se2026_tindak_lanjut`, beserta tanda "perlu dihapus" dari tabel terpisah
/// `se2026_tindak_lanjut_hapus`.
class TindakLanjutItem {
  final String assignmentId;
  final String statusAlias;
  final String kodeWilayah;
  final String level6Name;
  final String nama;
  final String alamat;
  final String noBang;
  final String nmKec;
  final String nmDesa;
  final String nmSls;
  final String pplNama;
  final String pmlNama;
  final bool perluHapus;
  final String alasanHapus;
  final String hapusOleh;
  final DateTime? hapusAt;

  const TindakLanjutItem({
    required this.assignmentId,
    required this.statusAlias,
    required this.kodeWilayah,
    required this.level6Name,
    required this.nama,
    required this.alamat,
    required this.noBang,
    required this.nmKec,
    required this.nmDesa,
    required this.nmSls,
    required this.pplNama,
    required this.pmlNama,
    required this.perluHapus,
    required this.alasanHapus,
    required this.hapusOleh,
    required this.hapusAt,
  });

  factory TindakLanjutItem.fromJson(Map<String, dynamic> json) {
    String s(String key) => (json[key] ?? '').toString().trim();
    return TindakLanjutItem(
      assignmentId: s('assignment_id'),
      statusAlias: s('assignment_status_alias'),
      kodeWilayah: s('level_6_full_code'),
      level6Name: s('level_6_name'),
      nama: s('nama'),
      alamat: s('alamat'),
      noBang: s('no_bang'),
      nmKec: s('nm_kec'),
      nmDesa: s('nm_desa'),
      nmSls: s('nm_sls'),
      pplNama: s('ppl_nama'),
      pmlNama: s('pml_nama'),
      perluHapus: json['perlu_hapus'] == true,
      alasanHapus: s('alasan_hapus'),
      hapusOleh: s('hapus_oleh'),
      hapusAt: DateTime.tryParse(s('hapus_at'))?.toLocal(),
    );
  }

  /// Nama SLS + kode sub-SLS (2 digit terakhir kode 16 digit; 00 = tanpa sub).
  String get slsLabel {
    final nama = nmSls.isNotEmpty ? nmSls : level6Name;
    final sub = kodeWilayah.length == 16 ? kodeWilayah.substring(14) : '';
    final hasSub = sub.isNotEmpty && (int.tryParse(sub) ?? 0) != 0;
    if (nama.isEmpty) return kodeWilayah;
    return hasSub ? '$nama $sub' : nama;
  }

  TindakLanjutItem copyWithHapus({
    required bool perluHapus,
    String alasanHapus = '',
    String hapusOleh = '',
    DateTime? hapusAt,
  }) {
    return TindakLanjutItem(
      assignmentId: assignmentId,
      statusAlias: statusAlias,
      kodeWilayah: kodeWilayah,
      level6Name: level6Name,
      nama: nama,
      alamat: alamat,
      noBang: noBang,
      nmKec: nmKec,
      nmDesa: nmDesa,
      nmSls: nmSls,
      pplNama: pplNama,
      pmlNama: pmlNama,
      perluHapus: perluHapus,
      alasanHapus: alasanHapus,
      hapusOleh: hapusOleh,
      hapusAt: hapusAt,
    );
  }
}
