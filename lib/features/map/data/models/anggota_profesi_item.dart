/// Satu baris hasil get_anggota_profesi(): anggota keluarga berprofesi +
/// agregat usaha di assignment yang sama.
class AnggotaProfesiItem {
  final String assignmentId;
  final int noUrut;
  final String namaKk;
  final String namaSubjek;
  final String profesi; // kode
  final String kodeWilayah;
  final String namaKec;
  final String namaDesa;
  final String namaSls;
  final String statusText;
  final String namaPetugas;
  final int jumlahUsaha;
  final String daftarUsaha;
  final bool sudahAnomali;
  final String komentarAdmin;

  const AnggotaProfesiItem({
    required this.assignmentId,
    required this.noUrut,
    required this.namaKk,
    required this.namaSubjek,
    required this.profesi,
    required this.kodeWilayah,
    required this.namaKec,
    required this.namaDesa,
    required this.namaSls,
    required this.statusText,
    required this.namaPetugas,
    required this.jumlahUsaha,
    required this.daftarUsaha,
    required this.sudahAnomali,
    required this.komentarAdmin,
  });

  factory AnggotaProfesiItem.fromJson(Map<String, dynamic> json) {
    String s(dynamic v) => (v ?? '').toString();
    int asInt(dynamic v) =>
        v is int ? v : int.tryParse(s(v)) ?? 0;
    return AnggotaProfesiItem(
      assignmentId: s(json['assignment_id']),
      noUrut: asInt(json['no_urut']),
      namaKk: s(json['nama_kk']),
      namaSubjek: (json['nama_subjek'] ?? '-').toString(),
      profesi: s(json['profesi']),
      kodeWilayah: s(json['kode_wilayah']),
      namaKec: s(json['nama_kec']),
      namaDesa: s(json['nama_desa']),
      namaSls: s(json['nama_sls']),
      statusText: s(json['status_text']),
      namaPetugas: s(json['nama_petugas']),
      jumlahUsaha: asInt(json['jumlah_usaha']),
      daftarUsaha: s(json['daftar_usaha']),
      sudahAnomali: json['sudah_anomali'] == true,
      komentarAdmin: s(json['komentar_admin']),
    );
  }

  String get key => '$assignmentId#$noUrut';

  bool get tanpaUsaha => jumlahUsaha == 0;

  String get wilayahLabel {
    final parts =
        [namaDesa, namaSls].where((v) => v.trim().isNotEmpty).toList();
    return parts.isEmpty ? kodeWilayah : parts.join(' / ');
  }
}
