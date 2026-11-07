import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models/revisit_models.dart';
import '../../data/services/revisit_laporan_doc_service.dart';
import '../../data/services/revisit_laporan_docx.dart';
import '../../data/services/revisit_service.dart';
import '../../data/services/revisit_spd_pdf_service.dart';
import '../../data/services/revisit_translok_excel_service.dart';
import 'revisit_cek_pejabat_dialog.dart';

/// Dialog khusus admin: pilih rentang hari ke- & petugas, lalu buat "Laporan
/// Perjalanan Dinas" (satu laporan per petugas per hari ke-, tiap laporan di
/// halaman baru) dari laporan revisit yang sudah diinput.
/// Jenis keluaran dialog: List Harian (Excel translok) atau laporan
/// perjalanan dinas (Google Docs).
enum RevisitKeluaran { listHarian, spd, spd1, laporan }

class RevisitLaporanDocDialog extends StatefulWidget {
  final RevisitKeluaran jenis;

  const RevisitLaporanDocDialog({super.key, required this.jenis});

  @override
  State<RevisitLaporanDocDialog> createState() =>
      _RevisitLaporanDocDialogState();
}

class _RevisitLaporanDocDialogState extends State<RevisitLaporanDocDialog> {
  final RevisitService _service = RevisitService();
  final RevisitLaporanDocService _docService = RevisitLaporanDocService();
  final RevisitTranslokExcelService _excelService =
      RevisitTranslokExcelService();
  final RevisitSpdPdfService _spdService = RevisitSpdPdfService();

  // Isian SPD (diingat di perangkat). Bawaan mengikuti contoh SPD.
  static const Map<String, String> _bawaanSpd = {
    'nomor': '011/429006-92800/TRANSLOK-2902/09/2026',
    'ppk_nama': 'Ismaya Gusmi,SST',
    'ppk_nip': '198910212013112001',
    'kepala_nama': 'Dian Ernawaty, SST., M.A.P.',
    'kepala_nip': '198503242008012002',
  };
  final TextEditingController _spdNomor = TextEditingController(
    text: _bawaanSpd['nomor'],
  );
  final TextEditingController _ppkNama = TextEditingController(
    text: _bawaanSpd['ppk_nama'],
  );
  final TextEditingController _ppkNip = TextEditingController(
    text: _bawaanSpd['ppk_nip'],
  );
  final TextEditingController _kepalaNama = TextEditingController(
    text: _bawaanSpd['kepala_nama'],
  );
  final TextEditingController _kepalaNip = TextEditingController(
    text: _bawaanSpd['kepala_nip'],
  );

  Map<String, TextEditingController> get _isianSpd => {
    'nomor': _spdNomor,
    'ppk_nama': _ppkNama,
    'ppk_nip': _ppkNip,
    'kepala_nama': _kepalaNama,
    'kepala_nip': _kepalaNip,
  };

  Future<void> _muatIsianSpd() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      for (final e in _isianSpd.entries) {
        final v = prefs.getString('revisit_spd_${e.key}');
        if (v != null && v.isNotEmpty) e.value.text = v;
      }
    } catch (_) {}
  }

  Future<void> _simpanIsianSpd() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final e in _isianSpd.entries) {
        await prefs.setString('revisit_spd_${e.key}', e.value.text.trim());
      }
    } catch (_) {}
  }

  // Isian penanda tangan diingat di perangkat agar tidak diketik ulang.
  static const String _kunciNama = 'revisit_laporan_mengetahui_nama';
  static const String _kunciJabatan = 'revisit_laporan_mengetahui_jabatan';
  static const String _kunciNip = 'revisit_laporan_mengetahui_nip';

  final TextEditingController _mengetahuiNama = TextEditingController();
  final TextEditingController _mengetahuiJabatan = TextEditingController(
    text: 'Kepala BPS Kota Parepare',
  );
  final TextEditingController _mengetahuiNip = TextEditingController();

  // Rentang hari ke- jadwal revisit (bukan tanggal input laporan).
  int _hariDari = 1;
  int _hariSampai = RevisitLaporanDocx.hariKeTerakhir;
  List<RevisitPetugas> _petugas = const [];

  /// Batas atas jumlah didata laporan SLS yang diambil (0 = hanya didata 0,
  /// 2 = didata 0–2); `null` = semua laporan.
  int? _maksDidata;

  String get _labelDidata =>
      _maksDidata == 0 ? 'didata 0' : 'didata 0-$_maksDidata';

  /// Petugas yang dipilih (id); kosong = semua petugas tim revisit.
  Set<String> _dipilih = {};

  bool _cocok(String petugasId) =>
      _dipilih.isEmpty || _dipilih.contains(petugasId);

  List<RevisitPetugas> get _tim =>
      _petugas.where((p) => p.isRevisit).toList()
        ..sort((a, b) => a.nama.toLowerCase().compareTo(b.nama.toLowerCase()));

  String get _labelPetugas {
    if (_dipilih.isEmpty) return 'Semua petugas';
    final nama = [
      for (final p in _tim)
        if (_dipilih.contains(p.petugasId)) p.nama,
    ];
    final ringkas = nama.take(3).join(', ');
    return '${_dipilih.length} dipilih: $ringkas'
        '${nama.length > 3 ? ', …' : ''}';
  }

  Future<void> _pilihPetugas() async {
    final sementara = {..._dipilih};
    var cari = '';
    final hasil = await showDialog<Set<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final daftar = _tim
              .where((p) => p.nama.toLowerCase().contains(cari.toLowerCase()))
              .toList();
          return AlertDialog(
            title: const Text('Pilih petugas'),
            content: SizedBox(
              width: 420,
              height: 460,
              child: Column(
                children: [
                  TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_rounded),
                      hintText: 'Cari nama',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => setLocal(() => cari = v),
                  ),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => setLocal(
                          () =>
                              sementara.addAll(daftar.map((p) => p.petugasId)),
                        ),
                        child: const Text('Pilih semua'),
                      ),
                      TextButton(
                        onPressed: () => setLocal(sementara.clear),
                        child: const Text('Kosongkan'),
                      ),
                      const Spacer(),
                      Text(
                        sementara.isEmpty
                            ? 'Semua'
                            : '${sementara.length} dipilih',
                        style: Theme.of(ctx).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final p in daftar)
                          CheckboxListTile(
                            dense: true,
                            value: sementara.contains(p.petugasId),
                            title: Text(p.nama),
                            onChanged: (v) => setLocal(() {
                              if (v == true) {
                                sementara.add(p.petugasId);
                              } else {
                                sementara.remove(p.petugasId);
                              }
                            }),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, sementara),
                child: const Text('Pakai'),
              ),
            ],
          );
        },
      ),
    );
    if (hasil != null) setState(() => _dipilih = hasil);
  }

  bool _busy = false;

  /// Keterangan langkah yang sedang berjalan saat membuat laporan.
  String? _status;

  @override
  void initState() {
    super.initState();
    _muatPetugas();
    _muatPenandaTangan();
    _muatIsianSpd();
  }

  @override
  void dispose() {
    _mengetahuiNama.dispose();
    _mengetahuiJabatan.dispose();
    _mengetahuiNip.dispose();
    for (final c in _isianSpd.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _muatPenandaTangan() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      _mengetahuiNama.text =
          prefs.getString(_kunciNama) ?? _mengetahuiNama.text;
      _mengetahuiJabatan.text =
          prefs.getString(_kunciJabatan) ?? _mengetahuiJabatan.text;
      _mengetahuiNip.text = prefs.getString(_kunciNip) ?? _mengetahuiNip.text;
    } catch (_) {
      // Isian tetap bisa diketik manual.
    }
  }

  Future<void> _simpanPenandaTangan() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kunciNama, _mengetahuiNama.text.trim());
      await prefs.setString(_kunciJabatan, _mengetahuiJabatan.text.trim());
      await prefs.setString(_kunciNip, _mengetahuiNip.text.trim());
    } catch (_) {}
  }

  Future<void> _muatPetugas() async {
    try {
      final daftar = await _service.fetchPetugas();
      if (mounted) setState(() => _petugas = daftar);
    } catch (e) {
      if (mounted) _showSnack('Gagal memuat petugas: $e', error: true);
    }
  }

  bool get _spdMode =>
      widget.jenis == RevisitKeluaran.spd ||
      widget.jenis == RevisitKeluaran.spd1;

  String get _periode => _hariDari == _hariSampai
      ? 'Hari ke-$_hariDari'
      : 'Hari ke-$_hariDari s.d. $_hariSampai';

  /// Periode untuk nama folder/dokumen laporan; ditandai bila hanya didata 0
  /// agar tidak tercampur dengan laporan lengkap.
  String get _periodeLaporan =>
      _maksDidata == null ? _periode : '$_periode ($_labelDidata)';

  /// Laporan sesuai pilihan hari ke- & petugas, atau `null` (dengan pesan)
  /// bila kosong. Laporan bisa diinput kapan saja, jadi ambil semua lalu
  /// saring menurut hari ke- jadwalnya.
  Future<List<RevisitLaporan>?> _ambilLaporan() async {
    final semua = await _service.fetchLaporan(
      dari: DateTime(2026, 1, 1),
      sampai: DateTime(2027, 12, 31),
      petugasId: _dipilih.length == 1 ? _dipilih.single : null,
    );
    final laporan = semua.where((l) {
      final hari = l.hariKe ?? 0;
      return hari >= _hariDari &&
          hari <= _hariSampai &&
          _cocok(l.petugasId) &&
          (_maksDidata == null || (l.jumlahDidata ?? 0) <= _maksDidata!);
    }).toList();
    if (laporan.isEmpty) {
      _showSnack(
        _maksDidata != null
            ? 'Tidak ada laporan $_labelDidata pada hari ke- tersebut.'
            : 'Tidak ada laporan pada hari ke- tersebut.',
        error: true,
      );
      return null;
    }
    return laporan;
  }

  /// Baris List Harian dari jadwal alokasi: satu baris per petugas per hari
  /// per kecamatan, termasuk yang belum melapor. `null` (dengan pesan) bila
  /// kosong. Dipakai Excel List Harian dan SPD.
  Future<List<RevisitTranslokBaris>?> _ambilBarisJadwal() async {
    debugPrint(
      '[ListHarian] mulai: $_periode, petugas='
      '${_dipilih.isEmpty ? 'semua' : '${_dipilih.length} dipilih'}',
    );
    // Jadwal diambil per petugas lewat get_revisit_tugas_saya (membaca
    // tabel alokasi). get_revisit_alokasi di database masih versi lama
    // tanpa kolom "jadwal", jadwalnya selalu terbaca kosong.
    final petugas = _petugas.isNotEmpty
        ? _petugas
        : await _service.fetchPetugas();
    final dipilih = [
      for (final p in petugas)
        if (_dipilih.isEmpty ? p.isRevisit : _dipilih.contains(p.petugasId)) p,
    ];
    final kunjungan = <RevisitKunjungan>[];
    var selesai = 0;
    for (var i = 0; i < dipilih.length; i += 6) {
      await Future.wait(
        dipilih.skip(i).take(6).map((p) async {
          final tugas = await _service.fetchTugasSaya(petugasId: p.petugasId);
          for (final t in tugas) {
            final hari = t.hariKe ?? 0;
            if (hari < _hariDari || hari > _hariSampai) continue;
            kunjungan.add(
              RevisitKunjungan(
                petugasId: p.petugasId,
                nama: p.nama,
                hariKe: hari,
                kodeSls: t.kodeSls,
                nmKec: t.nmKec,
              ),
            );
          }
          selesai++;
          if (mounted) {
            setState(
              () => _status =
                  'Mengambil jadwal petugas $selesai/${dipilih.length}…',
            );
          }
        }),
      );
    }
    debugPrint(
      '[ListHarian] ${dipilih.length} petugas, '
      '${kunjungan.length} jadwal dalam rentang',
    );
    if (kunjungan.isEmpty) {
      _showSnack(
        'Tidak ada jadwal pada $_periode untuk ${dipilih.length} petugas.',
        error: true,
      );
      return null;
    }
    final baris = RevisitTranslokExcelService.susunBaris(kunjungan);
    debugPrint('[ListHarian] baris: ${baris.length}');
    return baris;
  }

  /// Jalankan [kerja] dengan status sibuk & penanganan galat yang sama.
  Future<void> _jalankan(String awal, Future<void> Function() kerja) async {
    setState(() {
      _busy = true;
      _status = awal;
    });
    try {
      await kerja();
    } catch (e, st) {
      debugPrint('[ListHarian] GAGAL: $e\n$st');
      if (mounted) _showSnack('Gagal: $e', error: true);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = null;
        });
      }
    }
  }

  /// Excel translok (List Harian).
  Future<void> _excel() => _jalankan('Mengambil jadwal petugas…', () async {
    final semua = await _ambilBarisJadwal();
    if (semua == null) return;
    // Satu baris per orang per hari (kecamatan pertama saja).
    final baris = RevisitTranslokExcelService.satuPerHari(semua);
    final path = await _excelService.exportToFile(baris, periode: _periode);
    debugPrint('[ListHarian] tersimpan: $path');
    await OpenFile.open(path);
    final tanpaNik = {
      for (final b in baris)
        if (b.nip.isEmpty) b.nama,
    };
    if (!mounted) return;
    _showSnack(
      tanpaNik.isEmpty
          ? '${baris.length} baris diekspor ke Excel.'
          : '${baris.length} baris diekspor. NIK belum terdaftar untuk: '
                '${tanpaNik.join(', ')}',
      error: tanpaNik.isNotEmpty,
    );
    Navigator.pop(context);
  });

  /// SPD (PDF): 2 halaman per baris List Harian.
  Future<void> _spd() => _jalankan('Mengambil jadwal petugas…', () async {
    final semua = await _ambilBarisJadwal();
    if (semua == null) return;
    // SPD 1 halaman: satu SPD per orang per hari (kecamatan pertama saja).
    final baris = widget.jenis == RevisitKeluaran.spd1
        ? RevisitTranslokExcelService.satuPerHari(semua)
        : semua;
    if (mounted) {
      setState(() => _status = 'Menyusun ${baris.length} SPD…');
    }
    final path = await _spdService.simpan(
      baris,
      RevisitSpdPengaturan(
        nomor: _spdNomor.text.trim(),
        ppkNama: _ppkNama.text.trim(),
        ppkNip: _ppkNip.text.trim(),
        kepalaNama: _kepalaNama.text.trim(),
        kepalaNip: _kepalaNip.text.trim(),
      ),
      periode: _periode,
      satuHalaman: widget.jenis == RevisitKeluaran.spd1,
    );
    debugPrint('[SPD] tersimpan: $path');
    await _simpanIsianSpd();
    await OpenFile.open(path);
    if (!mounted) return;
    final halaman = widget.jenis == RevisitKeluaran.spd1 ? 1 : 2;
    _showSnack(
      '${baris.length} SPD dibuat (${baris.length * halaman} halaman).',
    );
    Navigator.pop(context);
  });

  /// Daftar laporan (sesuai pilihan) yang pejabat yang ditemui-nya kosong.
  Future<void> _cekPejabat() => _jalankan('Mengambil data laporan…', () async {
    final laporan = await _ambilLaporan();
    if (laporan == null || !mounted) return;
    await showRevisitCekPejabatDialog(context, laporan);
  });

  /// Sebelum membuat laporan: bila ada pejabat yang belum diisi, tawarkan
  /// cek dulu. `true` = lanjut membuat. Gagal memeriksa tidak menghalangi.
  Future<bool> _lanjutMeskiPejabatKosong(List<RevisitLaporan> laporan) async {
    if (mounted) setState(() => _status = 'Memeriksa pejabat yang ditemui…');
    final List<RevisitPejabatKurang> kurang;
    try {
      kurang = await revisitCekPejabat(laporan);
    } catch (e) {
      debugPrint('[LaporanDoc] cek pejabat gagal: $e');
      return true;
    }
    if (kurang.isEmpty || !mounted) return true;
    final pilihan = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pejabat belum lengkap'),
        content: Text(
          '${kurang.length} dari ${revisitJumlahHalaman(laporan)} halaman '
          'laporan belum berisi nama dan/atau jabatan pejabat yang ditemui. '
          'Di dokumen, bagian itu akan berupa titik-titik.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'lanjut'),
            child: const Text('Tetap buat'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'cek'),
            child: const Text('Cek dulu'),
          ),
        ],
      ),
    );
    if (pilihan == 'cek' && mounted) {
      await showRevisitCekPejabatDialog(context, laporan);
      return false;
    }
    return pilihan == 'lanjut';
  }

  Future<void> _buat() async {
    setState(() {
      _busy = true;
      _status = 'Mengambil data laporan…';
    });
    try {
      final laporan = await _ambilLaporan();
      if (laporan == null) return;
      if (!await _lanjutMeskiPejabatKosong(laporan)) return;
      final hasil = await _docService.buat(
        laporan: laporan,
        periode: _periodeLaporan,
        mengetahui: RevisitPejabatMengetahui(
          nama: _mengetahuiNama.text.trim(),
          jabatan: _mengetahuiJabatan.text.trim(),
          nip: _mengetahuiNip.text.trim(),
        ),
        onProgress: (status) {
          if (mounted) setState(() => _status = status);
        },
      );
      await _simpanPenandaTangan();
      // Satu petugas: buka dokumennya. Banyak petugas: buka foldernya saja
      // (bukan puluhan tab sekaligus).
      final satuLink = hasil.dokumen.length == 1
          ? hasil.dokumen.values.single
          : '';
      final buka = satuLink.isNotEmpty ? satuLink : hasil.folderLink;
      await launchUrl(Uri.parse(buka), mode: LaunchMode.externalApplication);
      if (mounted && hasil.dokumen.length > 1) {
        _showSnack('${hasil.dokumen.length} laporan dibuat, satu per petugas.');
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) _showSnack('Gagal membuat laporan: $e', error: true);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = null;
        });
      }
    }
  }

  /// Laporan sebagai PDF lokal (cadangan bila unggah Google Docs gagal).
  Future<void> _pdf() => _jalankan('Mengambil data laporan…', () async {
    final laporan = await _ambilLaporan();
    if (laporan == null) return;
    if (!await _lanjutMeskiPejabatKosong(laporan)) return;
    final path = await _docService.buatPdf(
      laporan: laporan,
      periode: _periodeLaporan,
      mengetahui: RevisitPejabatMengetahui(
        nama: _mengetahuiNama.text.trim(),
        jabatan: _mengetahuiJabatan.text.trim(),
        nip: _mengetahuiNip.text.trim(),
      ),
      onProgress: (status) {
        if (mounted) setState(() => _status = status);
      },
    );
    debugPrint('[LaporanPdf] tersimpan: $path');
    await _simpanPenandaTangan();
    await OpenFile.open(path);
    if (mounted) Navigator.pop(context);
  });

  void _showSnack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red : null,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static const List<String> _bulanPendek = [
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

  String _labelHari(int hari) {
    final t = RevisitLaporanDocx.tanggalHariKe(hari)!;
    return 'Hari $hari (${t.day} ${_bulanPendek[t.month - 1]})';
  }

  Widget _pilihHari({
    required String label,
    required int nilai,
    required ValueChanged<int> onChanged,
  }) {
    return DropdownButtonFormField<int>(
      initialValue: nilai,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      items: [
        for (var h = 1; h <= RevisitLaporanDocx.hariKeTerakhir; h++)
          DropdownMenuItem<int>(value: h, child: Text(_labelHari(h))),
      ],
      onChanged: _busy ? null : (v) => v == null ? null : onChanged(v),
    );
  }

  List<Widget> _isianSpdWidget() {
    Widget field(TextEditingController c, String label, {String? bantuan}) =>
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: TextField(
            controller: c,
            decoration: InputDecoration(
              labelText: label,
              helperText: bantuan,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
        );
    return [
      field(
        _spdNomor,
        'Nomor SPD pertama',
        bantuan:
            'Angka depan bertambah per SPD (011, 012, …); bulan '
            'mengikuti tanggal perjalanan.',
      ),
      field(_ppkNama, 'Nama Pejabat Pembuat Komitmen'),
      field(_ppkNip, 'NIP Pejabat Pembuat Komitmen'),
      field(_kepalaNama, 'Nama Kepala BPS'),
      field(_kepalaNip, 'NIP Kepala BPS'),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(switch (widget.jenis) {
        RevisitKeluaran.listHarian => 'List Harian (Excel)',
        RevisitKeluaran.spd => 'SPD (PDF)',
        RevisitKeluaran.spd1 => 'SPD 1 Halaman (PDF)',
        RevisitKeluaran.laporan => 'Buat Laporan Revisit',
      }),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: _pilihHari(
                    label: 'Dari',
                    nilai: _hariDari,
                    onChanged: (v) => setState(() {
                      _hariDari = v;
                      if (_hariSampai < v) _hariSampai = v;
                    }),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _pilihHari(
                    label: 'Sampai',
                    nilai: _hariSampai,
                    onChanged: (v) => setState(() {
                      _hariSampai = v;
                      if (_hariDari > v) _hariDari = v;
                    }),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _busy || _petugas.isEmpty ? null : _pilihPetugas,
              borderRadius: BorderRadius.circular(4),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Petugas',
                  border: OutlineInputBorder(),
                  isDense: true,
                  suffixIcon: Icon(Icons.arrow_drop_down_rounded),
                ),
                child: Text(
                  _petugas.isEmpty ? 'Memuat petugas…' : _labelPetugas,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            // Isian penanda tangan hanya untuk laporan Google Docs.
            if (_spdMode) ..._isianSpdWidget(),
            if (widget.jenis == RevisitKeluaran.laporan) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                initialValue: _maksDidata,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Laporan yang diambil',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem<int?>(child: Text('Semua laporan')),
                  DropdownMenuItem<int?>(
                    value: 0,
                    child: Text('Hanya yang didata 0'),
                  ),
                  DropdownMenuItem<int?>(
                    value: 2,
                    child: Text('Hanya yang didata 0-2'),
                  ),
                ],
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _maksDidata = v),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _mengetahuiJabatan,
                decoration: const InputDecoration(
                  labelText: 'Jabatan pejabat yang mengetahui',
                  hintText: 'Contoh: Kepala BPS Kota Parepare',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _mengetahuiNama,
                decoration: const InputDecoration(
                  labelText: 'Nama pejabat yang mengetahui',
                  hintText: 'Contoh: Dian Ernawaty, S.ST, M.A.P',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _mengetahuiNip,
                decoration: const InputDecoration(
                  labelText: 'NIP pejabat (opsional)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
            if (_busy && _status != null) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Text(_status!, style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        if (widget.jenis == RevisitKeluaran.laporan)
          OutlinedButton.icon(
            onPressed: _busy ? null : _cekPejabat,
            icon: const Icon(Icons.fact_check_outlined),
            label: const Text('Cek Pejabat'),
          ),
        if (widget.jenis == RevisitKeluaran.laporan)
          OutlinedButton.icon(
            onPressed: _busy ? null : _pdf,
            icon: const Icon(Icons.picture_as_pdf_rounded),
            label: const Text('Unduh PDF'),
          ),
        FilledButton.icon(
          onPressed: _busy
              ? null
              : switch (widget.jenis) {
                  RevisitKeluaran.listHarian => _excel,
                  RevisitKeluaran.spd || RevisitKeluaran.spd1 => _spd,
                  RevisitKeluaran.laporan => _buat,
                },
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(switch (widget.jenis) {
                  RevisitKeluaran.listHarian => Icons.table_view_rounded,
                  RevisitKeluaran.spd ||
                  RevisitKeluaran.spd1 => Icons.picture_as_pdf_rounded,
                  RevisitKeluaran.laporan => Icons.description_rounded,
                }),
          label: Text(switch (widget.jenis) {
            RevisitKeluaran.listHarian => 'Unduh Excel',
            RevisitKeluaran.spd || RevisitKeluaran.spd1 => 'Unduh SPD',
            RevisitKeluaran.laporan => 'Buat Laporan',
          }),
        ),
      ],
    );
  }
}
