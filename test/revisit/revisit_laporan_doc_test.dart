import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:direktori/features/map/data/models/revisit_models.dart';
import 'package:direktori/features/map/data/services/revisit_laporan_doc_service.dart';
import 'package:direktori/features/map/data/services/revisit_laporan_docx.dart';

RevisitLaporan _laporan({
  String petugasId = 'p1',
  String petugas = 'Budi',
  String kodeSls = '7372010001001001',
  String catatan = 'Ada <b>kendala</b>\nBaris dua',
  DateTime? tanggal,
  int hariKe = 2,
  List<String> fotoIds = const ['d1'],
}) {
  return RevisitLaporan.fromJson({
    'id': 'x-$petugasId-$kodeSls',
    'kode_sls': kodeSls,
    'nm_kec': 'Bacukiki Barat',
    'nm_desa': 'Lumpue',
    'nm_sls': 'RT 01',
    'petugas_id': petugasId,
    'petugas_nama': petugas,
    'petugas_role': 'PPL',
    'petugas_tim': 'Tim A',
    'hari_ke': hariKe,
    'tanggal': (tanggal ?? DateTime(2026, 7, 8)).toIso8601String(),
    'status': 'selesai',
    'jumlah_dicek': 10,
    'jumlah_submit': 8,
    'jumlah_belum_didata': 3,
    'catatan': catatan,
    'foto': [
      for (final id in fotoIds)
        {
          'id': 'f-$id',
          'drive_file_id': id,
          'link_file': 'https://example.com/$id',
          'nama_file': '$id.jpg',
        },
    ],
  });
}

const _mengetahui = RevisitPejabatMengetahui(
  nama: 'Dian Ernawaty, S.ST, M.A.P',
  jabatan: 'Kepala BPS Kota Parepare',
  nip: '19850324 200801 2 002',
);

final _foto = RevisitDocxFoto(
  jpg: Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9]),
  width: 400,
  height: 300,
);

void main() {
  test('jadwal hari ke-: 1–14 = 17–30 Sep, 15–18 = 5–8 Okt', () {
    expect(RevisitLaporanDocx.tanggalHariKe(1), DateTime(2026, 9, 17));
    expect(RevisitLaporanDocx.tanggalHariKe(14), DateTime(2026, 9, 30));
    expect(RevisitLaporanDocx.tanggalHariKe(15), DateTime(2026, 10, 5));
    expect(RevisitLaporanDocx.tanggalHariKe(18), DateTime(2026, 10, 8));
    expect(RevisitLaporanDocx.tanggalHariKe(0), isNull);
    expect(RevisitLaporanDocx.tanggalHariKe(19), isNull);
  });

  test('dikelompokkan per petugas per hari ke-, bukan tanggal input', () {
    final halaman = RevisitLaporanDocx.kelompokkan([
      // Hari ke-2 Budi: dua SLS, diinput di tanggal berbeda -> satu laporan.
      _laporan(hariKe: 2, tanggal: DateTime(2026, 10, 1)),
      _laporan(
        hariKe: 2,
        kodeSls: '7372010001002001',
        tanggal: DateTime(2026, 10, 3),
      ),
      _laporan(hariKe: 15, tanggal: DateTime(2026, 10, 9)),
      _laporan(petugasId: 'p2', petugas: 'Sari', hariKe: 2),
    ]);

    expect(
      halaman.map(
        (h) =>
            '${h.hariKe} ${revisitDateParam(h.tanggal)} ${h.petugasNama} ${h.laporan.length}',
      ),
      ['2 2026-09-18 Budi 2', '2 2026-09-18 Sari 1', '15 2026-10-05 Budi 1'],
    );
  });

  test('laporan tanpa hari ke- jatuh ke tanggal inputnya', () {
    final halaman = RevisitLaporanDocx.kelompokkan([
      _laporan(hariKe: 0, tanggal: DateTime(2026, 10, 2)),
    ]);
    expect(halaman.single.hariKe, 0);
    expect(revisitDateParam(halaman.single.tanggal), '2026-10-02');
  });

  test('tiap laporan mulai di halaman baru dan isinya mengikuti contoh', () {
    final halaman = RevisitLaporanDocx.kelompokkan([
      _laporan(),
      _laporan(petugasId: 'p2', petugas: 'Sari', hariKe: 3),
    ]);
    final xml = RevisitLaporanDocx.documentXml(
      halaman: halaman,
      foto: {'d1': _foto},
      mengetahui: _mengetahui,
    );

    // Dua laporan = satu jeda halaman asli di antaranya.
    expect(RegExp('<w:br w:type="page"/>').allMatches(xml).length, 1);
    expect(RegExp('LAPORAN PERJALANAN DINAS').allMatches(xml).length, 2);

    // A. Data umum persis contoh; tanggal dari jadwal hari ke-.
    expect(
      xml,
      contains('Penyediaan dan Pengembangan Statistik Distribusi (2902)'),
    );
    expect(xml, contains('Revisit Sensus Ekonomi 2026'));
    expect(
      xml,
      contains(
        'Program Penyediaan dan Pelayanan Informasi Statistik (054.01.GG)',
      ),
    );
    expect(
      xml,
      contains('Dukungan Penyelenggaraan Tugas dan Fungsi Unit (005)'),
    );
    expect(xml, contains('18 September 2026'));
    expect(xml, contains('19 September 2026'));

    // B. Uraian sesuai format yang diminta.
    expect(xml, contains('Melakukan revisit Sensus Ekonomi 2026 hari ke-2'));
    expect(xml, contains('Melakukan revisit Sensus Ekonomi 2026 hari ke-3'));
    expect(
      xml,
      contains(
        'Kegiatan dilaksanakan di Kelurahan Lumpue, '
        'Kecamatan Bacukiki Barat, Kota Parepare:',
      ),
    );
    expect(xml, contains('Tanggal berangkat : 18 September 2026'));
    expect(xml, contains('Tanggal pulang      : 18 September 2026'));
    expect(xml, isNot(contains('Petugas:')));

    // Catatan petugas disambung ke Hasil Kegiatan, aman dari markup.
    expect(
      xml,
      contains(
        'sisa belum didata 3. Ada &lt;b&gt;kendala&lt;/b&gt;. Baris dua.',
      ),
    );
    // Permasalahan disusun dari hasil SLS (di sini: selesai, submit kurang
    // dari didata tetap dianggap tersubmit -> tidak ada permasalahan).
    final masalah = RevisitLaporanDocx.permasalahan(halaman.first.laporan);
    expect(masalah, isNotEmpty);
    for (final m in masalah) {
      expect(xml, contains('•  $m'));
    }

    // D. Legalitas.
    expect(xml, contains('Kepala BPS Kota Parepare'));
    expect(xml, contains('NIP. 19850324 200801 2 002'));
    expect(xml, contains('PELAKSANA TUGAS'));

    // Tanpa huruf tebal, seperti contoh.
    expect(xml, isNot(contains('<w:b/>')));
  });

  test('foto dua per baris; foto yang gagal dimuat diberi keterangan', () {
    final halaman = RevisitLaporanDocx.kelompokkan([
      _laporan(fotoIds: ['d1', 'd2', 'd3', 'd4']),
    ]);
    final docx = RevisitLaporanDocx.build(
      halaman: halaman,
      // d4 tidak berhasil diunduh
      foto: {'d1': _foto, 'd2': _foto, 'd3': _foto},
      mengetahui: _mengetahui,
    );

    expect(RevisitLaporanDocx.jumlahMedia(docx), 3);
    final xml = RevisitLaporanDocx.bacaDocumentXml(docx);
    final paragrafFoto = RegExp(r'<w:p>(?:(?!</w:p>).)*?<w:drawing>.*?</w:p>')
        .allMatches(xml)
        .map((m) => '<w:drawing>'.allMatches(m.group(0)!).length)
        .toList();
    expect(paragrafFoto, [2, 1]);
    expect(xml, contains('(foto d4.jpg tidak dapat dimuat)'));
    expect(xml, isNot(contains('href')));
  });

  test('progress FASIH, rekomendasi, ruang tanda tangan, C+D menyatu', () {
    final halaman = RevisitLaporanDocx.kelompokkan([
      _laporan(),
      // submit 8 < didata 10: dianggap tersubmit semua, 10 + 10.
      _laporan(kodeSls: '7372010001002001'),
    ]);
    final xml = RevisitLaporanDocx.documentXml(
      halaman: halaman,
      foto: const {},
      mengetahui: _mengetahui,
    );

    expect(
      xml,
      contains(
        'Progress revisit Sensus Ekonomi 2026 hari ke-2 '
        '(18 September 2026) telah disubmit ke aplikasi FASIH sebanyak 20 '
        'usaha/keluarga.',
      ),
    );
    for (final r in RevisitLaporanDocx.rekomendasi(halaman.first.laporan)) {
      expect(xml, contains('•  $r'));
    }

    // C dan D ada di tabel sendiri: semua barisnya tidak boleh terpotong
    // halaman dan saling menempel ke baris berikutnya.
    final cd = xml.substring(xml.indexOf('C. PEJABAT DAN TEMPAT'));
    final tabelCd = xml.substring(
      xml.lastIndexOf('<w:tbl>', xml.indexOf('C. PEJABAT DAN TEMPAT')),
    );
    expect(RegExp('<w:tr>').allMatches(tabelCd).length, 5);
    expect(RegExp('<w:cantSplit/>').allMatches(tabelCd).length, 5);
    expect(cd, contains('D. LEGALITAS'));
    expect(
      tabelCd.indexOf('</w:tbl>'),
      greaterThan(tabelCd.indexOf('PELAKSANA TUGAS')),
    );

    // Baris tanda tangan lebih tinggi dan nama rata bawah.
    expect(xml, contains('<w:trHeight w:val="1700" w:hRule="atLeast"/>'));
    expect(xml, contains('<w:vAlign w:val="bottom"/>'));
  });

  test('ukuran JPEG dibaca dari header tanpa decode', () {
    final g = img.Image(width: 320, height: 200);
    final jpg = img.encodeJpg(g, quality: 70);
    expect(RevisitLaporanDocx.ukuranJpeg(jpg), (320, 200));
    expect(RevisitLaporanDocx.ukuranJpeg(img.encodePng(g)), isNull);
  });

  group('C+D tidak pernah terpisah halaman', () {
    RevisitLaporan uji(int n) => RevisitLaporan.fromJson({
      'id': 'x$n',
      'kode_sls': '7372010001001001',
      'nm_kec': 'SOREANG',
      'nm_desa': 'UJUNG BARU',
      'nm_sls': 'RT 01',
      'petugas_id': 'p$n',
      'petugas_nama': 'Petugas $n',
      'petugas_role': 'PPL',
      'petugas_tim': '',
      'hari_ke': 2,
      'tanggal': '2026-09-18',
      'status': 'selesai',
      'jumlah_dicek': 10,
      'jumlah_submit': 8,
      'jumlah_belum_didata': 3,
      'catatan': List.generate(
        n * 2,
        (i) => 'Catatan baris ${i + 1}',
      ).join('\n'),
      'foto': [
        for (var k = 0; k < 2; k++)
          {
            'id': 'f$k',
            'drive_file_id': 'd$k',
            'link_file': '',
            'nama_file': 'f$k.jpg',
          },
      ],
    });
    final potret = RevisitDocxFoto(jpg: Uint8List(4), width: 300, height: 400);
    final foto = {'d0': potret, 'd1': potret};

    test('perkiraan posisi C cocok dengan hasil Google Docs', () {
      // Posisi atas tabel C (pt) yang diukur dari PDF ekspor Google Docs
      // untuk laporan dengan 0, 2, 4, ... 14 butir catatan dan 2 foto potret.
      // Hanya laporan tanpa catatan yang tata letaknya masih sama dengan saat
      // pengukuran (catatan kini masuk Hasil Kegiatan, bukan Permasalahan).
      // Diukur saat Permasalahan & Rekomendasi masih teks baku (2 + 3 butir,
      // ±7 baris, 393 pt). Laporan uji ini (selesai, 1 SLS) kini hanya berisi
      // 1 temuan + 1 rekomendasi, baris 4 & 5 kembali ke tinggi minimumnya:
      // ±84 pt lebih pendek, jadi acuannya 393 - 84 (dihitung, bukan diukur
      // ulang di Google Docs).
      const asli = [309];
      for (var n = 0; n < asli.length; n++) {
        final y = RevisitLaporanDocx.perkiraanAwalC(
          RevisitLaporanDocx.kelompokkan([uji(n)]).single,
          foto,
        );
        // Boleh sedikit kurang (ditutup cadangan), lebih baik berlebih.
        expect(y, inInclusiveRange(asli[n] - 10, asli[n] + 50), reason: 'n=$n');
      }
    });

    test('C+D pindah ke halaman baru tepat saat tidak muat', () {
      // Laporan dengan k SLS (masing-masing 2 foto potret) makin panjang.
      RevisitLaporanHalaman halaman(int k) => RevisitLaporanDocx.kelompokkan([
        for (var i = 0; i < k; i++)
          _laporan(
            kodeSls: '73720100010${(i + 10).toString()}01',
            catatan: '',
            fotoIds: ['d0', 'd1'],
          ),
      ]).single;
      bool jedaSebelumC(RevisitLaporanHalaman h) {
        final x = RevisitLaporanDocx.documentXml(
          halaman: [h],
          foto: foto,
          mengetahui: _mengetahui,
        );
        final c = x.indexOf('C. PEJABAT DAN TEMPAT');
        final tabelC = x.lastIndexOf('<w:tbl>', c);
        return x
            .substring(0, tabelC)
            .endsWith('<w:p><w:r><w:br w:type="page"/></w:r></w:p>');
      }

      // Tinggi C+D ≈ 236 pt (C: Nama & Jabatan) + cadangan 30 pt;
      // halaman berisi 755,5 pt.
      const batas = 755.5 - 235.6 - 30;
      var adaJeda = false;
      for (var k = 1; k <= 6; k++) {
        final h = halaman(k);
        final y = RevisitLaporanDocx.perkiraanAwalC(h, foto);
        expect(jedaSebelumC(h), y > batas, reason: 'k=$k y=$y');
        adaJeda |= y > batas;
      }
      expect(adaJeda, isTrue);
      // Satu SLS dengan 2 foto pasti muat: tidak membuang halaman.
      expect(jedaSebelumC(halaman(1)), isFalse);
    });
  });

  test('hasil kegiatan ringkas tanpa angka submit', () {
    final satu = RevisitLaporanDocx.kalimatHasil([_laporan()]);
    expect(
      satu.$1,
      'Telah dilaksanakan revisit Sensus Ekonomi 2026 di Kelurahan Lumpue, '
      'Kecamatan Bacukiki Barat pada RT 01 01 dengan status Selesai: '
      'usaha/keluarga didata 10 dan sisa belum didata 3. '
      'Ada <b>kendala</b>. Baris dua. Setelah konfirmasi dengan ketua SLS, '
      'dilakukan pola penyisiran di jalan/perumahan ......... dengan jumlah '
      'bangunan sekitar .........',
    );
    expect(satu.$2, isEmpty);

    final terisi = RevisitLaporanDocx.kalimatHasil([
      _laporan().denganPenyisiran(
        const RevisitPenyisiran(jalan: 'Jl. Mattirotasi', bangunan: 25),
      ),
    ]);
    expect(
      terisi.$1,
      endsWith(
        'Setelah konfirmasi dengan ketua SLS, dilakukan pola penyisiran di '
        'jalan/perumahan Jl. Mattirotasi dengan jumlah bangunan sekitar 25 '
        'bangunan.',
      ),
    );

    final dua = RevisitLaporanDocx.kalimatHasil([
      _laporan(),
      _laporan(kodeSls: '7372010001002001'),
    ]);
    expect(
      dua.$1,
      'Telah dilaksanakan revisit Sensus Ekonomi 2026 pada 2 SLS:',
    );
    expect(dua.$2, hasLength(2));
    expect(
      dua.$2.first,
      'RT 01 01 (Kelurahan Lumpue): Selesai, didata 10, sisa belum didata 3. '
      'Ada <b>kendala</b>. Baris dua. Setelah konfirmasi dengan ketua SLS, '
      'dilakukan pola penyisiran di jalan/perumahan ......... dengan jumlah '
      'bangunan sekitar .........',
    );

    final xml = RevisitLaporanDocx.documentXml(
      halaman: RevisitLaporanDocx.kelompokkan([
        _laporan(),
        _laporan(kodeSls: '7372010001002001'),
      ]),
      foto: const {},
      mengetahui: _mengetahui,
    );
    final hasil = xml.substring(
      xml.indexOf('3.  Hasil Kegiatan:'),
      xml.indexOf('4. Permasalahan'),
    );
    expect(hasil, isNot(contains('submit')));
    expect(hasil, contains('•  RT 01 01 (Kelurahan Lumpue): Selesai'));
  });

  test(
    'semua petugas dipecah: satu dokumen per orang, nama file berisi nama',
    () {
      final per = RevisitLaporanDocService.kelompokPerPetugas([
        _laporan(petugasId: 'p2', petugas: 'Sari'),
        _laporan(petugasId: 'p1', petugas: 'Budi', hariKe: 3),
        _laporan(petugasId: 'p1', petugas: 'Budi', hariKe: 4),
        // Nama kembar dibedakan agar file tidak tertukar.
        _laporan(petugasId: 'abcdef123', petugas: 'Andi'),
        _laporan(petugasId: 'zyxwvu987', petugas: 'Andi'),
      ]);
      expect(per.keys.toList(), [
        'Andi (abcdef)',
        'Andi (zyxwvu)',
        'Budi',
        'Sari',
      ]);
      expect(per['Budi']!.length, 2);
      expect(
        RevisitLaporanDocService.namaDokumen('Budi', 'Hari ke-1 s.d. 14'),
        'Laporan Perjalanan Dinas Revisit - Budi - Hari ke-1 s.d. 14',
      );
    },
  );

  test('bagian C hanya berisi isian Nama & Jabatan pejabat', () {
    final xml = RevisitLaporanDocx.documentXml(
      halaman: RevisitLaporanDocx.kelompokkan([_laporan()]),
      foto: const {},
      mengetahui: _mengetahui,
    );
    final c = xml.substring(
      xml.indexOf('C. PEJABAT DAN TEMPAT'),
      xml.indexOf('D. LEGALITAS'),
    );
    expect(c, isNot(contains('Kota Parepare')));
    expect(c, contains('>Nama<'));
    expect(c, contains('>Jabatan<'));
    expect('<w:tab/>'.allMatches(c).length, 2);
    expect(c, contains('<w:tab w:val="left" w:pos="1000"/>'));
  });

  test('bagian C terisi nama & jabatan pejabat dari form petugas', () {
    String bagianC(
      Map<String, RevisitPejabat> pejabat,
      List<RevisitLaporan> l,
    ) {
      final xml = RevisitLaporanDocx.documentXml(
        halaman: RevisitLaporanDocx.kelompokkan(l),
        foto: const {},
        mengetahui: _mengetahui,
        pejabat: pejabat,
      );
      return xml.substring(
        xml.indexOf('C. PEJABAT DAN TEMPAT'),
        xml.indexOf('D. LEGALITAS'),
      );
    }

    final a = _laporan();
    final b = _laporan(kodeSls: '7372010001002001');
    const lurah = RevisitPejabat(
      nama: 'Hj Yenny, S.E',
      jabatan: 'Lurah Lumpue',
    );
    const rt = RevisitPejabat(nama: 'Baso', jabatan: 'Ketua RT 002');

    // Terisi dari form; pejabat yang sama di dua SLS cukup sekali.
    final satu = bagianC({a.id: lurah, b.id: lurah}, [a, b]);
    expect(satu, contains(': Hj Yenny, S.E'));
    expect(satu, contains(': Lurah Lumpue'));
    expect(': Hj Yenny'.allMatches(satu).length, 1);
    expect(satu, isNot(contains('.....')));

    // Dua pejabat berbeda: cukup satu, yang pertama menurut urutan SLS.
    final dua = bagianC({a.id: lurah, b.id: rt}, [b, a]);
    expect(dua, contains(': Hj Yenny, S.E'));
    expect(dua, isNot(contains('Baso')));
    expect(dua, isNot(contains('Ketua RT 002')));

    // SLS pertama belum diisi: pakai pejabat SLS berikutnya.
    final kedua = bagianC({b.id: rt}, [a, b]);
    expect(kedua, contains(': Baso'));
    expect(kedua, isNot(contains('.....')));

    // Belum diisi: titik-titik untuk diisi tangan.
    expect(bagianC(const {}, [a]), contains(': .....'));
  });

  test('tanpa laporan menampilkan keterangan kosong', () {
    final xml = RevisitLaporanDocx.documentXml(
      halaman: const [],
      foto: const {},
      mengetahui: _mengetahui,
    );
    expect(xml, contains('Tidak ada laporan pada periode ini.'));
  });

  group('permasalahan & rekomendasi mengikuti hasil revisit', () {
    RevisitLaporan l(
      String status, {
      String sls = '7372010001001001',
      String nmSls = 'RT 01',
      int didata = 5,
      int submit = 5,
      int sisa = 0,
    }) => RevisitLaporan.fromJson({
      'id': 'x-$sls',
      'kode_sls': sls,
      'nm_kec': 'Bacukiki Barat',
      'nm_desa': 'Lumpue',
      'nm_sls': nmSls,
      'petugas_id': 'p1',
      'petugas_nama': 'Budi',
      'hari_ke': 2,
      'tanggal': DateTime(2026, 9, 18).toIso8601String(),
      'status': status,
      'jumlah_dicek': didata,
      'jumlah_submit': submit,
      'jumlah_belum_didata': sisa,
      'catatan': '',
      'foto': const [],
    });

    test('hari lancar tetap berisi satu temuan, berpasangan & bervariasi', () {
      final laporan = [l('selesai', didata: 10, submit: 7)];
      final m = RevisitLaporanDocx.permasalahan(laporan);
      final r = RevisitLaporanDocx.rekomendasi(laporan);
      expect(m, hasLength(1));
      expect(r, hasLength(1));
      expect(m.join(), isNot(contains('Tidak terdapat permasalahan')));
      expect(m.join(), isNot(contains('disubmit')));
      expect(m.first, contains(laporan.first.slsLabel));

      // Dibuat ulang: hasilnya sama.
      expect(RevisitLaporanDocx.permasalahan(laporan), m);

      // Antarpetugas/antarSLS hasilnya tidak seragam.
      final variasi = <String>{
        for (var i = 0; i < 12; i++)
          RevisitLaporanDocx.rekomendasi([
            l('selesai', sls: '73720100010${i.toString().padLeft(2, '0')}001'),
          ]).join('|'),
      };
      expect(variasi.length, greaterThan(3));
    });

    test('hari lancar dengan banyak SLS: dua temuan berbeda', () {
      List<String> masalah(int jumlahSls) => RevisitLaporanDocx.permasalahan([
        for (var i = 0; i < jumlahSls; i++)
          l('selesai', sls: '737201000100${i}001', nmSls: 'RT 0$i'),
      ]);
      expect(masalah(2), hasLength(1));
      expect(masalah(3), hasLength(2));
      expect(masalah(3).toSet(), hasLength(2));
    });

    test('tidak ditemukan tanpa hasil', () {
      final laporan = [l('tidak_ditemukan', didata: 0, submit: 0, sisa: 4)];
      final m = RevisitLaporanDocx.permasalahan(laporan);
      expect(m.single, contains('tidak ditemukan di lokasi'));
      expect(m.single, contains('belum ada yang berhasil didata'));
      expect(
        RevisitLaporanDocx.rekomendasi(laporan).single,
        allOf(
          startsWith('Telah berkoordinasi dengan ketua RT'),
          contains('tidak ditemukan'),
        ),
      );
    });

    test('campuran: tiap kondisi satu poin, SLS digabung, urutan tetap', () {
      final laporan = [
        l('kunjungan_ulang', sisa: 2),
        l('belum_selesai', sls: '7372010001002001', nmSls: 'RT 02', sisa: 3),
        l(
          'belum_selesai',
          sls: '7372010001003001',
          nmSls: 'RT 03',
          sisa: 1,
          didata: 6,
          submit: 4,
        ),
        l('selesai', sls: '7372010001004001', nmSls: 'RT 04'),
      ];
      final m = RevisitLaporanDocx.permasalahan(laporan);
      // RT 03: submit 4 < didata 6 tidak dijadikan permasalahan.
      expect(m, hasLength(2));
      expect(m[0], contains('tidak berada di tempat'));
      expect(m[0], contains('2 usaha/keluarga belum didata'));
      expect(m[1], matches(RegExp(r'RT 02.* dan RT 03')));
      expect(m[1], contains('tersisa 4 usaha/keluarga'));
      expect(m.join(), isNot(contains('disubmit')));
      final r = RevisitLaporanDocx.rekomendasi(laporan);
      expect(r, hasLength(2));
      expect(r[0], startsWith('Menjadwalkan kunjungan ulang'));
      expect(r[1], startsWith('Melanjutkan pendataan'));
      expect(r.join(), isNot(contains('submit')));
    });
  });

  test('teks kapital semua dirapikan jadi huruf kalimat', () {
    expect(
      RevisitLaporanDocx.hurufKalimat(
        'MENURUT INFORMASI DARI PAK RW DAN IBU RT SEMUA WARGANYA SUDAH '
        'TERDATA.NAMA YANG ADA DIDAFTAR TIDAK DITEMUKAN. ADA 1 KELUARGA '
        'TIDAK BERSEDIA DIDATA.',
      ),
      'Menurut informasi dari pak RW dan ibu RT semua warganya sudah '
      'terdata. Nama yang ada didaftar tidak ditemukan. Ada 1 keluarga '
      'tidak bersedia didata.',
    );
    // Kalimat biasa tidak diubah; campuran hanya kalimat kapitalnya.
    expect(
      RevisitLaporanDocx.hurufKalimat('Sudah didata Ibu Ani. SEMUA SELESAI.'),
      'Sudah didata Ibu Ani. Semua selesai.',
    );
    expect(
      RevisitLaporanDocx.hurufKalimat('3 KK sudah didata.'),
      '3 KK sudah didata.',
    );
    expect(RevisitLaporanDocx.hurufJudul('BACUKIKI BARAT'), 'Bacukiki Barat');
    expect(RevisitLaporanDocx.hurufJudul('Lumpue'), 'Lumpue');
  });
}
