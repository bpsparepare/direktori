import '../models/revisit_models.dart';

/// Parser "Impor Cepat" alokasi revisit dari teks tempelan (clipboard).
///
/// Format yang dikenali per baris:
/// - Tabel dari Excel/Sheets (dipisah TAB), `;`, atau `|`. Bila ada baris
///   judul (mis. `Tim | Nama | Kode Wilayah | Hari`) kolom dipetakan dari
///   judul; tanpa judul kolom ditebak dari isinya.
/// - Teks bebas, mis. `Andi Rahman 7372010001000100 hari 2 tim 3`.
///
/// Kode wilayah 16 digit = satu SLS; 14 digit = semua sub-SLS di SLS itu.
/// Petugas dikenali dari EMAIL (dicocokkan persis, disarankan) atau nama
/// (toleran gelar, huruf besar/kecil, singkatan). Hasilnya WAJIB
/// diverifikasi pengguna sebelum disimpan.
class RevisitImportParser {
  final List<RevisitPetugas> petugas;
  final Map<String, RevisitAlokasiItem> _slsByKode;

  RevisitImportParser({
    required this.petugas,
    required List<RevisitAlokasiItem> sls,
  }) : _slsByKode = {for (final s in sls) s.kodeSls: s};

  static final RegExp _email = RegExp(
    r'[A-Za-z0-9._%+\-]+@[A-Za-z0-9\-]+(?:\.[A-Za-z0-9\-]+)+',
  );
  static final RegExp _kodeRun = RegExp(r'\d[\d.\- ]{8,}\d');
  static final RegExp _hariCell = RegExp(
    r'^(?:hari|h)\s*(?:ke)?\s*[-.:]?\s*(\d{1,3})$',
    caseSensitive: false,
  );
  static final RegExp _timCell = RegExp(
    r'^(?:tim|team|kelompok)\s*[-.:]?\s*(\S.*)$',
    caseSensitive: false,
  );
  static final RegExp _hariFree = RegExp(
    r'\b(?:hari|h)\s*(?:ke)?\s*[-.:]?\s*(\d{1,3})\b',
    caseSensitive: false,
  );
  static final RegExp _timFree = RegExp(
    r'\b(?:tim|team|kelompok)\s*[-.:]?\s*([A-Za-z0-9]+)\b',
    caseSensitive: false,
  );

  RevisitImportResult parse(String text) {
    final lines = text
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trimRight())
        .toList();
    final rows = <RevisitImportRowPreview>[];
    var ignored = 0;
    _HeaderMap? header;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.trim().isEmpty) continue;
      final cells = _splitCells(line);

      if (cells != null && header == null && rows.isEmpty) {
        final h = _HeaderMap.tryParse(cells);
        if (h != null) {
          header = h;
          continue;
        }
      }

      final row = cells == null
          ? _parseFree(line, i + 1)
          : _parseCells(cells, line, i + 1, header);
      if (row == null) {
        ignored++;
        continue;
      }
      rows.add(row);
    }

    return RevisitImportResult(
      rows: rows,
      ignoredLines: ignored,
      usedHeader: header != null,
    );
  }

  /// null = bukan tabel (teks bebas).
  List<String>? _splitCells(String line) {
    for (final sep in ['\t', ';', '|']) {
      if (line.contains(sep)) {
        return line.split(sep).map((c) => c.trim()).toList();
      }
    }
    return null;
  }

  RevisitImportRowPreview? _parseCells(
    List<String> cells,
    String raw,
    int lineNo,
    _HeaderMap? header,
  ) {
    String? kode;
    int? hari;
    String? tim;
    String? email;
    final namaKandidat = <String>[];

    if (header != null) {
      String cell(int? idx) =>
          idx != null && idx < cells.length ? cells[idx] : '';
      kode = _digits(cell(header.kode));
      final hariText = cell(header.hari);
      hari =
          int.tryParse(hariText) ??
          int.tryParse(_hariCell.firstMatch(hariText)?.group(1) ?? '');
      final timText = cell(header.tim);
      tim = timText.isEmpty
          ? null
          : (_timCell.firstMatch(timText)?.group(1) ?? timText).trim();
      final nama = cell(header.nama);
      if (nama.isNotEmpty) namaKandidat.add(nama);
      email = _email.firstMatch(cell(header.email))?.group(0);
    } else {
      final angka = <(int, int)>[]; // (indeks kolom, nilai)
      for (var c = 0; c < cells.length; c++) {
        final v = cells[c];
        if (v.isEmpty) continue;
        final e = _email.firstMatch(v);
        if (e != null) {
          email ??= e.group(0);
          continue;
        }
        final digits = _digits(v);
        if (kode == null &&
            digits.length >= 10 &&
            RegExp(r'^[\d.\- ]+$').hasMatch(v)) {
          kode = digits;
          continue;
        }
        final h = _hariCell.firstMatch(v);
        if (h != null) {
          hari ??= int.parse(h.group(1)!);
          continue;
        }
        final t = _timCell.firstMatch(v);
        if (t != null) {
          tim ??= t.group(1)!.trim();
          continue;
        }
        final n = int.tryParse(v);
        if (n != null) {
          angka.add((c, n));
          continue;
        }
        if (RegExp(r'[A-Za-z]').hasMatch(v)) namaKandidat.add(v);
      }
      // Satu angka polos yang bukan di kolom pertama (biasanya nomor urut)
      // dianggap "hari ke-".
      if (hari == null && angka.length == 1 && angka.first.$1 > 0) {
        hari = angka.first.$2;
      }
    }

    if (kode == null || kode.isEmpty) return null;
    return _build(
      lineNo: lineNo,
      raw: raw,
      kode: kode,
      namaKandidat: namaKandidat,
      email: email,
      hari: hari,
      tim: tim,
    );
  }

  RevisitImportRowPreview? _parseFree(String line, int lineNo) {
    final kodeMatch = _kodeRun.firstMatch(line);
    if (kodeMatch == null) return null;
    var rest = line.replaceRange(kodeMatch.start, kodeMatch.end, ' ');

    String? email;
    final e = _email.firstMatch(rest);
    if (e != null) {
      email = e.group(0);
      rest = rest.replaceRange(e.start, e.end, ' ');
    }

    int? hari;
    final h = _hariFree.firstMatch(rest);
    if (h != null) {
      hari = int.parse(h.group(1)!);
      rest = rest.replaceRange(h.start, h.end, ' ');
    }
    String? tim;
    final t = _timFree.firstMatch(rest);
    if (t != null) {
      tim = t.group(1);
      rest = rest.replaceRange(t.start, t.end, ' ');
    }
    // Buang nomor urut di depan ("1.", "12)") dan pemisah sisa.
    final nama = rest
        .replaceFirst(RegExp(r'^\s*\d+[.)]?\s+'), ' ')
        .replaceAll(RegExp(r'[,\-:]+\s*$'), '')
        .replaceAll(RegExp(r'^\s*[,\-:]+'), '')
        .trim();

    return _build(
      lineNo: lineNo,
      raw: line,
      kode: _digits(kodeMatch.group(0)!),
      namaKandidat: nama.isEmpty ? const [] : [nama],
      email: email,
      hari: hari,
      tim: tim,
    );
  }

  RevisitImportRowPreview _build({
    required int lineNo,
    required String raw,
    required String kode,
    required List<String> namaKandidat,
    required String? email,
    required int? hari,
    required String? tim,
  }) {
    final sls = _resolveSls(kode);
    final timBersih = (tim == null || tim.trim().isEmpty) ? null : tim.trim();

    // Email: cocok persis (tanpa beda huruf besar/kecil) -> pasti.
    if (email != null) {
      final e = email.toLowerCase();
      final byEmail = petugas.where((p) => p.email.toLowerCase() == e).toList();
      if (byEmail.length == 1) {
        return RevisitImportRowPreview(
          parser: this,
          lineNo: lineNo,
          raw: raw,
          kodeInput: kode,
          sls: sls,
          namaInput: email,
          emailInput: email,
          hariKe: hari,
          tim: timBersih,
          petugas: byEmail.single,
          matchScore: 1,
          ambiguous: false,
          kandidat: byEmail,
        );
      }
    }

    // Pilih sel nama dengan kecocokan terbaik (tabel tanpa judul bisa punya
    // beberapa kolom teks, mis. nama SLS dan nama petugas).
    var namaInput = namaKandidat.isEmpty ? '' : namaKandidat.first;
    var best = const _Match.none();
    for (final n in namaKandidat) {
      final m = _matchPetugas(n);
      if (m.score > best.score) {
        best = m;
        namaInput = n;
      }
    }

    // Email tidak terdaftar: tetap coba dari nama (bila ada) atau dari
    // bagian sebelum "@", tapi selalu ditandai untuk dicek.
    if (email != null && namaKandidat.isEmpty) {
      namaInput = email;
      best = _matchPetugas(
        email.split('@').first.replaceAll(RegExp(r'[._\d]+'), ' '),
      );
    }

    return RevisitImportRowPreview(
      parser: this,
      lineNo: lineNo,
      raw: raw,
      kodeInput: kode,
      sls: sls,
      namaInput: namaInput,
      emailInput: email,
      hariKe: hari,
      tim: timBersih,
      petugas: best.ambiguous || best.score < _minMirip ? null : best.petugas,
      matchScore: best.score,
      ambiguous: best.ambiguous,
      kandidat: best.kandidat,
    );
  }

  List<RevisitAlokasiItem> _resolveSls(String kode) {
    if (kode.length == 16) {
      final s = _slsByKode[kode];
      return s == null ? const [] : [s];
    }
    if (kode.length == 14) {
      return _slsByKode.values.where((s) => s.kodeSls.startsWith(kode)).toList()
        ..sort((a, b) => a.kodeSls.compareTo(b.kodeSls));
    }
    return const [];
  }

  // ── Pencocokan nama ────────────────────────────────────────────────────────

  static const double _minYakin = 0.9;
  static const double _minMirip = 0.5;

  _Match _matchPetugas(String input) {
    final q = normalizeNama(input);
    if (q.isEmpty) return const _Match.none();

    final scored = <(RevisitPetugas, double)>[];
    for (final p in petugas) {
      final emailName = p.email
          .split('@')
          .first
          .replaceAll(RegExp(r'[._\d]+'), ' ');
      final score = [
        namaScore(q, normalizeNama(p.nama)),
        namaScore(q, normalizeNama(emailName)),
      ].reduce((a, b) => a > b ? a : b);
      if (score > 0) scored.add((p, score));
    }
    if (scored.isEmpty) return const _Match.none();

    // Skor tertinggi dulu; bila sama, utamakan yang sudah masuk tim revisit.
    scored.sort((a, b) {
      final c = b.$2.compareTo(a.$2);
      if (c != 0) return c;
      if (a.$1.isRevisit != b.$1.isRevisit) return a.$1.isRevisit ? -1 : 1;
      return a.$1.nama.compareTo(b.$1.nama);
    });

    final top = scored.first;
    final ambiguous =
        scored.length > 1 &&
        scored[1].$2 >= top.$2 &&
        scored[1].$1.isRevisit == top.$1.isRevisit;
    return _Match(
      petugas: top.$1,
      score: top.$2,
      ambiguous: ambiguous,
      kandidat: [for (final s in scored.take(5)) s.$1],
    );
  }

  /// Huruf kecil, tanpa gelar di belakang koma, tanpa tanda baca.
  static String normalizeNama(String s) {
    var t = s.toLowerCase();
    final koma = t.indexOf(',');
    if (koma > 0) t = t.substring(0, koma);
    t = t.replaceAll(RegExp(r'[^a-z\s]'), ' ');
    return t.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// 1.0 = sama persis; 0.9 = semua kata nama pendek ada di nama panjang
  /// (termasuk singkatan ≥3 huruf, mis. "muh" ~ "muhammad"); selain itu
  /// proporsi kata yang cocok.
  static double namaScore(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0;
    if (a == b) return 1;
    final ta = a.split(' ');
    final tb = b.split(' ');
    final shorter = ta.length <= tb.length ? ta : tb;
    final longer = ta.length <= tb.length ? tb : ta;

    final used = <int>{};
    var cocok = 0;
    for (final w in shorter) {
      for (var j = 0; j < longer.length; j++) {
        if (used.contains(j)) continue;
        final v = longer[j];
        final sama =
            w == v ||
            (w.length >= 3 && v.startsWith(w)) ||
            (v.length >= 3 && w.startsWith(v));
        if (sama) {
          used.add(j);
          cocok++;
          break;
        }
      }
    }
    if (cocok == 0) return 0;
    final panjangCukup = shorter.any((w) => w.length >= 3);
    if (cocok == shorter.length && panjangCukup) return _minYakin;
    return cocok / (ta.length + tb.length - cocok);
  }

  static String _digits(String s) => s.replaceAll(RegExp(r'\D'), '');
}

class _HeaderMap {
  final int? kode;
  final int? nama;
  final int? email;
  final int? hari;
  final int? tim;

  const _HeaderMap({this.kode, this.nama, this.email, this.hari, this.tim});

  /// Baris judul: tanpa kode angka panjang dan memuat kolom kode + nama.
  static _HeaderMap? tryParse(List<String> cells) {
    if (cells.any((c) => RegExp(r'\d{10,}').hasMatch(c))) return null;
    int? cari(bool Function(String) cocok, {Set<int?> kecuali = const {}}) {
      for (var i = 0; i < cells.length; i++) {
        if (kecuali.contains(i)) continue;
        if (cocok(cells[i].toLowerCase())) return i;
      }
      return null;
    }

    // Judul spesifik diutamakan, judul umum hanya cadangan, agar mis.
    // "Nama Wilayah" tidak terbaca sebagai kolom kode maupun nama petugas.
    final kode =
        cari(
          (c) =>
              c.contains('kode') || c.contains('idsls') || c.contains('id sls'),
        ) ??
        cari((c) => c.contains('wilayah') && !c.contains('nama'));
    final email = cari(
      (c) => c.contains('email') || c.contains('e-mail') || c.contains('surel'),
      kecuali: {kode},
    );
    final nama =
        cari(
          (c) => c.contains('petugas') || c.contains('pencacah'),
          kecuali: {kode, email},
        ) ??
        cari(
          (c) =>
              c.contains('nama') &&
              !RegExp(r'sls|desa|kel|kec|wilayah|usaha|tim').hasMatch(c),
          kecuali: {kode, email},
        );
    final hari = cari((c) => c.contains('hari'), kecuali: {kode, nama, email});
    final tim = cari(
      (c) =>
          RegExp(r'\btim\b|team|kelompok').hasMatch(c) &&
          !c.contains('petugas'),
      kecuali: {kode, nama, email, hari},
    );
    if (kode == null || (nama == null && email == null)) return null;
    return _HeaderMap(
      kode: kode,
      nama: nama,
      email: email,
      hari: hari,
      tim: tim,
    );
  }
}

class _Match {
  final RevisitPetugas? petugas;
  final double score;
  final bool ambiguous;
  final List<RevisitPetugas> kandidat;

  const _Match({
    required this.petugas,
    required this.score,
    required this.ambiguous,
    required this.kandidat,
  });

  const _Match.none()
    : petugas = null,
      score = 0,
      ambiguous = false,
      kandidat = const [];
}

class RevisitImportResult {
  final List<RevisitImportRowPreview> rows;
  final int ignoredLines;
  final bool usedHeader;

  const RevisitImportResult({
    required this.rows,
    required this.ignoredLines,
    required this.usedHeader,
  });
}

class RevisitImportIssue {
  final bool isError;
  final String message;

  /// Keterangan biasa (bukan masalah), mis. "menambah jadwal hari baru".
  final bool isInfo;

  const RevisitImportIssue.error(this.message) : isError = true, isInfo = false;
  const RevisitImportIssue.warning(this.message)
    : isError = false,
      isInfo = false;
  const RevisitImportIssue.info(this.message) : isError = false, isInfo = true;
}

/// Satu baris hasil tempel + hasil pencocokan. [petugas] bisa diganti
/// pengguna saat verifikasi.
/// Apa yang akan terjadi bila baris ini disimpan.
enum RevisitImportAksi {
  /// Jadwal baru.
  tambah,

  /// Jadwal yang sama persis sudah ada.
  sudahAda,
}

class RevisitImportRowPreview {
  final RevisitImportParser parser;
  final int lineNo;
  final String raw;
  final String kodeInput;
  final List<RevisitAlokasiItem> sls;
  final String namaInput;

  /// Email yang ditulis (null bila baris memakai nama).
  final String? emailInput;
  final int? hariKe;
  final String? tim;
  final double matchScore;
  final bool ambiguous;
  final List<RevisitPetugas> kandidat;

  RevisitPetugas? petugas;

  /// true bila pengguna memilih petugas secara manual.
  bool manual = false;

  /// Baris lain (lebih bawah) menimpa kode yang sama.
  int? ditimpaBaris;

  RevisitImportRowPreview({
    required this.parser,
    required this.lineNo,
    required this.raw,
    required this.kodeInput,
    required this.sls,
    required this.namaInput,
    this.emailInput,
    required this.hariKe,
    required this.tim,
    required this.petugas,
    required this.matchScore,
    required this.ambiguous,
    required this.kandidat,
  });

  RevisitImportAksi get aksi {
    final p = petugas;
    if (p == null) return RevisitImportAksi.tambah;
    final hari = hariKe ?? 0;
    final sudah = sls.every(
      (s) => s.jadwalHari(hari).any((j) => j.petugasId == p.petugasId),
    );
    if (sls.isNotEmpty && sudah) return RevisitImportAksi.sudahAda;
    return RevisitImportAksi.tambah;
  }

  List<RevisitImportIssue> get issues {
    final out = <RevisitImportIssue>[];
    if (sls.isEmpty) {
      out.add(
        RevisitImportIssue.error(
          kodeInput.length == 16 || kodeInput.length == 14
              ? 'Kode wilayah tidak ditemukan'
              : 'Kode harus 16 digit (SLS) atau 14 digit',
        ),
      );
    }
    final emailCocok =
        emailInput != null &&
        petugas != null &&
        petugas!.email.toLowerCase() == emailInput!.toLowerCase();
    if (emailInput != null && !emailCocok && !manual) {
      out.add(
        petugas == null
            ? const RevisitImportIssue.error(
                'Email tidak terdaftar sebagai petugas aktif',
              )
            : const RevisitImportIssue.warning(
                'Email tidak terdaftar; dicocokkan dari nama, cek kembali',
              ),
      );
    } else if (petugas == null) {
      out.add(
        RevisitImportIssue.error(
          namaInput.isEmpty
              ? 'Email / nama petugas kosong'
              : ambiguous
              ? 'Nama cocok ke beberapa petugas, pilih salah satu'
              : 'Nama tidak ditemukan',
        ),
      );
    } else if (!manual &&
        !emailCocok &&
        matchScore < RevisitImportParser._minYakin) {
      out.add(RevisitImportIssue.warning('Nama hanya mirip, cek kembali'));
    }
    if (hariKe != null && (hariKe! < 1 || hariKe! > 366)) {
      out.add(const RevisitImportIssue.error('Hari ke- tidak valid'));
    }
    if (ditimpaBaris != null) {
      out.add(
        RevisitImportIssue.warning(
          'SLS, petugas & hari sama dengan baris $ditimpaBaris '
          '(yang dipakai baris itu)',
        ),
      );
    }
    final p = petugas;
    if (p != null) {
      final hari = hariKe ?? 0;
      switch (aksi) {
        case RevisitImportAksi.sudahAda:
          out.add(const RevisitImportIssue.info('Jadwal ini sudah ada'));
        case RevisitImportAksi.tambah:
          final rekan = <String>{};
          for (final s in sls) {
            for (final j in s.jadwalHari(hari)) {
              if (j.petugasId != p.petugasId) {
                rekan.add(j.nama.isEmpty ? 'petugas lain' : j.nama);
              }
            }
          }
          if (rekan.isNotEmpty) {
            out.add(
              RevisitImportIssue.info(
                'Hari ini juga dipegang ${rekan.join(', ')}',
              ),
            );
          }
      }
    }
    return out;
  }

  bool get hasError => issues.any((i) => i.isError);
  bool get hasWarning =>
      !hasError && issues.any((i) => !i.isError && !i.isInfo);

  /// Akan dikirim ke server. Baris dengan kode ganda tetap dikirim; server
  /// memakai baris terakhir untuk tiap kode.
  bool get willApply => !hasError;
}

/// Tandai baris yang akan ditimpa baris di bawahnya, mengikuti aturan
/// server: kunci dedup = (SLS, petugas, hari). Satu petugas boleh punya
/// beberapa SLS pada hari yang sama.
void markRevisitImportDuplicates(List<RevisitImportRowPreview> rows) {
  final terakhir = <String, RevisitImportRowPreview>{};
  for (final r in rows) {
    r.ditimpaBaris = null;
  }
  for (final r in rows.reversed) {
    if (r.sls.isEmpty) continue;
    for (final s in r.sls) {
      final pid = r.petugas?.petugasId ?? '-';
      final hari = r.hariKe ?? 0;
      final kunci = '${s.kodeSls}|$pid|$hari';
      final later = terakhir[kunci];
      if (later != null && later != r) {
        r.ditimpaBaris = later.lineNo;
      }
      terakhir.putIfAbsent(kunci, () => r);
    }
  }
}
