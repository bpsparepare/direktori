import 'revisit_models.dart';

/// Satu assignment pada daftar "Reject" revisit (sumber:
/// `se2026_revisit_reject_sumber`, diisi ulang tiap impor ekstensi) beserta
/// tanda "perlu di-reject" dari tabel terpisah `se2026_revisit_reject`.
class RevisitRejectItem {
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

  /// Petugas revisit yang memegang SLS ini (kosong = belum dialokasikan).
  final String revisitPetugasId;
  final String revisitNama;
  final String revisitTim;
  final int? hariKe;

  final bool perluReject;
  final String alasanReject;
  final String rejectOleh;
  final DateTime? rejectAt;

  const RevisitRejectItem({
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
    required this.revisitPetugasId,
    required this.revisitNama,
    required this.revisitTim,
    required this.hariKe,
    required this.perluReject,
    required this.alasanReject,
    required this.rejectOleh,
    required this.rejectAt,
  });

  factory RevisitRejectItem.fromJson(Map<String, dynamic> json) {
    String s(String key) => (json[key] ?? '').toString().trim();
    return RevisitRejectItem(
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
      revisitPetugasId: s('revisit_petugas_id'),
      revisitNama: s('revisit_nama'),
      revisitTim: s('revisit_tim'),
      hariKe: (json['hari_ke'] as num?)?.toInt(),
      perluReject: json['perlu_reject'] == true,
      alasanReject: s('alasan_reject'),
      rejectOleh: s('reject_oleh'),
      rejectAt: DateTime.tryParse(s('reject_at'))?.toLocal(),
    );
  }

  String get slsLabel =>
      revisitSlsLabel(kodeWilayah, nmSls.isNotEmpty ? nmSls : level6Name);

  RevisitRejectItem copyWithReject({
    required bool perluReject,
    String alasanReject = '',
    String rejectOleh = '',
    DateTime? rejectAt,
  }) {
    return RevisitRejectItem(
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
      revisitPetugasId: revisitPetugasId,
      revisitNama: revisitNama,
      revisitTim: revisitTim,
      hariKe: hariKe,
      perluReject: perluReject,
      alasanReject: alasanReject,
      rejectOleh: rejectOleh,
      rejectAt: rejectAt,
    );
  }
}

/// Ringkasan satu SLS pada tab Reject (dimuat lebih dulu; isi assignment
/// baru diambil saat SLS dibuka).
class RevisitRejectSls {
  final String kodeSls;
  final String level6Name;
  final String nmKec;
  final String nmDesa;
  final String nmSls;
  final String revisitPetugasId;
  final String revisitNama;
  final String revisitTim;
  final int? hariKe;
  final int jumlahAssignment;
  final int jumlahDitandai;

  const RevisitRejectSls({
    required this.kodeSls,
    required this.level6Name,
    required this.nmKec,
    required this.nmDesa,
    required this.nmSls,
    required this.revisitPetugasId,
    required this.revisitNama,
    required this.revisitTim,
    required this.hariKe,
    required this.jumlahAssignment,
    required this.jumlahDitandai,
  });

  factory RevisitRejectSls.fromJson(Map<String, dynamic> json) {
    String s(String key) => (json[key] ?? '').toString().trim();
    return RevisitRejectSls(
      kodeSls: s('kode_sls'),
      level6Name: s('level_6_name'),
      nmKec: s('nm_kec'),
      nmDesa: s('nm_desa'),
      nmSls: s('nm_sls'),
      revisitPetugasId: s('revisit_petugas_id'),
      revisitNama: s('revisit_nama'),
      revisitTim: s('revisit_tim'),
      hariKe: (json['hari_ke'] as num?)?.toInt(),
      jumlahAssignment: (json['jumlah_assignment'] as num?)?.toInt() ?? 0,
      jumlahDitandai: (json['jumlah_ditandai'] as num?)?.toInt() ?? 0,
    );
  }

  String get slsLabel =>
      revisitSlsLabel(kodeSls, nmSls.isNotEmpty ? nmSls : level6Name);

  RevisitRejectSls withDitandai(int jumlah) => RevisitRejectSls(
    kodeSls: kodeSls,
    level6Name: level6Name,
    nmKec: nmKec,
    nmDesa: nmDesa,
    nmSls: nmSls,
    revisitPetugasId: revisitPetugasId,
    revisitNama: revisitNama,
    revisitTim: revisitTim,
    hariKe: hariKe,
    jumlahAssignment: jumlahAssignment,
    jumlahDitandai: jumlah,
  );
}
