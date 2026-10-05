import 'package:flutter/material.dart';

/// Model fitur "Revisit" (kunjungan ulang SLS). Lihat
/// supabase/migrations/20260919120000_revisit.sql.

String _s(Map<String, dynamic> json, String key) =>
    (json[key] ?? '').toString().trim();

/// Nama SLS + kode sub-SLS (2 digit terakhir kode 16 digit; 00 = tanpa sub).
String revisitSlsLabel(String kodeSls, String nmSls) {
  final sub = kodeSls.length == 16 ? kodeSls.substring(14) : '';
  final hasSub = sub.isNotEmpty && (int.tryParse(sub) ?? 0) != 0;
  if (nmSls.isEmpty) return kodeSls;
  return hasSub ? '$nmSls $sub' : nmSls;
}

String revisitRoleLabel(String role) {
  switch (role) {
    case 'pengawas':
      return 'PML';
    case 'pendata':
      return 'PPL';
    case 'admin':
      return 'Admin';
  }
  return role;
}

/// Tanggal (tanpa jam) sebagai `yyyy-MM-dd` untuk parameter RPC.
String revisitDateParam(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

const List<String> _namaBulan = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'Mei',
  'Jun',
  'Jul',
  'Agu',
  'Sep',
  'Okt',
  'Nov',
  'Des',
];
const List<String> _namaHari = [
  'Senin',
  'Selasa',
  'Rabu',
  'Kamis',
  'Jumat',
  'Sabtu',
  'Minggu',
];

/// Contoh: "Sabtu, 19 Sep 2026" (withDay) atau "19 Sep 2026".
String revisitDateLabel(DateTime d, {bool withDay = false}) {
  final base = '${d.day} ${_namaBulan[d.month - 1]} ${d.year}';
  return withDay ? '${_namaHari[d.weekday - 1]}, $base' : base;
}

/// Label tim: "3" -> "Tim 3"; label yang sudah diawali "tim" dibiarkan.
String revisitTimLabel(String tim) {
  final t = tim.trim();
  if (t.isEmpty) return 'Tanpa tim';
  return t.toLowerCase().startsWith('tim') ? t : 'Tim $t';
}

int? _i(Map<String, dynamic> json, String key) => (json[key] as num?)?.toInt();

class RevisitStatus {
  final String value;
  final String label;
  final Color color;
  final IconData icon;

  const RevisitStatus(this.value, this.label, this.color, this.icon);

  static const List<RevisitStatus> all = [
    RevisitStatus(
      'selesai',
      'Selesai',
      Color(0xFF2E7D32),
      Icons.check_circle_rounded,
    ),
    RevisitStatus(
      'belum_selesai',
      'Belum Selesai',
      Color(0xFFEA8600),
      Icons.timelapse_rounded,
    ),
    RevisitStatus(
      'kunjungan_ulang',
      'Perlu Kunjungan Ulang',
      Color(0xFF1565C0),
      Icons.replay_rounded,
    ),
    RevisitStatus(
      'tidak_ditemukan',
      'Tidak Ditemukan',
      Color(0xFFC62828),
      Icons.location_off_rounded,
    ),
  ];

  static RevisitStatus? of(String value) {
    for (final s in all) {
      if (s.value == value) return s;
    }
    return null;
  }
}

/// Petugas aktif (PML/PPL) beserta penanda keanggotaan tim revisit.
class RevisitPetugas {
  final String petugasId;
  final String nama;
  final String email;
  final String role;
  final bool isRevisit;
  final int jumlahSls;

  /// Label tim (2 orang per tim); informasi saja, alokasi tetap per orang.
  final String tim;

  const RevisitPetugas({
    required this.petugasId,
    required this.nama,
    required this.email,
    required this.role,
    required this.isRevisit,
    required this.jumlahSls,
    required this.tim,
  });

  factory RevisitPetugas.fromJson(Map<String, dynamic> json) {
    return RevisitPetugas(
      petugasId: _s(json, 'petugas_id'),
      nama: _s(json, 'nama'),
      email: _s(json, 'email'),
      role: _s(json, 'role'),
      isRevisit: json['is_revisit'] == true,
      jumlahSls: (json['jumlah_sls'] as num?)?.toInt() ?? 0,
      tim: _s(json, 'tim'),
    );
  }
}

/// Satu SLS wilayah tugas + petugas revisit yang dialokasikan (bila ada).
/// Satu baris jadwal: hari ke- + petugas pemiliknya.
class RevisitJadwal {
  /// 0 = hari belum ditentukan.
  final int hariKe;
  final String petugasId;
  final String nama;
  final String tim;

  const RevisitJadwal({
    required this.hariKe,
    required this.petugasId,
    required this.nama,
    required this.tim,
  });

  factory RevisitJadwal.fromJson(Map<String, dynamic> json) {
    return RevisitJadwal(
      hariKe: _i(json, 'hari_ke') ?? 0,
      petugasId: _s(json, 'petugas_id'),
      nama: _s(json, 'nama'),
      tim: _s(json, 'tim'),
    );
  }

  String get hariLabel => hariKe == 0 ? 'Hari –' : 'H$hariKe';

  String get label => '$hariLabel · ${nama.isEmpty ? '-' : nama}';
}

/// Satu SLS wilayah tugas + jadwal revisitnya (bisa beberapa hari, dan tiap
/// hari boleh dipegang petugas berbeda).
class RevisitAlokasiItem {
  final String kodeSls;
  final String nmKec;
  final String nmDesa;
  final String nmSls;
  final String pmlNama;
  final String pplNama;
  final List<RevisitJadwal> jadwal;

  const RevisitAlokasiItem({
    required this.kodeSls,
    required this.nmKec,
    required this.nmDesa,
    required this.nmSls,
    required this.pmlNama,
    required this.pplNama,
    required this.jadwal,
  });

  factory RevisitAlokasiItem.fromJson(Map<String, dynamic> json) {
    final raw = json['jadwal'];
    return RevisitAlokasiItem(
      kodeSls: _s(json, 'kode_sls'),
      nmKec: _s(json, 'nm_kec'),
      nmDesa: _s(json, 'nm_desa'),
      nmSls: _s(json, 'nm_sls'),
      pmlNama: _s(json, 'pml_nama'),
      pplNama: _s(json, 'ppl_nama'),
      jadwal: raw is List
          ? raw
                .whereType<Map>()
                .map(
                  (j) => RevisitJadwal.fromJson(Map<String, dynamic>.from(j)),
                )
                .toList()
          : const [],
    );
  }

  bool get isAllocated => jadwal.isNotEmpty;

  List<int> get hariList => [for (final j in jadwal) j.hariKe];

  /// Semua petugas yang dijadwalkan pada [hariKe] (bisa lebih dari satu).
  List<RevisitJadwal> jadwalHari(int hariKe) => [
    for (final j in jadwal)
      if (j.hariKe == hariKe) j,
  ];

  bool dipegang(String petugasId) =>
      jadwal.any((j) => j.petugasId == petugasId);

  String get slsLabel => revisitSlsLabel(kodeSls, nmSls);
}

/// SLS yang dialokasikan ke petugas revisit yang sedang login.
class RevisitTugas {
  final String kodeSls;
  final String nmKec;
  final String nmDesa;
  final String nmSls;
  final int? hariKe;
  final int jumlahLaporan;
  final String statusTerakhir;
  final DateTime? tanggalTerakhir;

  /// Total didata dari semua laporan SLS ini.
  final int totalDidata;

  /// Total submit dari semua laporan SLS ini.
  final int totalSubmit;

  /// Sisa potensi belum didata menurut laporan terakhir (null = belum diisi).
  final int? belumDidata;

  /// Kunjungan terjadwal hari ini sudah dilakukan (jumlah laporan petugas
  /// ini >= urutan hari jadwalnya).
  final bool sudahDikunjungi;

  /// Jumlah laporan milik petugas ini di SLS tsb (angka lain = total SLS).
  final int laporanSaya;

  /// Laporan untuk jadwal (hari ke-) ini saja; null bila belum dibuat.
  final String statusHari;
  final DateTime? tanggalHari;
  final int? didataHari;
  final int? submitHari;

  const RevisitTugas({
    required this.kodeSls,
    required this.nmKec,
    required this.nmDesa,
    required this.nmSls,
    required this.hariKe,
    required this.jumlahLaporan,
    required this.statusTerakhir,
    required this.tanggalTerakhir,
    required this.totalDidata,
    required this.totalSubmit,
    required this.belumDidata,
    required this.sudahDikunjungi,
    required this.laporanSaya,
    required this.statusHari,
    required this.tanggalHari,
    required this.didataHari,
    required this.submitHari,
  });

  factory RevisitTugas.fromJson(Map<String, dynamic> json) {
    return RevisitTugas(
      kodeSls: _s(json, 'kode_sls'),
      nmKec: _s(json, 'nm_kec'),
      nmDesa: _s(json, 'nm_desa'),
      nmSls: _s(json, 'nm_sls'),
      hariKe: _i(json, 'hari_ke'),
      jumlahLaporan: (json['jumlah_laporan'] as num?)?.toInt() ?? 0,
      statusTerakhir: _s(json, 'status_terakhir'),
      tanggalTerakhir: DateTime.tryParse(_s(json, 'tanggal_terakhir')),
      totalDidata: _i(json, 'total_didata') ?? 0,
      totalSubmit: _i(json, 'total_submit') ?? 0,
      belumDidata: _i(json, 'belum_didata'),
      sudahDikunjungi: json['sudah_dikunjungi'] == true,
      laporanSaya: _i(json, 'laporan_saya') ?? 0,
      statusHari: _s(json, 'status_hari'),
      tanggalHari: DateTime.tryParse(_s(json, 'tanggal_hari')),
      didataHari: _i(json, 'didata_hari'),
      submitHari: _i(json, 'submit_hari'),
    );
  }

  String get slsLabel => revisitSlsLabel(kodeSls, nmSls);

  /// Proporsi didata terhadap (didata + sisa potensi); null bila sisa
  /// potensi belum pernah dilaporkan.
  double? get persenDidata {
    final sisa = belumDidata;
    if (sisa == null) return null;
    final total = totalDidata + sisa;
    return total == 0 ? 1 : totalDidata / total;
  }
}

class RevisitFoto {
  final String id;
  final String driveFileId;
  final String linkFile;
  final String namaFile;

  const RevisitFoto({
    required this.id,
    required this.driveFileId,
    required this.linkFile,
    required this.namaFile,
  });

  factory RevisitFoto.fromJson(Map<String, dynamic> json) {
    return RevisitFoto(
      id: _s(json, 'id'),
      driveFileId: _s(json, 'drive_file_id'),
      linkFile: _s(json, 'link_file'),
      namaFile: _s(json, 'nama_file'),
    );
  }

  /// Endpoint thumbnail Drive (file di-share publik saat upload).
  String thumbnailUrl({int size = 400}) =>
      'https://drive.google.com/thumbnail?id=$driveFileId&sz=w$size';

  String get viewUrl => linkFile.isNotEmpty
      ? linkFile
      : 'https://drive.google.com/file/d/$driveFileId/view';
}

class RevisitLaporan {
  final String id;
  final String kodeSls;
  final String nmKec;
  final String nmDesa;
  final String nmSls;
  final String petugasId;
  final String petugasNama;
  final String petugasRole;
  final String petugasTim;
  final int? hariKe;
  final DateTime tanggal;
  final String status;
  final int? jumlahDidata;

  /// Usaha/keluarga yang sudah di-submit.
  final int? jumlahSubmit;

  /// Sisa potensi usaha/keluarga yang belum didata saat laporan ini.
  final int? jumlahBelumDidata;
  final String catatan;
  final DateTime? updatedAt;
  final List<RevisitFoto> foto;

  const RevisitLaporan({
    required this.id,
    required this.kodeSls,
    required this.nmKec,
    required this.nmDesa,
    required this.nmSls,
    required this.petugasId,
    required this.petugasNama,
    required this.petugasRole,
    required this.petugasTim,
    required this.hariKe,
    required this.tanggal,
    required this.status,
    required this.jumlahDidata,
    required this.jumlahSubmit,
    required this.jumlahBelumDidata,
    required this.catatan,
    required this.updatedAt,
    required this.foto,
  });

  factory RevisitLaporan.fromJson(Map<String, dynamic> json) {
    final rawFoto = json['foto'];
    return RevisitLaporan(
      id: _s(json, 'id'),
      kodeSls: _s(json, 'kode_sls'),
      nmKec: _s(json, 'nm_kec'),
      nmDesa: _s(json, 'nm_desa'),
      nmSls: _s(json, 'nm_sls'),
      petugasId: _s(json, 'petugas_id'),
      petugasNama: _s(json, 'petugas_nama'),
      petugasRole: _s(json, 'petugas_role'),
      petugasTim: _s(json, 'petugas_tim'),
      hariKe: _i(json, 'hari_ke'),
      tanggal: DateTime.tryParse(_s(json, 'tanggal')) ?? DateTime.now(),
      status: _s(json, 'status'),
      jumlahDidata: (json['jumlah_dicek'] as num?)?.toInt(),
      jumlahSubmit: _i(json, 'jumlah_submit'),
      jumlahBelumDidata: _i(json, 'jumlah_belum_didata'),
      catatan: _s(json, 'catatan'),
      updatedAt: DateTime.tryParse(_s(json, 'updated_at'))?.toLocal(),
      foto: rawFoto is List
          ? rawFoto
                .whereType<Map>()
                .map((f) => RevisitFoto.fromJson(Map<String, dynamic>.from(f)))
                .toList()
          : const [],
    );
  }

  String get slsLabel => revisitSlsLabel(kodeSls, nmSls);
}

/// Total usaha/keluarga didata dari sekumpulan laporan.
int revisitTotalDidata(Iterable<RevisitLaporan> laporan) =>
    laporan.fold<int>(0, (s, l) => s + (l.jumlahDidata ?? 0));

/// Total usaha/keluarga submit dari sekumpulan laporan.
int revisitTotalSubmit(Iterable<RevisitLaporan> laporan) =>
    laporan.fold<int>(0, (s, l) => s + (l.jumlahSubmit ?? 0));

/// Agregat laporan satu tanggal (untuk grafik progres harian).
class RevisitProgresHari {
  final DateTime tanggal;
  final int jumlahLaporan;
  final int jumlahDidata;
  final int jumlahSubmit;
  final int jumlahPetugas;
  final int jumlahFoto;

  /// Total sisa potensi belum didata (laporan terakhir tiap SLS s.d. tanggal).
  final int sisaBelumDidata;

  const RevisitProgresHari({
    required this.tanggal,
    required this.jumlahLaporan,
    required this.jumlahDidata,
    required this.jumlahSubmit,
    required this.jumlahPetugas,
    required this.jumlahFoto,
    required this.sisaBelumDidata,
  });

  factory RevisitProgresHari.fromJson(Map<String, dynamic> json) {
    return RevisitProgresHari(
      tanggal: DateTime.tryParse(_s(json, 'tanggal')) ?? DateTime(2000),
      jumlahLaporan: _i(json, 'jumlah_laporan') ?? 0,
      jumlahDidata: _i(json, 'jumlah_didata') ?? 0,
      jumlahSubmit: _i(json, 'jumlah_submit') ?? 0,
      jumlahPetugas: _i(json, 'jumlah_petugas') ?? 0,
      jumlahFoto: _i(json, 'jumlah_foto') ?? 0,
      sisaBelumDidata: _i(json, 'sisa_belum_didata') ?? 0,
    );
  }
}

/// Progres kumulatif per "hari ke-" alokasi (bukan per tanggal upload).
class RevisitProgresHariKe {
  final int? hariKe;
  final int jumlahSls;
  final int slsDilapor;
  final int slsSelesai;
  final int totalDidata;
  final int totalSubmit;
  final int sisaBelumDidata;

  const RevisitProgresHariKe({
    required this.hariKe,
    required this.jumlahSls,
    required this.slsDilapor,
    required this.slsSelesai,
    required this.totalDidata,
    required this.totalSubmit,
    required this.sisaBelumDidata,
  });

  factory RevisitProgresHariKe.fromJson(Map<String, dynamic> json) {
    return RevisitProgresHariKe(
      hariKe: _i(json, 'hari_ke'),
      jumlahSls: _i(json, 'jumlah_sls') ?? 0,
      slsDilapor: _i(json, 'sls_dilapor') ?? 0,
      slsSelesai: _i(json, 'sls_selesai') ?? 0,
      totalDidata: _i(json, 'total_didata') ?? 0,
      totalSubmit: _i(json, 'total_submit') ?? 0,
      sisaBelumDidata: _i(json, 'sisa_belum_didata') ?? 0,
    );
  }

  String get label => hariKe == null ? 'Tanpa hari' : 'H$hariKe';

  String get labelPanjang =>
      hariKe == null ? 'Hari belum ditentukan' : 'Hari ke-$hariKe';
}

/// Rekap kumulatif satu petugas revisit (sejak awal, bukan per tanggal).
class RevisitRekapPetugas {
  final String petugasId;
  final String nama;
  final String role;
  final String tim;
  final int jumlahSls;
  final int slsDilapor;
  final int slsSelesai;
  final int totalDidata;
  final int totalSubmit;
  final int sisaBelumDidata;
  final int jumlahLaporan;
  final int jumlahFoto;
  final DateTime? tanggalTerakhir;

  const RevisitRekapPetugas({
    required this.petugasId,
    required this.nama,
    required this.role,
    required this.tim,
    required this.jumlahSls,
    required this.slsDilapor,
    required this.slsSelesai,
    required this.totalDidata,
    required this.totalSubmit,
    required this.sisaBelumDidata,
    required this.jumlahLaporan,
    required this.jumlahFoto,
    required this.tanggalTerakhir,
  });

  factory RevisitRekapPetugas.fromJson(Map<String, dynamic> json) {
    return RevisitRekapPetugas(
      petugasId: _s(json, 'petugas_id'),
      nama: _s(json, 'nama'),
      role: _s(json, 'role'),
      tim: _s(json, 'tim'),
      jumlahSls: _i(json, 'jumlah_sls') ?? 0,
      slsDilapor: _i(json, 'sls_dilapor') ?? 0,
      slsSelesai: _i(json, 'sls_selesai') ?? 0,
      totalDidata: _i(json, 'total_didata') ?? 0,
      totalSubmit: _i(json, 'total_submit') ?? 0,
      sisaBelumDidata: _i(json, 'sisa_belum_didata') ?? 0,
      jumlahLaporan: _i(json, 'jumlah_laporan') ?? 0,
      jumlahFoto: _i(json, 'jumlah_foto') ?? 0,
      tanggalTerakhir: DateTime.tryParse(_s(json, 'tanggal_terakhir')),
    );
  }

  /// Proporsi SLS yang sudah dikunjungi.
  double get persenSls => jumlahSls == 0 ? 0 : slsDilapor / jumlahSls;
}

/// Satu sel matriks rekap: petugas × "hari ke-" alokasi.
class RevisitMatriksSel {
  final String petugasId;
  final int? hariKe;
  final int jumlahSls;
  final int slsDilapor;
  final int slsSelesai;
  final int totalDidata;
  final int totalSubmit;

  const RevisitMatriksSel({
    required this.petugasId,
    required this.hariKe,
    required this.jumlahSls,
    required this.slsDilapor,
    required this.slsSelesai,
    required this.totalDidata,
    required this.totalSubmit,
  });

  factory RevisitMatriksSel.fromJson(Map<String, dynamic> json) {
    return RevisitMatriksSel(
      petugasId: _s(json, 'petugas_id'),
      hariKe: _i(json, 'hari_ke'),
      jumlahSls: _i(json, 'jumlah_sls') ?? 0,
      slsDilapor: _i(json, 'sls_dilapor') ?? 0,
      slsSelesai: _i(json, 'sls_selesai') ?? 0,
      totalDidata: _i(json, 'total_didata') ?? 0,
      totalSubmit: _i(json, 'total_submit') ?? 0,
    );
  }

  bool get lengkap => jumlahSls > 0 && slsDilapor >= jumlahSls;
  bool get belumLapor => jumlahSls > 0 && slsDilapor == 0;
}
