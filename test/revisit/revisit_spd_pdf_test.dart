import 'package:direktori/features/map/data/services/revisit_spd_pdf_service.dart';
import 'package:direktori/features/map/data/services/revisit_translok_excel_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('nama kecamatan tujuan dari kode 7372xxx', () {
    expect(RevisitSpdPdfService.namaTujuan('7372010'), 'Kecamatan Bacukiki');
    expect(
      RevisitSpdPdfService.namaTujuan('7372011'),
      'Kecamatan Bacukiki Barat',
    );
    expect(RevisitSpdPdfService.namaTujuan('7372020'), 'Kecamatan Ujung');
    expect(RevisitSpdPdfService.namaTujuan('7372030'), 'Kecamatan Soreang');
  });

  test('tanggal SPD seperti contoh: 08 Mei 2026', () {
    expect(RevisitSpdPdfService.tanggal('2026-05-08'), '08 Mei 2026');
    expect(
      RevisitSpdPdfService.tanggal(DateTime(2026, 9, 17)),
      '17 September 2026',
    );
  });

  test('PDF terbentuk untuk beberapa SPD', () async {
    const b = RevisitTranslokBaris(
      nama: 'Citra Dewi',
      nip: '7372000000000002',
      tujuanKe: 1,
      asal: '7372011',
      tujuan: '7372030',
      berangkat: '2026-09-17',
      pulang: '2026-09-17',
    );
    final bytes = await RevisitSpdPdfService.buatPdf(
      [b, b, b],
      RevisitSpdPengaturan(
        nomor: '011/429006-92800/TRANSLOK-2902/04/2026',
        ppkNama: 'Ahmad Kamal,S.Tr.Stat.',
        ppkNip: '200004302023021001',
        kepalaNama: 'Dian Ernawaty,SST, M.A.P.',
        kepalaNip: '198503242008012002',
      ),
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(5000));
  });

  test('nomor SPD berurutan dari angka awal, lebar digit tetap', () {
    const awal = '011/429006-92800/TRANSLOK-2902/09/2026';
    expect(RevisitSpdPdfService.nomorKe(awal, 0), awal);
    expect(
      RevisitSpdPdfService.nomorKe(awal, 1),
      '012/429006-92800/TRANSLOK-2902/09/2026',
    );
    expect(
      RevisitSpdPdfService.nomorKe(awal, 989),
      '1000/429006-92800/TRANSLOK-2902/09/2026',
    );
    expect(RevisitSpdPdfService.nomorKe('TANPA-ANGKA', 3), 'TANPA-ANGKA');
  });

  test('SPD 1 halaman lebih kecil dari SPD 2 halaman', () async {
    const b = RevisitTranslokBaris(
      nama: 'Anisa',
      nip: '',
      tujuanKe: 1,
      asal: '7372011',
      tujuan: '7372010',
      berangkat: '2026-07-21',
      pulang: '2026-07-21',
    );
    const p = RevisitSpdPengaturan(
      nomor: '159/429006-92800/TRANSLOK-2902/06/2026',
      ppkNama: 'Ismaya Gusmi,SST',
      ppkNip: '198910212013112001',
      kepalaNama: 'Dian Ernawaty, SST., M.A.P.',
      kepalaNip: '198503242008012002',
    );
    final dua = await RevisitSpdPdfService.buatPdf([b, b], p);
    final satu = await RevisitSpdPdfService.buatPdf(
      [b, b],
      p,
      satuHalaman: true,
    );
    expect(String.fromCharCodes(satu.take(5)), '%PDF-');
    expect(satu.length, lessThan(dua.length));
  });

  test('bulan & tahun nomor mengikuti tanggal perjalanan', () {
    const n = '011/429006-92800/TRANSLOK-2902/04/2026';
    expect(
      RevisitSpdPdfService.nomorBulan(n, '2026-09-17'),
      '011/429006-92800/TRANSLOK-2902/09/2026',
    );
    expect(
      RevisitSpdPdfService.nomorBulan(n, '2026-10-05'),
      '011/429006-92800/TRANSLOK-2902/10/2026',
    );
    expect(
      RevisitSpdPdfService.nomorBulan('TANPA-BULAN', '2026-10-05'),
      'TANPA-BULAN',
    );
  });

  test('nomor dipatahkan setelah TRANSLOK-', () {
    expect(
      RevisitSpdPdfService.barisNomor('004/429006-92800/TRANSLOK-2904/01/2026'),
      ['004/429006-92800/TRANSLOK-', '2904/01/2026'],
    );
    expect(RevisitSpdPdfService.barisNomor('123/ABC'), ['123/ABC']);
  });
}
