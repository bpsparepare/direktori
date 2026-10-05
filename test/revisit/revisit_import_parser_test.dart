import 'package:direktori/features/map/data/models/revisit_models.dart';
import 'package:direktori/features/map/data/services/revisit_import_parser.dart';
import 'package:flutter_test/flutter_test.dart';

RevisitPetugas _p(
  String id,
  String nama, {
  bool tim = false,
  String email = '',
}) => RevisitPetugas(
  petugasId: id,
  nama: nama,
  email: email,
  role: 'pendata',
  isRevisit: tim,
  jumlahSls: 0,
  tim: '',
);

/// [by] = petugas pemilik jadwal, [hari] = hari ke- jadwal tersebut.
RevisitAlokasiItem _s(
  String kode, {
  String nm = 'RT 001',
  String? by,
  int hari = 0,
}) => RevisitAlokasiItem(
  kodeSls: kode,
  nmKec: 'Bacukiki',
  nmDesa: 'Lumpue',
  nmSls: nm,
  pmlNama: '',
  pplNama: '',
  jadwal: by == null
      ? const []
      : [
          RevisitJadwal(
            hariKe: hari,
            petugasId: by,
            nama: 'Petugas Lama',
            tim: '',
          ),
        ],
);

void main() {
  final petugas = [
    _p('a', 'Andi Rahman'),
    _p('b', 'Muhammad Budi Santoso, S.ST'),
    _p('c', 'Citra Lestari', email: 'citra.l@bps.go.id'),
    _p('d', 'Andi Baso'),
  ];
  final sls = [
    _s('7372010001000100'),
    _s('7372010001000200', nm: 'RT 002'),
    _s('7372010001000301', nm: 'RT 003'),
    _s('7372010001000302', nm: 'RT 003', by: 'x'),
  ];
  final parser = RevisitImportParser(petugas: petugas, sls: sls);

  test('tabel dengan baris judul (tempel dari Excel)', () {
    final r = parser.parse(
      'No\tTim\tNama Petugas\tKode Wilayah\tNama SLS\tHari\n'
      '1\t1\tAndi Rahman\t7372010001000100\tRT 001\t2\n'
      '2\t1\tmuh budi santoso\t7372010001000200\tRT 002\t3\n',
    );
    expect(r.usedHeader, isTrue);
    expect(r.rows, hasLength(2));
    expect(r.rows[0].petugas?.petugasId, 'a');
    expect(r.rows[0].hariKe, 2);
    expect(r.rows[0].tim, '1');
    expect(r.rows[0].issues, isEmpty);
    expect(r.rows[1].petugas?.petugasId, 'b');
    expect(r.rows[1].hariKe, 3);
  });

  test('tanpa judul: kode, nama, hari ditebak dari isi sel', () {
    final r = parser.parse('7372010001000100\tCitra Lestari\tRT 001\thari 4');
    final row = r.rows.single;
    expect(row.petugas?.petugasId, 'c');
    expect(row.hariKe, 4);
    expect(row.willApply, isTrue);
  });

  test('teks bebas + kode 14 digit = semua sub-SLS', () {
    final r = parser.parse('1. Andi Rahman 73720100010003 H-5 tim 2');
    final row = r.rows.single;
    expect(row.sls.map((s) => s.kodeSls), [
      '7372010001000301',
      '7372010001000302',
    ]);
    expect(row.hariKe, 5);
    expect(row.tim, '2');
    expect(row.petugas?.petugasId, 'a');
    // Jadwal lama sub-SLS 02 milik petugas lain di hari 0, jadi baris ini
    // hanya menambah jadwal baru.
    expect(row.aksi, RevisitImportAksi.tambah);
    expect(row.hasWarning, isFalse);
    expect(row.willApply, isTrue);
  });

  test('nama ambigu dan kode tidak ada menjadi error', () {
    final r = parser.parse(
      'Andi\t7372010001000100\n'
      'Siapa Saja\t7372019999999999\n',
    );
    expect(r.rows[0].petugas, isNull);
    expect(r.rows[0].hasError, isTrue);
    expect(r.rows[1].hasError, isTrue);
    expect(
      r.rows[1].issues.map((i) => i.message),
      contains('Kode wilayah tidak ditemukan'),
    );
  });

  test('pilih petugas manual menghapus error nama', () {
    final row = parser.parse('Andi\t7372010001000100').rows.single;
    row.petugas = petugas.last;
    row.manual = true;
    expect(row.issues, isEmpty);
  });

  test('baris sama persis (SLS+hari+petugas) ditandai ganda', () {
    final r = parser.parse(
      'Andi Rahman\t7372010001000100\n'
      'Andi Rahman\t7372010001000100\n',
    );
    markRevisitImportDuplicates(r.rows);
    expect(r.rows[0].ditimpaBaris, 2);
    expect(r.rows[1].ditimpaBaris, isNull);
  });

  test('SLS & hari sama tapi petugas beda bukan duplikat', () {
    final r = parser.parse(
      'Andi Rahman\t7372010001000100\n'
      'Citra Lestari\t7372010001000100\n',
    );
    markRevisitImportDuplicates(r.rows);
    expect(r.rows.every((x) => x.ditimpaBaris == null), isTrue);
    expect(r.rows.every((x) => x.willApply), isTrue);
  });

  test('baris tanpa kode diabaikan', () {
    final r = parser.parse(
      'Daftar alokasi revisit\n\nAndi Rahman\t7372010001000100',
    );
    expect(r.rows, hasLength(1));
    expect(r.ignoredLines, 1);
  });

  test('judul "Nama Wilayah" tidak dianggap kolom kode', () {
    final r = parser.parse(
      'Nama Wilayah\tNama Petugas\tKode\n'
      'RT 001\tAndi Rahman\t7372010001000100\n',
    );
    expect(r.usedHeader, isTrue);
    expect(r.rows.single.sls.single.kodeSls, '7372010001000100');
    expect(r.rows.single.petugas?.petugasId, 'a');
  });

  group('email', () {
    test('kolom Email dengan baris judul -> cocok persis', () {
      final r = parser.parse(
        'Email\tKode Wilayah\tHari\n'
        'Citra.L@bps.go.id\t7372010001000100\t2\n',
      );
      final row = r.rows.single;
      expect(r.usedHeader, isTrue);
      expect(row.petugas?.petugasId, 'c');
      expect(row.matchScore, 1);
      expect(row.hariKe, 2);
      expect(row.issues, isEmpty);
    });

    test('tanpa judul dan teks bebas', () {
      final a = parser.parse('7372010001000100\tcitra.l@bps.go.id\th3');
      expect(a.rows.single.petugas?.petugasId, 'c');
      expect(a.rows.single.hariKe, 3);
      final b = parser.parse('citra.l@bps.go.id 7372010001000200 hari 1 tim 4');
      expect(b.rows.single.petugas?.petugasId, 'c');
      expect(b.rows.single.tim, '4');
      expect(b.rows.single.issues, isEmpty);
    });

    test('email tidak terdaftar -> error, atau peringatan bila nama cocok', () {
      final r = parser.parse(
        'Email\tNama\tKode\n'
        'salah@x.id\t\t7372010001000100\n'
        'lain@x.id\tAndi Rahman\t7372010001000200\n',
      );
      expect(r.rows[0].petugas, isNull);
      expect(
        r.rows[0].issues.first.message,
        'Email tidak terdaftar sebagai petugas aktif',
      );
      expect(r.rows[1].petugas?.petugasId, 'a');
      expect(r.rows[1].hasWarning, isTrue);
    });
  });

  test('SLS sama dengan hari berbeda bukan duplikat', () {
    final r = parser.parse(
      'Email\tKode\tHari\n'
      'citra.l@bps.go.id\t7372010001000100\t1\n'
      'citra.l@bps.go.id\t7372010001000100\t3\n',
    );
    markRevisitImportDuplicates(r.rows);
    expect(r.rows.map((x) => x.hariKe), [1, 3]);
    expect(r.rows.every((x) => x.ditimpaBaris == null), isTrue);
    expect(r.rows.every((x) => x.willApply), isTrue);
  });

  test('hari sama dengan petugas lain = tambah, bukan ganti', () {
    final p2 = RevisitImportParser(
      petugas: petugas,
      sls: [_s('7372010001000100', by: 'x', hari: 2)],
    );
    final row = p2.parse('andi@x.id\t7372010001000100\t2').rows.single;
    row.petugas = petugas.first;
    row.manual = true;
    expect(row.aksi, RevisitImportAksi.tambah);
    expect(
      row.issues.any((i) => i.isInfo && i.message.contains('juga dipegang')),
      isTrue,
    );
    expect(row.hasWarning, isFalse);
  });

  test('petugas sudah punya SLS lain di hari itu = tambah', () {
    final p2 = RevisitImportParser(
      petugas: petugas,
      // Citra sudah memegang RT 002 pada hari ke-2.
      sls: [
        _s('7372010001000100'),
        _s('7372010001000200', nm: 'RT 002', by: 'c', hari: 2),
      ],
    );
    final row = p2.parse('citra.l@bps.go.id\t7372010001000100\t2').rows.single;
    expect(row.aksi, RevisitImportAksi.tambah);
    expect(row.hasWarning, isFalse);
  });

  test('jadwal yang sama persis ditandai sudah ada', () {
    final p2 = RevisitImportParser(
      petugas: petugas,
      sls: [_s('7372010001000100', by: 'c', hari: 2)],
    );
    final row = p2.parse('citra.l@bps.go.id\t7372010001000100\t2').rows.single;
    expect(row.aksi, RevisitImportAksi.sudahAda);
  });

  test('petugas & hari sama, SLS beda = keduanya dipakai', () {
    final r = parser.parse(
      'Email\tKode\tHari\n'
      'citra.l@bps.go.id\t7372010001000100\t2\n'
      'citra.l@bps.go.id\t7372010001000200\t2\n',
    );
    markRevisitImportDuplicates(r.rows);
    expect(r.rows.every((x) => x.ditimpaBaris == null), isTrue);
    expect(r.rows.every((x) => x.willApply), isTrue);
  });

  test('SLS, petugas & hari sama di dua baris = baris atas ditimpa', () {
    final r = parser.parse(
      'Email\tKode\tHari\n'
      'citra.l@bps.go.id\t7372010001000100\t2\n'
      'citra.l@bps.go.id\t7372010001000100\t2\n',
    );
    markRevisitImportDuplicates(r.rows);
    expect(r.rows[0].ditimpaBaris, 3);
    expect(r.rows[1].ditimpaBaris, isNull);
  });
}
