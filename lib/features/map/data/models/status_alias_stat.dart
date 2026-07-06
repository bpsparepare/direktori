/// Satu baris statistik jumlah dokumen se2026_keterangan_umum yang
/// dikelompokkan berdasarkan assignment_status_alias.
class StatusAliasStat {
  final String alias;
  final int jumlah;

  const StatusAliasStat({required this.alias, required this.jumlah});

  factory StatusAliasStat.fromJson(Map<String, dynamic> json) {
    final rawAlias = json['status_text'] ?? json['assignment_status_alias'];
    final alias = (rawAlias == null || rawAlias.toString().trim().isEmpty)
        ? 'Tidak Diketahui'
        : rawAlias.toString().trim();
    final rawJumlah = json['jumlah'];
    final jumlah = rawJumlah is num
        ? rawJumlah.toInt()
        : int.tryParse(rawJumlah?.toString() ?? '') ?? 0;
    return StatusAliasStat(alias: alias, jumlah: jumlah);
  }
}

/// Statistik silang: satu Status Assignment beserta rincian jumlah per
/// kode_bang di dalamnya.
class StatusKodeBangGroup {
  final String status;
  final int total;
  final List<StatusAliasStat> breakdown;

  const StatusKodeBangGroup({
    required this.status,
    required this.total,
    required this.breakdown,
  });
}
