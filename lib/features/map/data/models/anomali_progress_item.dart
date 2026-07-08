/// Satu baris agregat progres pemeriksaan anomali pusat dari RPC
/// get_anomali_pusat_progress(). [dimensi] menandakan level breakdown:
/// 'pml' (per pengawas), 'ppl' (per petugas), atau 'self' (pendata sendiri).
class AnomaliProgressItem {
  final String dimensi;
  final String grupId;
  final String grupNama;
  final int total;
  final int sudah;

  const AnomaliProgressItem({
    required this.dimensi,
    required this.grupId,
    required this.grupNama,
    required this.total,
    required this.sudah,
  });

  factory AnomaliProgressItem.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic v) =>
        v is int ? v : int.tryParse(v?.toString() ?? '') ?? 0;
    return AnomaliProgressItem(
      dimensi: (json['dimensi'] ?? '').toString(),
      grupId: (json['grup_id'] ?? '').toString(),
      grupNama: (json['grup_nama'] ?? '-').toString(),
      total: asInt(json['total']),
      sudah: asInt(json['sudah']),
    );
  }

  int get belum => (total - sudah).clamp(0, total);

  double get persen => total == 0 ? 0 : (sudah / total).clamp(0, 1).toDouble();
}
