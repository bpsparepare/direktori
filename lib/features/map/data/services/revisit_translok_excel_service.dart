import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart';

import '../models/revisit_models.dart';
import 'revisit_laporan_docx.dart';
import 'revisit_nik_petugas.dart';

/// Satu baris Excel translok: satu petugas, satu hari, satu kecamatan.
class RevisitTranslokBaris {
  final String nama;
  final String nip;
  final int tujuanKe;
  final String asal;
  final String tujuan;
  final String berangkat;
  final String pulang;

  const RevisitTranslokBaris({
    required this.nama,
    required this.nip,
    required this.tujuanKe,
    required this.asal,
    required this.tujuan,
    required this.berangkat,
    required this.pulang,
  });
}

/// Satu kunjungan terjadwal: petugas, hari ke-, dan SLS yang dikunjungi.
/// Bisa berasal dari alokasi (jadwal) maupun laporan yang diinput.
class RevisitKunjungan {
  final String petugasId;
  final String nama;
  final int hariKe;
  final String kodeSls;
  final String nmKec;

  /// Dipakai bila [hariKe] di luar jadwal (mis. laporan tanpa hari).
  final DateTime? tanggalCadangan;

  const RevisitKunjungan({
    required this.petugasId,
    required this.nama,
    required this.hariKe,
    required this.kodeSls,
    required this.nmKec,
    this.tanggalCadangan,
  });

  factory RevisitKunjungan.dariLaporan(RevisitLaporan l) => RevisitKunjungan(
    petugasId: l.petugasId,
    nama: l.petugasNama,
    hariKe: l.hariKe ?? 0,
    kodeSls: l.kodeSls,
    nmKec: l.nmKec,
    tanggalCadangan: l.tanggal,
  );

  /// Semua jadwal alokasi dalam rentang hari ke- (hari 0 = belum dijadwalkan,
  /// diabaikan), opsional hanya untuk [petugasId].
  static List<RevisitKunjungan> dariAlokasi(
    List<RevisitAlokasiItem> alokasi, {
    required int hariDari,
    required int hariSampai,
    String? petugasId,
  }) => [
    for (final a in alokasi)
      for (final j in a.jadwal)
        if (j.hariKe >= hariDari &&
            j.hariKe <= hariSampai &&
            (petugasId == null || j.petugasId == petugasId))
          RevisitKunjungan(
            petugasId: j.petugasId,
            nama: j.nama,
            hariKe: j.hariKe,
            kodeSls: a.kodeSls,
            nmKec: a.nmKec,
          ),
  ];
}

/// Excel translok revisit: kolom NIP Lama Peserta, Tujuan ke-, Asal, Tujuan,
/// Berangkat, Pulang. Tanggal mengikuti jadwal hari ke- (bukan tanggal
/// input), asal selalu kantor di Bacukiki Barat (011), tujuan = kode
/// kecamatan SLS yang dikunjungi.
class RevisitTranslokExcelService {
  /// Kode kab/kota Parepare, awalan kode Asal & Tujuan.
  static const String kodeKota = '7372';

  /// Kode asal: kantor BPS Kota Parepare di Bacukiki Barat (7372 + 011).
  static const String kodeAsal = '${kodeKota}011';

  static const List<String> header = [
    'NIP Lama Peserta',
    'Tujuan ke-',
    'Asal',
    'Tujuan',
    'Berangkat (yyyy-mm-dd)',
    'Pulang (yyyy-mm-dd)',
    'Nama',
  ];

  static const List<String> headerCek = [
    'Nama',
    'NIK',
    'Jumlah Baris',
    'Keterangan',
  ];

  /// Cadangan bila kode SLS tidak lengkap: kode kecamatan dari namanya.
  static const Map<String, String> _kodeKecamatan = {
    'bacukiki': '010',
    'bacukiki barat': '011',
    'ujung': '020',
    'soreang': '030',
  };

  /// Kode kecamatan 3 digit: digit ke-5–7 kode SLS (7372 **011** …),
  /// atau dari nama kecamatan bila kode tidak lengkap.
  static String kodeKecamatan(String kodeSls, String nmKec) {
    if (kodeSls.length >= 7) return kodeSls.substring(4, 7);
    return _kodeKecamatan[normalisasiNama(nmKec)] ?? '';
  }

  /// Satu baris per petugas per hari per kecamatan; "Tujuan ke-" = nomor
  /// urut baris (1, 2, 3, …). Urut nama petugas, tanggal, lalu kecamatan.
  static List<RevisitTranslokBaris> susunBaris(
    List<RevisitKunjungan> kunjunganList,
  ) {
    // (petugas, tanggal) -> nama petugas & kode kecamatan yang dikunjungi.
    final kunjungan =
        <String, ({String nama, String tanggal, Set<String> kec})>{};
    for (final l in kunjunganList) {
      final jadwal = RevisitLaporanDocx.tanggalHariKe(l.hariKe);
      final tanggalAsli = jadwal ?? l.tanggalCadangan;
      if (tanggalAsli == null) continue;
      final tanggal = revisitDateParam(tanggalAsli);
      final kunci = '${l.petugasId}|$tanggal';
      final k = kunjungan.putIfAbsent(
        kunci,
        () => (nama: l.nama, tanggal: tanggal, kec: <String>{}),
      );
      k.kec.add(kodeKecamatan(l.kodeSls, l.nmKec));
    }

    final urut = kunjungan.values.toList()
      ..sort((a, b) {
        final n = a.nama.toLowerCase().compareTo(b.nama.toLowerCase());
        if (n != 0) return n;
        return a.tanggal.compareTo(b.tanggal);
      });

    final baris = [
      for (final k in urut)
        for (final kec in k.kec.toList()..sort()) (k: k, kec: kec),
    ];
    return [
      for (final (i, b) in baris.indexed)
        RevisitTranslokBaris(
          nama: b.k.nama,
          nip: nikPetugas(b.k.nama),
          tujuanKe: i + 1,
          asal: kodeAsal,
          tujuan: '$kodeKota${b.kec}',
          berangkat: b.k.tanggal,
          pulang: b.k.tanggal,
        ),
    ];
  }

  /// Satu baris per orang per hari: bila seseorang mengunjungi beberapa
  /// kecamatan pada hari yang sama, ambil yang pertama saja (urutan tetap),
  /// lalu "Tujuan ke-" dinomori ulang 1, 2, 3, … Dipakai List Harian & SPD
  /// 1 halaman.
  static List<RevisitTranslokBaris> satuPerHari(
    List<RevisitTranslokBaris> baris,
  ) {
    final dipakai = <String>{};
    final sisa = [
      for (final b in baris)
        if (dipakai.add('${b.nama}|${b.nip}|${b.berangkat}')) b,
    ];
    return [
      for (final (i, b) in sisa.indexed)
        RevisitTranslokBaris(
          nama: b.nama,
          nip: b.nip,
          tujuanKe: i + 1,
          asal: b.asal,
          tujuan: b.tujuan,
          berangkat: b.berangkat,
          pulang: b.pulang,
        ),
    ];
  }

  /// Isi sheet "Cek Petugas": semua nama di daftar NIK beserta jumlah
  /// barisnya (0 = tidak ada di Excel), ditambah petugas di Excel yang NIK-nya
  /// belum terdaftar. Untuk mencari siapa yang belum ada.
  static List<List<String>> cekPetugas(List<RevisitTranslokBaris> baris) {
    final jumlah = <String, int>{};
    final namaAsli = <String, String>{};
    for (final b in baris) {
      final kunci = normalisasiNama(b.nama);
      jumlah[kunci] = (jumlah[kunci] ?? 0) + 1;
      namaAsli[kunci] = b.nama;
    }
    final terdaftar = <String>{};
    final hasil = <List<String>>[];
    for (final (nama, nik) in daftarNikPetugas) {
      final kunci = normalisasiNama(nama);
      terdaftar.add(kunci);
      final n = jumlah[kunci] ?? 0;
      hasil.add([nama, nik, '$n', n == 0 ? 'Tidak ada di Excel' : 'Ada']);
    }
    for (final e in jumlah.entries) {
      if (terdaftar.contains(e.key)) continue;
      hasil.add([namaAsli[e.key]!, '', '${e.value}', 'NIK belum terdaftar']);
    }
    return hasil;
  }

  /// Tulis Excel lalu kembalikan path file. Semua sel teks agar NIK 16 digit
  /// dan kode berawalan nol tidak berubah jadi angka.
  Future<String> exportToFile(
    List<RevisitTranslokBaris> baris, {
    required String periode,
  }) async {
    final workbook = Workbook();
    final sheet = workbook.worksheets[0];
    sheet.name = 'Translok';

    for (var c = 0; c < header.length; c++) {
      final cell = sheet.getRangeByIndex(1, c + 1);
      cell.setText(header[c]);
      cell.cellStyle.bold = true;
    }
    for (var r = 0; r < baris.length; r++) {
      final b = baris[r];
      final nilai = [
        b.nip,
        '${b.tujuanKe}',
        b.asal,
        b.tujuan,
        b.berangkat,
        b.pulang,
        b.nama,
      ];
      for (var c = 0; c < nilai.length; c++) {
        final cell = sheet.getRangeByIndex(r + 2, c + 1);
        cell.numberFormat = '@';
        cell.setText(nilai[c]);
      }
    }
    for (var c = 1; c <= header.length; c++) {
      sheet.getRangeByIndex(1, c).columnWidth = c == 1 || c == 7 ? 30 : 20;
    }

    final cek = workbook.worksheets.addWithName('Cek Petugas');
    final isiCek = [headerCek, ...cekPetugas(baris)];
    for (var r = 0; r < isiCek.length; r++) {
      for (var c = 0; c < isiCek[r].length; c++) {
        final cell = cek.getRangeByIndex(r + 1, c + 1);
        cell.numberFormat = '@';
        cell.setText(isiCek[r][c]);
        if (r == 0) cell.cellStyle.bold = true;
      }
    }
    for (var c = 1; c <= headerCek.length; c++) {
      cek.getRangeByIndex(1, c).columnWidth = c == 1 ? 34 : 20;
    }

    final bytes = workbook.saveAsStream();
    workbook.dispose();

    final dir = await getTemporaryDirectory();
    final aman = periode.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
    final path = '${dir.path}/translok_revisit_$aman.xlsx';
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }
}
