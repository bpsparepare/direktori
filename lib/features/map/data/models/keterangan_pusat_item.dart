class KeteranganPusatItem {
  final String petugasId;
  final String namaPetugas;
  final String role;
  final String keterangan;
  final DateTime updatedAt;

  const KeteranganPusatItem({
    required this.petugasId,
    required this.namaPetugas,
    required this.role,
    required this.keterangan,
    required this.updatedAt,
  });

  factory KeteranganPusatItem.fromJson(Map<String, dynamic> json) {
    return KeteranganPusatItem(
      petugasId: (json['petugas_id'] ?? '').toString(),
      namaPetugas: (json['nama_petugas'] ?? '').toString(),
      role: (json['role'] ?? '').toString(),
      keterangan: (json['keterangan'] ?? '').toString(),
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  String get roleLabel {
    switch (role) {
      case 'pendata':
        return 'PPL';
      case 'pengawas':
        return 'PML';
      case 'admin':
        return 'Admin';
      default:
        return role;
    }
  }
}
