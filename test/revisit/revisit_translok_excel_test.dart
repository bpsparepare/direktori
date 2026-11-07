import 'package:direktori/features/map/data/models/revisit_models.dart';
import 'package:direktori/features/map/data/services/revisit_nik_petugas.dart';
import 'package:direktori/features/map/data/services/revisit_translok_excel_service.dart';
import 'package:flutter_test/flutter_test.dart';

RevisitLaporan _laporan({
  String petugasId = 'p1',
  String petugas = 'Citra Dewi',
  String kodeSls = '7372011001000101',
  String nmKec = 'BACUKIKI BARAT',
  int hariKe = 2,
  DateTime? tanggal,
}) {
  return RevisitLaporan.fromJson({
    'id': 'x-$petugasId-$kodeSls-$hariKe',
    'kode_sls': kodeSls,
    'nm_kec': nmKec,
    'nm_desa': 'LUMPUE',
    'nm_sls': 'RT 001',
    'petugas_id': petugasId,
    'petugas_nama': petugas,
    'petugas_role': 'PPL',
    'petugas_tim': '',
    'hari_ke': hariKe,
    'tanggal': (tanggal ?? DateTime(2026, 10, 9)).toIso8601String(),
    'status': 'selesai',
    'catatan': '',
    'foto': const [],
  });
}

List<RevisitTranslokBaris> _susun(List<RevisitLaporan> laporan) =>
    RevisitTranslokExcelService.susunBaris(
      laporan.map(RevisitKunjungan.dariLaporan).toList(),
    );

void main() {
  // Data contoh (bukan NIK asli; NIK asli hanya ada di env lokal).
  setUpAll(
    () => aturNikPetugas(
      uraiNikPetugas(
        'Budi Santoso|7372000000000001;Citra Dewi|7372000000000002;'
        'Dewi Lestari, S.M|7372000000000003;Eka Putri|7372000000000004;'
        'Fajar S|7372000000000005;rusak tanpa nik',
      ),
    ),
  );

  test('kode kecamatan dari digit ke-5–7 kode SLS, cadangan dari nama', () {
    expect(
      RevisitTranslokExcelService.kodeKecamatan(
        '7372011001000101',
        'BACUKIKI BARAT',
      ),
      '011',
    );
    expect(
      RevisitTranslokExcelService.kodeKecamatan('7372030002000301', 'SOREANG'),
      '030',
    );
    expect(RevisitTranslokExcelService.kodeKecamatan('', 'UJUNG'), '020');
  });

  test('satu baris per orang per hari per kecamatan, tujuan ke- = no urut', () {
    final baris = _susun([
      // Citra Dewi hari ke-2: dua SLS di Bacukiki Barat (satu baris) + satu di
      // Soreang (baris kedua, tujuan ke-2). Tanggal input tidak dipakai.
      _laporan(),
      _laporan(kodeSls: '7372011001000201'),
      _laporan(kodeSls: '7372030002000301', nmKec: 'SOREANG'),
      // Citra Dewi hari ke-15 = 5 Oktober.
      _laporan(hariKe: 15),
      // Petugas lain diurutkan menurut nama.
      _laporan(
        petugasId: 'p2',
        petugas: 'Budi Santoso',
        kodeSls: '7372010001000101',
      ),
    ]);

    expect(
      baris.map(
        (b) =>
            '${b.nama}|${b.nip}|${b.tujuanKe}|${b.asal}|'
            '${b.tujuan}|${b.berangkat}|${b.pulang}',
      ),
      [
        'Budi Santoso|7372000000000001|1|7372011|7372010|2026-09-18|2026-09-18',
        'Citra Dewi|7372000000000002|2|7372011|7372011|2026-09-18|2026-09-18',
        'Citra Dewi|7372000000000002|3|7372011|7372030|2026-09-18|2026-09-18',
        'Citra Dewi|7372000000000002|4|7372011|7372011|2026-10-05|2026-10-05',
      ],
    );
  });

  test('nama dicocokkan ke NIK walau beda huruf besar, spasi, atau gelar', () {
    expect(nikPetugas('DEWI LESTARI,S.M'), '7372000000000003');
    expect(nikPetugas('Dewi Lestari, S.M.'), '7372000000000003');
    expect(nikPetugas('EKA PUTRI '), '7372000000000004');
    expect(nikPetugas('Fajar S.'), '7372000000000005');
    expect(nikPetugas('Nama Tidak Ada'), '');
    expect(nikPetugasRevisit, hasLength(5));
  });

  test('cek petugas: yang belum ada dan yang NIK-nya belum terdaftar', () {
    final baris = _susun([
      _laporan(),
      _laporan(hariKe: 15),
      _laporan(petugasId: 'p9', petugas: 'Petugas Baru'),
    ]);
    final cek = RevisitTranslokExcelService.cekPetugas(baris);

    expect(cek.firstWhere((r) => r[0] == 'Citra Dewi'), [
      'Citra Dewi',
      '7372000000000002',
      '2',
      'Ada',
    ]);
    expect(cek.firstWhere((r) => r[0] == 'Budi Santoso'), [
      'Budi Santoso',
      '7372000000000001',
      '0',
      'Tidak ada di Excel',
    ]);
    expect(cek.last, ['Petugas Baru', '', '1', 'NIK belum terdaftar']);
    expect(cek, hasLength(6));
  });

  test(
    'list harian dari alokasi: rentang hari ke-, filter petugas, hari 0 diabaikan',
    () {
      final alokasi = [
        RevisitAlokasiItem.fromJson({
          'kode_sls': '7372030002000301',
          'nm_kec': 'SOREANG',
          'nm_desa': 'UJUNG BARU',
          'nm_sls': 'RT 001',
          'jadwal': [
            {'hari_ke': 1, 'petugas_id': 'p1', 'nama': 'Citra Dewi'},
            {'hari_ke': 3, 'petugas_id': 'p1', 'nama': 'Citra Dewi'},
            {'hari_ke': 0, 'petugas_id': 'p1', 'nama': 'Citra Dewi'},
            {'hari_ke': 1, 'petugas_id': 'p2', 'nama': 'Budi Santoso'},
          ],
        }),
      ];

      final semua = RevisitKunjungan.dariAlokasi(
        alokasi,
        hariDari: 1,
        hariSampai: 2,
      );
      expect(semua.map((k) => '${k.nama}:${k.hariKe}'), [
        'Citra Dewi:1',
        'Budi Santoso:1',
      ]);

      final hajrah = RevisitKunjungan.dariAlokasi(
        alokasi,
        hariDari: 1,
        hariSampai: 18,
        petugasId: 'p1',
      );
      final baris = RevisitTranslokExcelService.susunBaris(hajrah);
      expect(baris.map((b) => '${b.tujuanKe}|${b.tujuan}|${b.berangkat}'), [
        '1|7372030|2026-09-17',
        '2|7372030|2026-09-19',
      ]);
    },
  );

  test(
    'List Harian & SPD 1 hal: satu baris per orang per hari, no urut ulang',
    () {
      final baris = _susun([
        _laporan(),
        _laporan(kodeSls: '7372030002000301', nmKec: 'SOREANG'),
        _laporan(hariKe: 15),
        _laporan(
          petugasId: 'p2',
          petugas: 'Budi Santoso',
          kodeSls: '7372010001000101',
        ),
      ]);
      expect(baris, hasLength(4));
      final satu = RevisitTranslokExcelService.satuPerHari(baris);
      expect(
        satu.map((b) => '${b.tujuanKe}|${b.nama}|${b.tujuan}|${b.berangkat}'),
        [
          '1|Budi Santoso|7372010|2026-09-18',
          '2|Citra Dewi|7372011|2026-09-18',
          '3|Citra Dewi|7372011|2026-10-05',
        ],
      );
    },
  );
}
