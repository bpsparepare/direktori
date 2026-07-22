/// Satu baris hasil get_usaha_kbli(): usaha beserta KBLI/keg_utama/produk untuk
/// pengecekan "Salah Penentuan KBLI".
class UsahaKbliItem {
  final String assignmentId;
  final int noUsaha;
  final String namaSubjek;
  final String kbli;
  final String kegUtama;
  final String produk;
  final String jenisUsaha;
  final String kodeWilayah;
  final String namaKec;
  final String namaDesa;
  final String namaSls;
  final String kategori;
  final String statusText;
  final String namaPetugas;
  final bool sudahAnomali;
  final String komentarAdmin;

  const UsahaKbliItem({
    required this.assignmentId,
    required this.noUsaha,
    required this.namaSubjek,
    required this.kbli,
    required this.kegUtama,
    required this.produk,
    required this.jenisUsaha,
    required this.kodeWilayah,
    required this.namaKec,
    required this.namaDesa,
    required this.namaSls,
    required this.kategori,
    required this.statusText,
    required this.namaPetugas,
    required this.sudahAnomali,
    required this.komentarAdmin,
  });

  factory UsahaKbliItem.fromJson(Map<String, dynamic> json) {
    String s(dynamic v) => (v ?? '').toString();
    return UsahaKbliItem(
      assignmentId: s(json['assignment_id']),
      noUsaha: json['no_usaha'] is int
          ? json['no_usaha'] as int
          : int.tryParse(s(json['no_usaha'])) ?? 0,
      namaSubjek: (json['nama_subjek'] ?? '-').toString(),
      kbli: s(json['kbli']),
      kegUtama: s(json['keg_utama']),
      produk: s(json['produk']),
      jenisUsaha: s(json['jenis_usaha']),
      kodeWilayah: s(json['kode_wilayah']),
      namaKec: s(json['nama_kec']),
      namaDesa: s(json['nama_desa']),
      namaSls: s(json['nama_sls']),
      kategori: s(json['kategori']),
      statusText: s(json['status_text']),
      namaPetugas: s(json['nama_petugas']),
      sudahAnomali: json['sudah_anomali'] == true,
      komentarAdmin: s(json['komentar_admin']),
    );
  }

  String get key => '$assignmentId#$noUsaha';

  String get wilayahLabel {
    final parts =
        [namaDesa, namaSls].where((v) => v.trim().isNotEmpty).toList();
    return parts.isEmpty ? kodeWilayah : parts.join(' / ');
  }
}
