import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../models/revisit_models.dart';

/// Foto yang sudah siap ditanam ke dokumen (JPEG + ukuran piksel).
class RevisitDocxFoto {
  final Uint8List jpg;
  final int width;
  final int height;

  const RevisitDocxFoto({
    required this.jpg,
    required this.width,
    required this.height,
  });
}

/// Satu laporan perjalanan dinas = satu petugas pada satu hari ke-
/// (semua SLS hari itu digabung).
class RevisitLaporanHalaman {
  final String petugasNama;

  /// Hari ke- jadwal revisit; 0 bila laporan tidak terikat hari.
  final int hariKe;

  /// Tanggal pelaksanaan menurut jadwal hari ke- (bukan tanggal input).
  final DateTime tanggal;
  final List<RevisitLaporan> laporan;

  const RevisitLaporanHalaman({
    required this.petugasNama,
    required this.hariKe,
    required this.tanggal,
    required this.laporan,
  });
}

/// Penanda tangan "Mengetahui" di bagian Legalitas.
class RevisitPejabatMengetahui {
  final String nama;
  final String jabatan;
  final String nip;

  const RevisitPejabatMengetahui({
    required this.nama,
    required this.jabatan,
    this.nip = '',
  });
}

/// Penyusun berkas DOCX "Laporan Perjalanan Dinas" untuk revisit SE2026.
///
/// Ukuran (kertas, margin, lebar kolom, tinggi baris, spasi, huruf) disalin
/// dari contoh laporan SKGB. DOCX dipilih karena impor HTML ke Google Docs
/// tidak mengenal jeda halaman, sedangkan konversi DOCX mempertahankan
/// `w:br w:type="page"` sehingga tiap laporan mulai di halaman baru.
class RevisitLaporanDocx {
  static const List<String> _bulan = [
    'Januari',
    'Februari',
    'Maret',
    'April',
    'Mei',
    'Juni',
    'Juli',
    'Agustus',
    'September',
    'Oktober',
    'November',
    'Desember',
  ];

  static const String kegiatan =
      'Penyediaan dan Pengembangan Statistik Distribusi (2902)';
  static const String tujuan = 'Revisit Sensus Ekonomi 2026';
  static const String program =
      'Program Penyediaan dan Pelayanan Informasi Statistik (054.01.GG)';
  static const String komponen =
      'Dukungan Penyelenggaraan Tugas dan Fungsi Unit (005)';
  static const String kota = 'Kota Parepare';

  // Satuan Word: twip (1/20 pt) untuk ukuran, EMU (1 pt = 12700) untuk gambar.
  static const int _emuPerPt = 12700;

  /// Lebar foto dokumentasi = lebar foto di contoh (383,4 px ≈ 287,5 pt).
  static const double _lebarFotoPt = 287.5;

  /// Lebar tiap foto bila dua foto berdampingan (isi sel ±490 pt).
  static const double _lebarFotoBerdampingPt = 236;

  /// Hari ke- terakhir dalam jadwal revisit.
  static const int hariKeTerakhir = 18;

  /// Tanggal pelaksanaan untuk hari ke- [hariKe]:
  /// hari 1–14 = 17–30 September 2026, hari 15–18 = 5–8 Oktober 2026.
  /// `null` bila di luar jadwal.
  static DateTime? tanggalHariKe(int hariKe) {
    if (hariKe >= 1 && hariKe <= 14) return DateTime(2026, 9, 16 + hariKe);
    if (hariKe >= 15 && hariKe <= hariKeTerakhir) {
      return DateTime(2026, 10, hariKe - 10);
    }
    return null;
  }

  /// Kelompokkan laporan per petugas per hari ke- (SLS-nya digabung), urut
  /// hari lalu nama. Laporan tanpa hari ke- yang dikenal jatuh ke tanggal
  /// inputnya.
  static List<RevisitLaporanHalaman> kelompokkan(List<RevisitLaporan> laporan) {
    final grup = <String, List<RevisitLaporan>>{};
    for (final l in laporan) {
      final hari = l.hariKe ?? 0;
      final kunci = tanggalHariKe(hari) != null
          ? 'h$hari|${l.petugasId}'
          : 't${revisitDateParam(l.tanggal)}|${l.petugasId}';
      grup.putIfAbsent(kunci, () => []).add(l);
    }
    final halaman =
        grup.values.map((isi) {
          isi.sort((a, b) => a.kodeSls.compareTo(b.kodeSls));
          final hari = isi.first.hariKe ?? 0;
          final jadwal = tanggalHariKe(hari);
          return RevisitLaporanHalaman(
            petugasNama: isi.first.petugasNama,
            hariKe: jadwal == null ? 0 : hari,
            tanggal: jadwal ?? isi.first.tanggal,
            laporan: isi,
          );
        }).toList()..sort((a, b) {
          final t = revisitDateParam(
            a.tanggal,
          ).compareTo(revisitDateParam(b.tanggal));
          if (t != 0) return t;
          return a.petugasNama.compareTo(b.petugasNama);
        });
    return halaman;
  }

  /// Berkas DOCX lengkap. [foto] dikunci dengan `driveFileId`; foto yang
  /// tidak ada di map ditulis sebagai keterangan teks. [pejabat] (dikunci id
  /// laporan) mengisi Nama/Jabatan di bagian C; yang kosong jadi titik-titik.
  static Uint8List build({
    required List<RevisitLaporanHalaman> halaman,
    required Map<String, RevisitDocxFoto> foto,
    required RevisitPejabatMengetahui mengetahui,
    Map<String, RevisitPejabat> pejabat = const {},
  }) {
    final media = <_Media>[];
    final docXml = _documentXml(halaman, foto, mengetahui, pejabat, media);

    final archive = Archive()
      ..add(ArchiveFile.string('[Content_Types].xml', _contentTypes))
      ..add(ArchiveFile.string('_rels/.rels', _rootRels))
      ..add(ArchiveFile.string('word/document.xml', docXml))
      ..add(ArchiveFile.string('word/styles.xml', _styles))
      ..add(
        ArchiveFile.string(
          'word/_rels/document.xml.rels',
          _documentRels(media),
        ),
      );
    for (final m in media) {
      archive.add(ArchiveFile.bytes('word/media/${m.fileName}', m.bytes));
    }
    return ZipEncoder().encodeBytes(archive);
  }

  /// `word/document.xml`. Publik agar susunannya bisa diuji.
  static String documentXml({
    required List<RevisitLaporanHalaman> halaman,
    required Map<String, RevisitDocxFoto> foto,
    required RevisitPejabatMengetahui mengetahui,
    Map<String, RevisitPejabat> pejabat = const {},
  }) => _documentXml(halaman, foto, mengetahui, pejabat, <_Media>[]);

  static String _documentXml(
    List<RevisitLaporanHalaman> halaman,
    Map<String, RevisitDocxFoto> foto,
    RevisitPejabatMengetahui mengetahui,
    Map<String, RevisitPejabat> pejabat,
    List<_Media> daftarMedia,
  ) {
    final b = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write(
        '<w:document '
        'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
        'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">',
      )
      ..write('<w:body>');

    if (halaman.isEmpty) {
      b.write(_p(_run('Tidak ada laporan pada periode ini.')));
    }
    for (var i = 0; i < halaman.length; i++) {
      if (i > 0) b.write('<w:p><w:r><w:br w:type="page"/></w:r></w:p>');
      _laporan(b, halaman[i], foto, mengetahui, pejabat, daftarMedia);
    }

    // A4, margin 43,2 pt (sama dengan contoh).
    b
      ..write(
        '<w:sectPr>'
        '<w:pgSz w:w="11906" w:h="16838"/>'
        '<w:pgMar w:top="864" w:right="864" w:bottom="864" w:left="864" '
        'w:header="0" w:footer="0" w:gutter="0"/>'
        '</w:sectPr>',
      )
      ..write('</w:body></w:document>');
    return b.toString();
  }

  static void _laporan(
    StringBuffer b,
    RevisitLaporanHalaman h,
    Map<String, RevisitDocxFoto> foto,
    RevisitPejabatMengetahui mengetahui,
    Map<String, RevisitPejabat> pejabat,
    List<_Media> media,
  ) {
    final tgl = tanggalTeks(h.tanggal);
    final lokasiHari = lokasi(h.laporan);
    final hari = h.hariKe > 0 ? ' hari ke-${h.hariKe}' : '';

    // Judul (11 pt, tengah, tidak tebal).
    b.write(_p(_run('LAPORAN PERJALANAN DINAS', sz: 22), jc: 'center'));

    // ── Tabel A: Data umum ────────────────────────────────────────────────
    const lebarA = [2122, 2982, 2534, 2530];
    b
      ..write(_tblOpen(lebarA))
      ..write(_tr(432, [_tc(_p(_run('A. DATA UMUM'), jc: 'center'), span: 4)]))
      ..write(
        _tr(998, [
          _tc(_p(_run('1. Nama Pelaksana'))),
          _tc(_p(_run(h.petugasNama))),
          _tc(_p(_run('4. Jadwal Pelaksanaan'))),
          _tc(_p(_run(tgl))),
        ]),
      )
      ..write(
        _tr(1610, [
          _tc(_p(_run('2. Kegiatan'))),
          _tc(_p(_run(kegiatan))),
          _tc(_p(_run('5. Program yang membiayai'))),
          _tc(_p(_run(program))),
        ]),
      )
      ..write(
        _tr(1644, [
          _tc(_p(_run('3. Tujuan'))),
          _tc(_p(_run(tujuan))),
          _tc(_p(_run('6. Komponen'))),
          _tc(_p(_run(komponen))),
        ]),
      )
      ..write('</w:tbl>')
      ..write(_p(''));

    // ── Tabel B–D: Uraian, pejabat & tempat, legalitas ───────────────────
    const lebarB = [5114, 4914];
    b
      ..write(_tblOpen(lebarB))
      ..write(
        _tr(576, [
          _tc(
            _p(_run('B. URAIAN PEKERJAAN (RINGKASAN HASIL)'), jc: 'center'),
            span: 2,
          ),
        ]),
      );

    // 1. Tujuan
    b.write(
      _tr(1472, [
        _tc(
          _p(_run('1.   Tujuan Utama Transport Lokal:'), line: 360) +
              _p(
                _run('Melakukan revisit Sensus Ekonomi 2026$hari'),
                line: 360,
                ind: 318,
              ),
          span: 2,
        ),
      ]),
    );

    // 2. Kegiatan dilaksanakan di …
    b.write(
      _tr(1404, [
        _tc(
          _p(
                _run('2.  Kegiatan dilaksanakan di $lokasiHari, $kota:'),
                line: 360,
                ind: 284,
                hanging: 284,
              ) +
              _p(_run('Tanggal berangkat : $tgl'), line: 360, ind: 330) +
              _p(_run('Tanggal pulang      : $tgl'), line: 360, ind: 330),
          span: 2,
        ),
      ]),
    );

    // 3. Hasil kegiatan (ringkas; jumlah submit ada di Progress).
    final (pembuka, butirHasil) = kalimatHasil(h.laporan);
    final hasil = StringBuffer(
      _p(_run('3.  Hasil Kegiatan:'), line: 360, jc: 'both'),
    )..write(_p(_run(pembuka), line: 360, ind: 284, jc: 'both'));
    for (final butir in butirHasil) {
      hasil.write(_butir(butir));
    }
    b.write(_tr(1710, [_tc(hasil.toString(), span: 2)]));

    // 4. Permasalahan & 5. Rekomendasi: disusun dari status dan angka tiap
    // SLS (catatan petugas tetap masuk ke Hasil Kegiatan).
    b.write(
      _tr(1418, [
        _tc(
          _p(_run('4. Permasalahan yang Ditemui'), line: 360) +
              permasalahan(h.laporan).map(_butir).join(),
          span: 2,
          vAlign: 'top',
        ),
      ]),
    );

    // 6. Progress: jumlah yang sudah disubmit ke FASIH pada hari itu.
    final submit = h.laporan.fold<int>(0, (s, l) => s + submitDianggap(l));
    b
      ..write(
        _tr(984, [
          _tc(
            _p(_run('5.  Rekomendasi yang Disampaikan:'), line: 360) +
                rekomendasi(h.laporan).map(_butir).join(),
            span: 2,
          ),
        ]),
      )
      ..write(
        _tr(1134, [
          _tc(
            _p(_run('6.    Progress Kegiatan:'), line: 360) +
                _p(
                  _run(
                    'Progress revisit Sensus Ekonomi 2026$hari ($tgl) telah '
                    'disubmit ke aplikasi FASIH sebanyak $submit '
                    'usaha/keluarga.',
                  ),
                  line: 360,
                  ind: 426,
                  jc: 'both',
                ),
            span: 2,
          ),
        ]),
      );

    // 7. Dokumentasi: foto tertanam, dua foto per baris.
    final dok = StringBuffer(_p(_run('7.    Dokumentasi'), line: 360));
    final siap = <(_Media, RevisitDocxFoto)>[];
    final gagal = <String>[];
    for (final l in h.laporan) {
      for (final f in l.foto) {
        final data = foto[f.driveFileId];
        if (data == null) {
          gagal.add(f.namaFile);
          continue;
        }
        final m = _Media(
          id: 'rIdImg${media.length + 1}',
          fileName: 'foto${media.length + 1}.jpg',
          bytes: data.jpg,
        );
        media.add(m);
        siap.add((m, data));
      }
    }
    // Satu foto saja: selebar contoh; lebih dari satu: dua per baris.
    final lebar = siap.length == 1 ? _lebarFotoPt : _lebarFotoBerdampingPt;
    for (var i = 0; i < siap.length; i += 2) {
      final baris = siap.skip(i).take(2).toList();
      final runs = <String>[];
      for (var j = 0; j < baris.length; j++) {
        if (j > 0) runs.add(_run('   '));
        final (m, data) = baris[j];
        runs.add(_gambar(m, data, media.indexOf(m) + 1, lebar));
      }
      dok.write(_p(runs.join(), jc: 'center', after: 120));
    }
    for (final nama in gagal) {
      dok.write(_p(_run('(foto $nama tidak dapat dimuat)'), jc: 'center'));
    }
    if (siap.isEmpty && gagal.isEmpty) {
      dok.write(_p(_run('-'), jc: 'center'));
    }
    b
      ..write(_tr(5454, [_tc(dok.toString(), span: 2, vAlign: 'top')]))
      ..write('</w:tbl>');

    // C dan D: tabel tersendiri. Google Docs tidak bisa diminta menjaga
    // beberapa baris tabel tetap satu halaman, jadi sisa ruang halaman
    // diperkirakan; bila C+D tidak muat, keduanya dipindah ke halaman baru
    // supaya Legalitas tidak pernah tampil sendirian.
    final adaNip = mengetahui.nip.trim().isNotEmpty;
    final daftarPejabat = pejabatHalaman(h, pejabat);
    if (!_cdMuat(h, foto, daftarPejabat.length)) {
      b.write('<w:p><w:r><w:br w:type="page"/></w:r></w:p>');
    }
    b
      ..write(_tblOpen(lebarB))
      // C. Pejabat dan tempat yang dikunjungi
      ..write(
        _tr(576, satuHalaman: true, [
          _tc(
            _p(
              _run('C. PEJABAT DAN TEMPAT YANG DIKUNJUNGI'),
              line: 360,
              jc: 'center',
              keepNext: true,
            ),
            span: 2,
          ),
        ]),
      )
      // Pejabat yang ditemui (dari form petugas; kosong = titik-titik
      // untuk diisi tangan).
      ..write(
        _tr(_tinggiBarisC, satuHalaman: true, [
          _tc(
            daftarPejabat.isEmpty
                ? _isianVisum('Nama') + _isianVisum('Jabatan')
                : daftarPejabat
                      .map(
                        (p) =>
                            _isianVisum('Nama', p.nama) +
                            _isianVisum('Jabatan', p.jabatan),
                      )
                      .join(),
            span: 2,
            vAlign: 'top',
          ),
        ]),
      )
      // D. Legalitas
      ..write(
        _tr(576, satuHalaman: true, [
          _tc(
            _p(_run('D. LEGALITAS'), line: 276, jc: 'center', keepNext: true),
            span: 2,
          ),
        ]),
      )
      ..write(
        _tr(740, satuHalaman: true, [
          _tc(
            _p(_run('Mengetahui,'), jc: 'center', keepNext: true) +
                _p(_run(mengetahui.jabatan), jc: 'center', keepNext: true),
          ),
          _tc(_p(_run('PELAKSANA TUGAS'), jc: 'center', keepNext: true)),
        ]),
      )
      // Ruang tanda tangan lega (±85 pt); nama rata bawah.
      ..write(
        _tr(_tinggiTtd, satuHalaman: true, [
          _tc(
            _p(_run(mengetahui.nama, underline: true), jc: 'center') +
                (adaNip
                    ? _p(_run('NIP. ${mengetahui.nip.trim()}'), jc: 'center')
                    : ''),
            vAlign: 'bottom',
          ),
          _tc(
            _p(_run(h.petugasNama, underline: true), jc: 'center') +
                (adaNip ? _p('', jc: 'center') : ''),
            vAlign: 'bottom',
          ),
        ]),
      )
      ..write('</w:tbl>');
  }

  /// Kalimat Hasil Kegiatan: satu SLS = satu kalimat; beberapa SLS = kalimat
  /// pembuka + satu butir ringkas per SLS. Catatan laporan petugas ikut
  /// disambung di belakang kalimat SLS-nya. Jumlah submit sengaja tidak
  /// ditulis karena sudah ada di Progress Kegiatan.
  static (String, List<String>) kalimatHasil(List<RevisitLaporan> laporan) {
    String status(RevisitLaporan l) =>
        RevisitStatus.of(l.status)?.label ?? l.status;
    if (laporan.length == 1) {
      final l = laporan.single;
      return (
        'Telah dilaksanakan revisit Sensus Ekonomi 2026 di ${_satuLokasi(l)} '
            'pada ${l.slsLabel} dengan status ${status(l)}: usaha/keluarga '
            'didata ${l.jumlahDidata ?? 0} dan sisa belum didata '
            '${l.jumlahBelumDidata ?? 0}.${_catatanSambung(l.catatan)}'
            ' ${kalimatPenyisiran(l.penyisiran)}',
        const <String>[],
      );
    }
    return (
      'Telah dilaksanakan revisit Sensus Ekonomi 2026 pada '
          '${laporan.length} SLS:',
      [
        for (final l in laporan)
          '${l.slsLabel} (Kelurahan ${hurufJudul(l.nmDesa)}): ${status(l)}, '
              'didata '
              '${l.jumlahDidata ?? 0}, sisa belum didata '
              '${l.jumlahBelumDidata ?? 0}.${_catatanSambung(l.catatan)}'
              ' ${kalimatPenyisiran(l.penyisiran)}',
      ],
    );
  }

  /// Kalimat penyisiran SLS; isian kosong ditulis titik-titik agar bisa
  /// dilengkapi tangan.
  static String kalimatPenyisiran(RevisitPenyisiran p) {
    const titik = '.........';
    final jalan = p.jalan.trim().isEmpty ? titik : hurufJudul(p.jalan.trim());
    final bangunan = p.bangunan == null ? titik : '${p.bangunan}';
    return 'Setelah konfirmasi dengan ketua SLS, dilakukan pola penyisiran '
        'di jalan/perumahan $jalan dengan jumlah bangunan sekitar $bangunan'
        '${p.bangunan == null ? '' : ' bangunan.'}';
  }

  /// Catatan petugas sebagai lanjutan kalimat: baris-barisnya dijadikan
  /// kalimat dan diakhiri titik, mis. "\n11 KK sudah didata" → " 11 KK sudah
  /// didata." Kosong bila tidak ada catatan.
  static String _catatanSambung(String catatan) {
    final kalimat = catatan
        .split('\n')
        .map((s) => hurufKalimat(s.trim()))
        .where((s) => s.isNotEmpty)
        .map((s) => RegExp(r'[.!?]$').hasMatch(s) ? s : '$s.')
        .join(' ');
    return kalimat.isEmpty ? '' : ' $kalimat';
  }

  /// Jumlah disubmit untuk laporan: semua yang sudah didata dianggap sudah
  /// disubmit ke FASIH, jadi minimal sama dengan jumlah didata.
  static int submitDianggap(RevisitLaporan l) {
    final submit = l.jumlahSubmit ?? 0;
    final didata = l.jumlahDidata ?? 0;
    return submit > didata ? submit : didata;
  }

  /// Kelompok kondisi SLS dalam satu laporan hari, urutan tetap.
  static ({
    List<RevisitLaporan> tidakDitemukan,
    List<RevisitLaporan> kunjunganUlang,
    List<RevisitLaporan> belumSelesai,
  })
  _kondisi(List<RevisitLaporan> laporan) => (
    tidakDitemukan: [
      for (final l in laporan)
        if (l.status == 'tidak_ditemukan') l,
    ],
    kunjunganUlang: [
      for (final l in laporan)
        if (l.status == 'kunjungan_ulang') l,
    ],
    belumSelesai: [
      for (final l in laporan)
        if (l.status == 'belum_selesai') l,
    ],
  );

  /// "RT 01", "RT 01 dan RT 02", "RT 01, RT 02, dan RT 03".
  static String _daftarSls(List<RevisitLaporan> laporan) {
    final label = laporan.map((l) => l.slsLabel).toSet().toList();
    if (label.length <= 2) return label.join(' dan ');
    return '${label.take(label.length - 1).join(', ')}, dan ${label.last}';
  }

  static int _sisa(List<RevisitLaporan> laporan) =>
      laporan.fold<int>(0, (s, l) => s + (l.jumlahBelumDidata ?? 0));

  /// Permasalahan sesuai hasil revisit hari itu: status tiap SLS (tidak
  /// ditemukan, kunjungan ulang, belum selesai). Submit tidak dianggap
  /// masalah (lihat [submitDianggap]). Hari tanpa kendala status tetap
  /// diisi temuan lapangan umum (lihat [_temuanUmum]).
  static List<String> permasalahan(List<RevisitLaporan> laporan) {
    final k = _kondisi(laporan);
    final hasil = <String>[];
    if (k.tidakDitemukan.isNotEmpty) {
      final sls = _daftarSls(k.tidakDitemukan);
      final didata = k.tidakDitemukan.fold<int>(
        0,
        (s, l) => s + (l.jumlahDidata ?? 0),
      );
      final sisa = _sisa(k.tidakDitemukan);
      hasil.add(
        didata == 0
            ? 'Usaha/keluarga sasaran revisit di $sls tidak ditemukan di '
                  'lokasi (kemungkinan sudah pindah, tutup, atau alamatnya '
                  'berubah), sehingga belum ada yang berhasil didata.'
            : 'Sebagian usaha/keluarga di $sls tidak ditemukan di lokasi '
                  '(kemungkinan sudah pindah, tutup, atau alamatnya '
                  'berubah)${sisa > 0 ? '; $sisa usaha/keluarga belum dapat '
                            'didata' : ''}.',
      );
    }
    if (k.kunjunganUlang.isNotEmpty) {
      final sisa = _sisa(k.kunjunganUlang);
      hasil.add(
        'Responden di ${_daftarSls(k.kunjunganUlang)} tidak berada di tempat '
        'saat kunjungan sehingga perlu dilakukan kunjungan ulang'
        '${sisa > 0 ? '; $sisa usaha/keluarga belum didata' : ''}.',
      );
    }
    if (k.belumSelesai.isNotEmpty) {
      final sisa = _sisa(k.belumSelesai);
      hasil.add(
        'Pendataan di ${_daftarSls(k.belumSelesai)} belum selesai'
        '${sisa > 0 ? '; masih tersisa $sisa usaha/keluarga yang belum '
                  'didata' : ' pada hari kunjungan'}.',
      );
    }
    if (hasil.isEmpty) {
      final sls = _daftarSls(laporan);
      hasil.addAll(_temuanUmum(laporan).map((t) => t.$1(sls)));
    }
    return hasil;
  }

  /// Temuan lapangan umum (permasalahan, rekomendasi) untuk hari tanpa
  /// kendala dari status SLS, supaya bagian Permasalahan tetap terisi.
  /// Permasalahan menerima daftar SLS hari itu.
  static final List<(String Function(String), String)> _temuan = [
    (
      (sls) =>
          'Beberapa keluarga di $sls sudah pindah dari alamat semula; hal '
          'ini telah dikonfirmasi melalui koordinasi dengan ketua RT '
          'setempat.',
      'Telah berkoordinasi dengan ketua RT terkait keluarga yang sudah '
          'pindah agar daftar sasaran dapat diperbarui.',
    ),
    (
      (sls) =>
          'Terdapat usaha di $sls yang sudah tutup atau tidak beroperasi '
          'lagi; keberadaannya telah dikonfirmasi kepada ketua RT.',
      'Telah berkoordinasi dengan ketua RT terkait usaha yang tidak '
          'ditemukan atau sudah tutup, dan hasilnya dilaporkan kepada '
          'pengawas.',
    ),
    (
      (sls) =>
          'Sebagian responden di $sls sulit ditemui pada jam kerja sehingga '
          'waktu kunjungan perlu disesuaikan.',
      'Menyesuaikan waktu kunjungan dengan keberadaan responden, misalnya '
          'sore hari atau akhir pekan.',
    ),
    (
      (sls) =>
          'Alamat sebagian usaha di $sls pada daftar berbeda dengan kondisi '
          'di lapangan sehingga lokasinya perlu dipastikan bersama ketua RT.',
      'Memastikan lokasi usaha bersama ketua RT dan mencatat alamat terbaru '
          'saat pendataan.',
    ),
    (
      (sls) =>
          'Beberapa responden di $sls awalnya ragu memberikan keterangan, '
          'namun bersedia setelah dijelaskan tujuan Sensus Ekonomi 2026.',
      'Menyampaikan penjelasan singkat tentang tujuan dan kerahasiaan data '
          'Sensus Ekonomi 2026 sejak awal kunjungan.',
    ),
    (
      (sls) =>
          'Beberapa bangunan yang tercatat sebagai tempat usaha di $sls sudah '
          'beralih fungsi menjadi tempat tinggal.',
      'Telah berkoordinasi dengan ketua RT untuk memastikan bangunan yang '
          'beralih fungsi tidak lagi menjadi sasaran pendataan usaha.',
    ),
  ];

  /// Jumlah SLS dalam sehari yang dianggap banyak: temuan umum jadi dua.
  static const int _slsBanyak = 3;

  /// Temuan umum untuk satu laporan hari: satu, atau dua (berbeda) bila
  /// harinya banyak SLS. Pilihannya tetap untuk laporan yang sama (dibuat
  /// ulang hasilnya sama), tetapi berbeda antarpetugas dan antarhari agar
  /// laporan tidak seragam.
  static List<(String Function(String), String)> _temuanUmum(
    List<RevisitLaporan> laporan,
  ) {
    var kunci = 0;
    for (final l in laporan) {
      for (final c in '${l.petugasId}|${l.hariKe}|${l.kodeSls}'.codeUnits) {
        kunci = (kunci * 31 + c) & 0x7fffffff;
      }
    }
    final n = _temuan.length;
    final pertama = kunci % n;
    final kedua = (pertama + 1 + (kunci ~/ n) % (n - 1)) % n;
    final jumlahSls = laporan.map((l) => l.kodeSls).toSet().length;
    return [_temuan[pertama], if (jumlahSls >= _slsBanyak) _temuan[kedua]];
  }

  /// Baris C (twip): Nama & Jabatan pejabat yang ditemui (±50 pt).
  static const int _tinggiBarisC = 1000;

  /// Isian "Label : isi" untuk pejabat yang memberi visum; kosong =
  /// titik-titik. Titik dua sejajar lewat tab stop.
  static String _isianVisum(String label, [String isi = '']) => _p(
    '${_run(label)}<w:r><w:tab/></w:r>'
    '${_run(isi.trim().isEmpty ? ': ..........................................................' : ': ${isi.trim()}')}',
    line: 360,
    keepNext: true,
    tabStop: 1000,
  );

  /// Pejabat yang menandatangani bagian C pada satu laporan hari: cukup
  /// satu orang, yaitu yang pertama terisi menurut urutan SLS. Kosong bila
  /// belum ada yang diisi (bagian C jadi titik-titik).
  static List<RevisitPejabat> pejabatHalaman(
    RevisitLaporanHalaman h,
    Map<String, RevisitPejabat> pejabat,
  ) => [
    for (final l in h.laporan)
      if (pejabat[l.id] case final p? when !p.kosong) p,
  ].take(1).toList();

  /// Tinggi baris tanda tangan (twip): ±85 pt ruang untuk paraf/tanda tangan.
  static const int _tinggiTtd = 1700;

  /// Rekomendasi yang menjawab tiap [permasalahan], urutan sama.
  static List<String> rekomendasi(List<RevisitLaporan> laporan) {
    final k = _kondisi(laporan);
    final hasil = <String>[
      if (k.tidakDitemukan.isNotEmpty)
        'Telah berkoordinasi dengan ketua RT terkait usaha/keluarga yang '
            'tidak ditemukan di ${_daftarSls(k.tidakDitemukan)}; yang sudah '
            'pindah atau tutup dilaporkan kepada pengawas.',
      if (k.kunjunganUlang.isNotEmpty)
        'Menjadwalkan kunjungan ulang ke ${_daftarSls(k.kunjunganUlang)} '
            'pada waktu responden kemungkinan berada di tempat, serta meminta '
            'kontak responden melalui ketua RT/RW.',
      if (k.belumSelesai.isNotEmpty)
        'Melanjutkan pendataan usaha/keluarga yang tersisa di '
            '${_daftarSls(k.belumSelesai)} pada kunjungan berikutnya.',
    ];
    if (hasil.isEmpty) {
      // Pasangan dari temuan umum yang sama dengan bagian Permasalahan.
      hasil.addAll(_temuanUmum(laporan).map((t) => t.$2));
    }
    return hasil;
  }

  // ── Perkiraan tata letak halaman ────────────────────────────────────────
  //
  // Angka sengaja dilebihkan: salah perkiraan hanya menyisakan ruang kosong
  // di bawah halaman, bukan memisahkan C dan D.

  /// Tinggi isi halaman A4 dikurangi margin atas-bawah 43,2 pt.
  static const double _tinggiHalamanPt = 841.9 - 2 * 43.2;
  static const double _baris10 = 15.5; // Calibri 12 pt, spasi 1,0
  static const double _baris15 = 22.5; // spasi 1,5
  static const double _lebarHurufPt =
      5.6; // rata-rata Calibri 12 pt, dilebihkan
  static const double _isiSelBPt = 501.3 - 10.8; // lebar isi sel tabel B
  static const double _cadanganPt = 30;

  /// Jumlah baris teks dengan lebar [lebarPt] (per baris baru dihitung sendiri).
  static int _jumlahBaris(String teks, double lebarPt) {
    final perBaris = (lebarPt / _lebarHurufPt).floor().clamp(1, 1000);
    return teks
        .split('\n')
        .fold<int>(
          0,
          (n, s) => n + (s.length / perBaris).ceil().clamp(1, 1000),
        );
  }

  /// Apakah tabel C+D masih muat di halaman tempat B berakhir.
  static bool _cdMuat(
    RevisitLaporanHalaman h,
    Map<String, RevisitDocxFoto> foto,
    int jumlahPejabat,
  ) {
    final barisPejabat = (jumlahPejabat < 1 ? 1 : jumlahPejabat) * 2;
    final tinggiCd =
        28.8 +
        [
          _tinggiBarisC / 20,
          barisPejabat * _baris15 + 1,
        ].reduce((a, b) => a > b ? a : b) +
        28.8 +
        37 +
        _tinggiTtd / 20 +
        6;
    return perkiraanAwalC(h, foto) + tinggiCd + _cadanganPt <= _tinggiHalamanPt;
  }

  /// Perkiraan posisi atas tabel C (pt dari atas isi halaman).
  @visibleForTesting
  static double perkiraanAwalC(
    RevisitLaporanHalaman h,
    Map<String, RevisitDocxFoto> foto,
  ) {
    final hari = h.hariKe > 0 ? ' hari ke-${h.hariKe}' : '';
    final tgl = tanggalTeks(h.tanggal);
    final hal = _PosisiHalaman(_tinggiHalamanPt);
    double teks(String s, double lebar, double baris) =>
        _jumlahBaris(s, lebar) * baris;
    // Baris satu sel: isi bertumpuk ke bawah, per baris teks / foto.
    void baris(double minimum, List<double> blok) {
      var isi = 1.0; // garis tabel
      for (final t in blok) {
        hal.blok(t);
        isi += t;
      }
      if (isi < minimum) hal.ruang(minimum - isi);
    }

    // Baris beberapa sel berdampingan: tinggi = sel tertinggi.
    void barisBerdampingan(double minimum, List<double> sel) {
      final tertinggi = sel.fold<double>(0, (a, b) => a > b ? a : b) + 1;
      hal.ruang(tertinggi > minimum ? tertinggi : minimum);
    }

    // Judul, tabel A, paragraf jarak.
    hal.blok(_baris10);
    baris(21.6, [_baris10]);
    barisBerdampingan(49.9, [teks(h.petugasNama, 138, _baris10)]);
    barisBerdampingan(80.5, [
      teks(kegiatan, 138, _baris10),
      teks(program, 116, _baris10),
    ]);
    barisBerdampingan(82.2, [
      teks(tujuan, 138, _baris10),
      teks(komponen, 116, _baris10),
    ]);
    hal.blok(_baris10);

    // Tabel B.
    baris(28.8, [_baris10]);
    baris(73.6, [
      _baris15,
      teks(
        'Melakukan revisit Sensus Ekonomi 2026$hari',
        _isiSelBPt - 16,
        _baris15,
      ),
    ]);
    baris(70.2, [
      teks(
        '2.  Kegiatan dilaksanakan di ${lokasi(h.laporan)}, $kota:',
        _isiSelBPt - 14,
        _baris15,
      ),
      _baris15 * 2,
    ]);
    final (pembuka, butirHasil) = kalimatHasil(h.laporan);
    baris(85.5, [
      _baris15,
      teks(pembuka, _isiSelBPt - 14, _baris15),
      for (final butir in butirHasil)
        teks('•  $butir', _isiSelBPt - 43, _baris15),
    ]);
    baris(70.9, [
      _baris15,
      for (final m in permasalahan(h.laporan))
        teks('•  $m', _isiSelBPt - 43, _baris15),
    ]);
    baris(49.2, [
      _baris15,
      for (final r in rekomendasi(h.laporan))
        teks('•  $r', _isiSelBPt - 43, _baris15),
    ]);
    baris(56.7, [
      _baris15,
      teks(
        'Progress revisit Sensus Ekonomi 2026$hari ($tgl) telah disubmit ke '
        'aplikasi FASIH sebanyak 0000 usaha/keluarga.',
        _isiSelBPt - 22,
        _baris15,
      ),
    ]);

    // Dokumentasi: tiap baris foto tidak bisa terbelah.
    final siap = [
      for (final l in h.laporan)
        for (final f in l.foto)
          if (foto[f.driveFileId] != null) foto[f.driveFileId]!,
    ];
    final gagal = h.laporan.expand((l) => l.foto).length - siap.length;
    final lebar = siap.length == 1 ? _lebarFotoPt : _lebarFotoBerdampingPt;
    baris(272.7, [
      _baris15,
      for (var i = 0; i < siap.length; i += 2)
        siap
                .skip(i)
                .take(2)
                .map((f) => f.width == 0 ? lebar : lebar * f.height / f.width)
                .reduce((a, b) => a > b ? a : b) +
            8,
      for (var i = 0; i < gagal; i++) _baris10,
      if (siap.isEmpty && gagal == 0) _baris10,
    ]);

    return hal.y;
  }

  // ── Potongan XML ─────────────────────────────────────────────────────────

  /// Tabel bergaris 1 pt, sel padding kiri-kanan 5,4 pt, geser −5,4 pt
  /// (persis contoh).
  static String _tblOpen(List<int> grid) {
    final total = grid.fold<int>(0, (s, w) => s + w);
    return '<w:tbl><w:tblPr>'
        '<w:tblW w:w="$total" w:type="dxa"/>'
        '<w:tblInd w:w="-108" w:type="dxa"/>'
        '<w:tblBorders>'
        '<w:top w:val="single" w:sz="8" w:space="0" w:color="000000"/>'
        '<w:left w:val="single" w:sz="8" w:space="0" w:color="000000"/>'
        '<w:bottom w:val="single" w:sz="8" w:space="0" w:color="000000"/>'
        '<w:right w:val="single" w:sz="8" w:space="0" w:color="000000"/>'
        '<w:insideH w:val="single" w:sz="8" w:space="0" w:color="000000"/>'
        '<w:insideV w:val="single" w:sz="8" w:space="0" w:color="000000"/>'
        '</w:tblBorders>'
        '<w:tblLayout w:type="fixed"/>'
        '<w:tblCellMar>'
        '<w:top w:w="0" w:type="dxa"/><w:left w:w="108" w:type="dxa"/>'
        '<w:bottom w:w="0" w:type="dxa"/><w:right w:w="108" w:type="dxa"/>'
        '</w:tblCellMar>'
        '</w:tblPr>'
        '<w:tblGrid>${grid.map((w) => '<w:gridCol w:w="$w"/>').join()}</w:tblGrid>';
  }

  /// Baris dengan tinggi minimum [tinggi] twip (kelegaan seperti contoh).
  /// [satuHalaman]: baris tidak boleh terpotong ke halaman berikutnya.
  static String _tr(int tinggi, List<String> sel, {bool satuHalaman = false}) =>
      '<w:tr><w:trPr>'
      '${satuHalaman ? '<w:cantSplit/>' : ''}'
      '<w:trHeight w:val="$tinggi" w:hRule="atLeast"/></w:trPr>'
      '${sel.join()}</w:tr>';

  static String _tc(String isi, {int span = 1, String vAlign = 'center'}) =>
      '<w:tc><w:tcPr>'
      '${span > 1 ? '<w:gridSpan w:val="$span"/>' : ''}'
      '<w:vAlign w:val="$vAlign"/>'
      '</w:tcPr>${isi.isEmpty ? _p('') : isi}</w:tc>';

  /// Paragraf. [line] = spasi baris dalam 240-an (240 = 1,0; 360 = 1,5).
  static String _p(
    String runs, {
    String jc = 'left',
    int line = 240,
    int ind = 0,
    int hanging = 0,
    int after = 0,
    bool keepNext = false,
    int? tabStop,
  }) {
    final indXml = ind > 0 || hanging > 0
        ? '<w:ind w:left="$ind"${hanging > 0 ? ' w:hanging="$hanging"' : ''}/>'
        : '';
    return '<w:p><w:pPr>'
        '${keepNext ? '<w:keepNext/><w:keepLines/>' : ''}'
        '${tabStop == null ? '' : '<w:tabs><w:tab w:val="left" w:pos="$tabStop"/></w:tabs>'}'
        '<w:spacing w:before="0" w:after="$after" w:line="$line" w:lineRule="auto"/>'
        '$indXml<w:jc w:val="$jc"/>'
        '</w:pPr>$runs</w:p>';
  }

  /// Butir daftar (seperti bullet di contoh: menjorok 42,5 pt).
  static String _butir(String teks) =>
      _p(_run('•  $teks'), line: 360, ind: 850, hanging: 213);

  /// Teks Calibri; [sz] dalam setengah-pt (24 = 12 pt).
  static String _run(String teks, {int sz = 24, bool underline = false}) =>
      '<w:r><w:rPr>'
      '<w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:cs="Calibri"/>'
      '${underline ? '<w:u w:val="single"/>' : ''}'
      '<w:sz w:val="$sz"/><w:szCs w:val="$sz"/>'
      '</w:rPr><w:t xml:space="preserve">${_e(teks)}</w:t></w:r>';

  static String _gambar(
    _Media m,
    RevisitDocxFoto f,
    int nomor,
    double lebarPt,
  ) {
    final cx = (lebarPt * _emuPerPt).round();
    final cy = f.width == 0 ? cx : (cx * f.height / f.width).round();
    return '<w:r><w:drawing>'
        '<wp:inline distT="0" distB="0" distL="0" distR="0">'
        '<wp:extent cx="$cx" cy="$cy"/>'
        '<wp:docPr id="$nomor" name="Foto $nomor"/>'
        '<a:graphic><a:graphicData '
        'uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<pic:pic><pic:nvPicPr><pic:cNvPr id="$nomor" name="${m.fileName}"/>'
        '<pic:cNvPicPr/></pic:nvPicPr>'
        '<pic:blipFill><a:blip r:embed="${m.id}"/>'
        '<a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
        '<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="$cx" cy="$cy"/>'
        '</a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>'
        '</pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r>';
  }

  // ── Teks ─────────────────────────────────────────────────────────────────

  static String _satuLokasi(RevisitLaporan l) =>
      'Kelurahan ${hurufJudul(l.nmDesa)}, Kecamatan ${hurufJudul(l.nmKec)}';

  /// Singkatan yang tetap kapital saat teks kapital semua dirapikan.
  static const Set<String> _singkatan = {
    'rt',
    'rw',
    'kk',
    'sls',
    'btn',
    'bps',
    'pt',
    'cv',
    'ud',
    'umkm',
    'nik',
    'ktp',
    'sd',
    'smp',
    'sma',
    'smk',
    'tk',
    'pns',
    'tni',
    'polri',
    'bumn',
    'pln',
    'pdam',
    'spbu',
    'atm',
    'cctv',
    'se',
    'fasih',
    'ppl',
    'pml',
    'ii',
    'iii',
    'iv',
  };

  /// "BACUKIKI BARAT" → "Bacukiki Barat". Teks yang tidak kapital semua
  /// dibiarkan.
  static String hurufJudul(String teks) {
    if (!_kapitalSemua(teks)) return teks;
    return teks.toLowerCase().replaceAllMapped(
      RegExp(r"[a-z][a-z']*"),
      (m) => _singkatan.contains(m[0])
          ? m[0]!.toUpperCase()
          : '${m[0]![0].toUpperCase()}${m[0]!.substring(1)}',
    );
  }

  /// true bila hurufnya (minimal 4) hampir semua kapital.
  static bool _kapitalSemua(String teks) {
    final huruf = teks.replaceAll(RegExp(r'[^A-Za-z]'), '');
    if (huruf.length < 4) return false;
    final besar = huruf.replaceAll(RegExp(r'[^A-Z]'), '').length;
    return besar / huruf.length >= 0.8;
  }

  /// Kalimat yang diketik kapital semua dijadikan huruf kalimat biasa:
  /// huruf kecil, awal kalimat kapital, singkatan umum (RT, RW, BTN, …) tetap
  /// kapital. Titik yang menempel ke kata berikutnya diberi spasi. Kalimat
  /// yang tidak kapital semua dibiarkan.
  static String hurufKalimat(String teks) {
    // Rapikan per kalimat supaya kalimat yang sudah benar tidak tersentuh.
    final rapi = teks.replaceAllMapped(
      RegExp(r'([A-Za-z]{3,})\.([A-Za-z]{3,})'),
      (m) => _kapitalSemua('${m[1]}${m[2]}') ? '${m[1]}. ${m[2]}' : m[0]!,
    );
    final kalimat = RegExp(r'[^.!?]+[.!?]*\s*').allMatches(rapi);
    return kalimat.map((m) {
      final k = m[0]!;
      if (!_kapitalSemua(k)) return k;
      var kecil = k.toLowerCase().replaceAllMapped(
        RegExp(r'[a-z]+'),
        (w) => _singkatan.contains(w[0]) ? w[0]!.toUpperCase() : w[0]!,
      );
      // Awal kalimat kapital (huruf pertama saja, bukan angka/singkatan).
      kecil = kecil.replaceFirstMapped(
        RegExp(r'^([^A-Za-z]*)([a-z])'),
        (c) => '${c[1]}${c[2]!.toUpperCase()}',
      );
      return kecil;
    }).join();
  }

  /// Lokasi unik hari itu, mis. "Kelurahan A, Kecamatan B dan Kelurahan C,
  /// Kecamatan D".
  static String lokasi(List<RevisitLaporan> laporan) =>
      laporan.map(_satuLokasi).toSet().join(' dan ');

  static String tanggalTeks(DateTime d) =>
      '${d.day} ${_bulan[d.month - 1]} ${d.year}';

  static String _e(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  // ── Bagian paket DOCX ────────────────────────────────────────────────────

  static const String _contentTypes =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" '
      'ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Default Extension="jpg" ContentType="image/jpeg"/>'
      '<Override PartName="/word/document.xml" ContentType="application/'
      'vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
      '<Override PartName="/word/styles.xml" ContentType="application/'
      'vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
      '</Types>';

  static const String _rootRels =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/'
      'officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
      '</Relationships>';

  /// Huruf bawaan Calibri 11 pt tanpa spasi antarparagraf.
  static const String _styles =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      '<w:docDefaults><w:rPrDefault><w:rPr>'
      '<w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:cs="Calibri" w:eastAsia="Calibri"/>'
      '<w:sz w:val="22"/><w:szCs w:val="22"/><w:lang w:val="id-ID"/>'
      '</w:rPr></w:rPrDefault>'
      '<w:pPrDefault><w:pPr>'
      '<w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="auto"/>'
      '</w:pPr></w:pPrDefault></w:docDefaults>'
      '<w:style w:type="paragraph" w:default="1" w:styleId="Normal">'
      '<w:name w:val="Normal"/></w:style>'
      '</w:styles>';

  static String _documentRels(List<_Media> media) =>
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rIdStyles" Type="http://schemas.openxmlformats.org/'
      'officeDocument/2006/relationships/styles" Target="styles.xml"/>'
      '${media.map((m) => '<Relationship Id="${m.id}" '
          'Type="http://schemas.openxmlformats.org/officeDocument/2006/'
          'relationships/image" Target="media/${m.fileName}"/>').join()}'
      '</Relationships>';

  /// Lebar & tinggi JPEG dibaca dari header (tanpa decode penuh), atau
  /// `null` bila bukan JPEG yang dikenali.
  static (int, int)? ukuranJpeg(Uint8List b) {
    if (b.length < 4 || b[0] != 0xFF || b[1] != 0xD8) return null;
    var i = 2;
    while (i + 9 < b.length) {
      if (b[i] != 0xFF) return null;
      final marker = b[i + 1];
      if (marker == 0xFF) {
        i++; // byte pengisi
        continue;
      }
      // SOF0–SOF15 kecuali DHT (C4), JPG (C8), DAC (CC) memuat ukuran.
      if (marker >= 0xC0 &&
          marker <= 0xCF &&
          marker != 0xC4 &&
          marker != 0xC8 &&
          marker != 0xCC) {
        final tinggi = (b[i + 5] << 8) | b[i + 6];
        final lebar = (b[i + 7] << 8) | b[i + 8];
        return lebar > 0 && tinggi > 0 ? (lebar, tinggi) : null;
      }
      final panjang = (b[i + 2] << 8) | b[i + 3];
      i += 2 + panjang;
    }
    return null;
  }

  /// Jumlah gambar di dalam DOCX (untuk uji: memastikan foto ikut tertanam).
  static int jumlahMedia(Uint8List docx) {
    final arsip = ZipDecoder().decodeBytes(docx);
    return arsip.files.where((f) => f.name.startsWith('word/media/')).length;
  }

  /// Isi `word/document.xml` dari berkas DOCX (untuk uji).
  static String bacaDocumentXml(Uint8List docx) {
    final arsip = ZipDecoder().decodeBytes(docx);
    final f = arsip.files.firstWhere((f) => f.name == 'word/document.xml');
    return utf8.decode(f.content);
  }
}

class _Media {
  final String id;
  final String fileName;
  final Uint8List bytes;

  const _Media({required this.id, required this.fileName, required this.bytes});
}

/// Posisi vertikal kasar di halaman berjalan (pt dari atas isi halaman).
class _PosisiHalaman {
  final double tinggi;
  double y = 0;

  _PosisiHalaman(this.tinggi);

  /// Blok yang tidak bisa terbelah (satu baris teks atau satu baris foto).
  void blok(double h) {
    if (y + h > tinggi) {
      y = h > tinggi ? h % tinggi : h;
    } else {
      y += h;
    }
  }

  /// Ruang kosong yang boleh terbelah antarhalaman.
  void ruang(double h) {
    y += h;
    while (y > tinggi) {
      y -= tinggi;
    }
  }
}
