class UsahaOrganikItem {
  final String nama;
  final String alamat;
  final String keterangan;

  const UsahaOrganikItem({
    required this.nama,
    required this.alamat,
    required this.keterangan,
  });

  factory UsahaOrganikItem.fromJson(Map<String, dynamic> json) {
    return UsahaOrganikItem(
      nama: (json['nama'] ?? '').toString().trim(),
      alamat: (json['alamat'] ?? '').toString().trim(),
      keterangan: (json['keterangan'] ?? '').toString().trim(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'nama': nama,
      'alamat': alamat,
      'keterangan': keterangan,
    };
  }
}
