import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models/revisit_models.dart';
import '../../data/services/revisit_import_parser.dart';
import '../../data/services/revisit_service.dart';
import 'revisit_page.dart';

/// "Impor Cepat" alokasi revisit. Saat dibuka langsung membaca clipboard
/// (email/nama petugas + kode wilayah, opsional tim & hari ke-) dan
/// menampilkan daftar verifikasi; pengguna cukup cek lalu Simpan.
/// Mengembalikan `true` bila ada yang disimpan.
class RevisitImporPage extends StatefulWidget {
  final List<RevisitPetugas> petugas;
  final List<RevisitAlokasiItem> sls;

  const RevisitImporPage({super.key, required this.petugas, required this.sls});

  @override
  State<RevisitImporPage> createState() => _RevisitImporPageState();
}

enum _Filter { semua, dicek, error }

class _RevisitImporPageState extends State<RevisitImporPage> {
  static const Color _ok = Color(0xFF2E7D32);
  static const Color _warn = Color(0xFFB45309);
  static const Color _err = Color(0xFFC62828);

  final RevisitService _service = RevisitService();
  final TextEditingController _text = TextEditingController();
  late final RevisitImportParser _parser = RevisitImportParser(
    petugas: widget.petugas,
    sls: widget.sls,
  );

  RevisitImportResult? _result;
  _Filter _filter = _Filter.semua;
  bool _saving = false;

  /// true = petugas lain pada (SLS, hari) yang diimpor dilepas (tukar).
  bool _modeGanti = false;
  bool _membaca = true;
  bool _manual = false;

  @override
  void initState() {
    super.initState();
    _ambilClipboard(auto: true);
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  /// Baca clipboard lalu langsung periksa. [auto] = saat halaman dibuka:
  /// gagal/kosong tidak memunculkan pesan, cukup tampilkan petunjuk.
  Future<void> _ambilClipboard({bool auto = false}) async {
    setState(() => _membaca = true);
    var text = '';
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      text = data?.text ?? '';
    } catch (_) {}
    if (!mounted) return;
    setState(() => _membaca = false);
    if (text.trim().isEmpty) {
      if (!auto) {
        _snack(
          'Clipboard kosong. Salin dulu datanya dari Excel/Sheets.',
          error: true,
        );
      }
      return;
    }
    _text.text = text;
    _periksa(silent: auto);
  }

  void _periksa({bool silent = false}) {
    final result = _parser.parse(_text.text);
    markRevisitImportDuplicates(result.rows);
    if (result.rows.isEmpty) {
      if (!silent) {
        _snack(
          'Tidak ada baris berisi kode wilayah. Periksa data yang disalin.',
          error: true,
        );
      }
      return;
    }
    setState(() {
      _result = result;
      _manual = false;
      _filter = result.rows.any((r) => r.hasError)
          ? _Filter.error
          : result.rows.any((r) => r.hasWarning)
          ? _Filter.dicek
          : _Filter.semua;
    });
  }

  Future<void> _pilihPetugas(RevisitImportRowPreview row) async {
    final picked = await showModalBottomSheet<RevisitPetugas>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CariPetugasSheet(
        petugas: widget.petugas,
        kandidat: row.kandidat,
        namaInput: row.namaInput,
      ),
    );
    if (picked == null) return;
    setState(() {
      row.petugas = picked;
      row.manual = true;
    });
  }

  List<RevisitImportRow> get _payload => [
    for (final r in _result?.rows ?? const <RevisitImportRowPreview>[])
      if (r.willApply)
        for (final s in r.sls)
          RevisitImportRow(
            kodeSls: s.kodeSls,
            petugasId: r.petugas!.petugasId,
            hariKe: r.hariKe,
            tim: r.tim,
          ),
  ];

  Future<void> _terapkan() async {
    final payload = _payload;
    if (payload.isEmpty) return;
    final rows = _result!.rows;
    final error = rows.where((r) => r.hasError).length;
    final petugasBaru = {
      for (final r in rows)
        if (r.willApply && !r.petugas!.isRevisit) r.petugas!.petugasId,
    };

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Simpan alokasi?'),
        content: Text(
          '${payload.map((p) => p.kodeSls).toSet().length} SLS '
          '(${payload.length} baris jadwal) akan dialokasikan.'
          '${_modeGanti ? '\nMode GANTI: petugas lain pada SLS & hari yang sama akan dilepas.' : ''}'
          '${petugasBaru.isNotEmpty ? '\n${petugasBaru.length} petugas otomatis masuk tim revisit.' : ''}'
          '${error > 0 ? '\n$error baris error dilewati.' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _saving = true);
    try {
      final (count, skipped, dilepas) = await _service.importAlokasi(
        payload,
        ganti: _modeGanti,
      );
      if (!mounted) return;
      _snack(
        '$count jadwal disimpan'
        '${dilepas > 0 ? ' · $dilepas jadwal petugas lain dilepas' : ''}'
        '${skipped > 0 ? ' · $skipped dilewati server' : ''}',
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack('Gagal menyimpan: $e', error: true);
    }
  }

  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red : null,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        backgroundColor: revisitBackground,
        appBar: AppBar(
          title: const Text('Impor Cepat Alokasi'),
          backgroundColor: revisitPrimary,
          foregroundColor: Colors.white,
          actions: [
            if (_result != null)
              IconButton(
                tooltip: 'Edit teks manual',
                onPressed: _saving
                    ? null
                    : () => setState(() {
                        _result = null;
                        _manual = true;
                      }),
                icon: const Icon(Icons.edit_note_rounded),
              ),
          ],
        ),
        body: _membaca
            ? const Center(child: CircularProgressIndicator())
            : _result == null
            ? _buildInput()
            : _buildVerifikasi(),
        bottomNavigationBar: _membaca
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: _result == null
                      ? _inputActions()
                      : _verifikasiActions(),
                ),
              ),
      ),
    );
  }

  // ── Belum ada data: petunjuk + input manual (opsional) ──────────────────

  Widget _buildInput() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFE8F1FB),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.content_paste_search_rounded,
                    color: revisitPrimary,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Salin (Ctrl/Cmd + C) data di Excel / Google Sheets, '
                      'lalu tekan "Ambil Clipboard".',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 8),
              Text(
                'Wajib: email petugas (disarankan) atau nama, dan kode wilayah '
                '(16 digit SLS, atau 14 digit untuk semua sub-SLS). Opsional: '
                'tim dan hari ke-. Ikutkan baris judul agar kolom terbaca tepat:',
                style: TextStyle(height: 1.4),
              ),
              SizedBox(height: 8),
              SelectableText(
                'Tim\tEmail\tKode Wilayah\tHari\n'
                '1\tandi@bps.go.id\t7372010001000100\t1\n'
                '1\tcitra@bps.go.id\t7372010001000200\t1',
                style: TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (!_manual)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _manual = true),
              icon: const Icon(Icons.keyboard_rounded),
              label: const Text('Atau ketik / tempel manual'),
            ),
          )
        else ...[
          const SizedBox(height: 4),
          TextField(
            controller: _text,
            minLines: 8,
            maxLines: 20,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            decoration: const InputDecoration(
              hintText: 'Tempel / ketik data di sini…',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: _text.text.trim().isEmpty ? null : _periksa,
              icon: const Icon(Icons.fact_check_rounded),
              label: const Text('Periksa teks ini'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _inputActions() {
    return FilledButton.icon(
      onPressed: _ambilClipboard,
      style: FilledButton.styleFrom(
        backgroundColor: revisitPrimary,
        minimumSize: const Size.fromHeight(52),
      ),
      icon: const Icon(Icons.content_paste_go_rounded),
      label: const Text('Ambil Clipboard'),
    );
  }

  // ── Tahap 2: verifikasi ────────────────────────────────────────────────────

  Widget _buildVerifikasi() {
    final rows = _result!.rows;
    final nError = rows.where((r) => r.hasError).length;
    final nWarn = rows.where((r) => r.hasWarning).length;
    final nOk = rows.length - nError - nWarn;
    final nSls = _payload.map((p) => p.kodeSls).toSet().length;
    final nJadwal = _payload.length;
    final shown = rows.where((r) {
      return switch (_filter) {
        _Filter.semua => true,
        _Filter.dicek => r.hasWarning,
        _Filter.error => r.hasError,
      };
    }).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _stat('${rows.length}', 'baris', revisitPrimary),
            _stat('$nOk', 'siap', _ok),
            _stat('$nWarn', 'perlu dicek', _warn),
            _stat('$nError', 'error', _err),
            _stat('$nSls', 'SLS disimpan', revisitPrimary),
            _stat('$nJadwal', 'baris jadwal', revisitPrimary),
          ],
        ),
        if (_result!.ignoredLines > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '${_result!.ignoredLines} baris tanpa kode wilayah diabaikan.',
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
            ),
          ),
        ..._timInfo(),
        const SizedBox(height: 12),
        _pilihMode(),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            for (final f in _Filter.values)
              ChoiceChip(
                label: Text(switch (f) {
                  _Filter.semua => 'Semua',
                  _Filter.dicek => 'Perlu dicek ($nWarn)',
                  _Filter.error => 'Error ($nError)',
                }),
                selected: _filter == f,
                onSelected: (_) => setState(() => _filter = f),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (shown.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: Text('Tidak ada baris.')),
          ),
        for (final r in shown) ...[_rowCard(r), const SizedBox(height: 8)],
      ],
    );
  }

  /// Mode simpan: menambah petugas, atau menukar petugas pada SLS+hari itu.
  Widget _pilihMode() {
    final nTukar = _result!.rows
        .where((r) => r.willApply && _rekanLain(r).isNotEmpty)
        .length;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Mode simpan',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                ),
              ),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12)),
                ),
                segments: const [
                  ButtonSegment(
                    value: false,
                    icon: Icon(Icons.person_add_alt_1_rounded, size: 16),
                    label: Text('Tambah'),
                  ),
                  ButtonSegment(
                    value: true,
                    icon: Icon(Icons.swap_horiz_rounded, size: 16),
                    label: Text('Ganti'),
                  ),
                ],
                selected: {_modeGanti},
                onSelectionChanged: (v) => setState(() => _modeGanti = v.first),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _modeGanti
                ? 'Ganti: petugas lain pada SLS & hari yang diimpor dilepas'
                      '${nTukar > 0 ? ' ($nTukar baris menukar petugas lain)' : ''}.'
                : 'Tambah: petugas lain pada SLS & hari yang sama tetap '
                      'dipertahankan.',
            style: TextStyle(
              fontSize: 12,
              color: _modeGanti ? _warn : const Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }

  /// Petugas lain yang sudah memegang (SLS, hari) baris ini.
  Set<String> _rekanLain(RevisitImportRowPreview r) {
    final p = r.petugas;
    if (p == null) return {};
    final hari = r.hariKe ?? 0;
    return {
      for (final s in r.sls)
        for (final j in s.jadwalHari(hari))
          if (j.petugasId != p.petugasId)
            j.nama.isEmpty ? 'petugas lain' : j.nama,
    };
  }

  /// Peringatan tim yang anggotanya bukan 2 orang (informasi saja).
  List<Widget> _timInfo() {
    final timOf = <String, String>{
      for (final p in widget.petugas)
        if (p.isRevisit && p.tim.isNotEmpty) p.petugasId: p.tim,
    };
    for (final r in _result!.rows) {
      if (r.willApply && r.tim != null) timOf[r.petugas!.petugasId] = r.tim!;
    }
    final anggota = <String, int>{};
    for (final t in timOf.values) {
      anggota[t] = (anggota[t] ?? 0) + 1;
    }
    final aneh = anggota.entries.where((e) => e.value != 2).toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    if (aneh.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          'Info tim (seharusnya 2 orang): '
          '${aneh.map((e) => '${revisitTimLabel(e.key)} ${e.value} orang').join(' · ')}',
          style: const TextStyle(color: _warn, fontSize: 12),
        ),
      ),
    ];
  }

  Widget _stat(String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  Widget _rowCard(RevisitImportRowPreview r) {
    final issues = r.issues;
    final color = r.hasError
        ? _err
        : r.hasWarning
        ? _warn
        : _ok;
    final p = r.petugas;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: color, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Baris ${r.lineNo}',
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  r.raw.replaceAll('\t', '  ·  '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF94A3B8),
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Wilayah
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.place_rounded,
                size: 18,
                color: r.sls.isEmpty ? _err : revisitPrimary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: r.sls.isEmpty
                    ? Text(
                        r.kodeInput,
                        style: const TextStyle(
                          color: _err,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            r.sls.length == 1
                                ? r.sls.first.slsLabel
                                : '${r.sls.length} sub-SLS: '
                                      '${r.sls.map((s) => s.slsLabel).join(', ')}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            '${revisitWilayahLabel(r.sls.first.nmDesa, r.sls.first.nmKec)}'
                            ' · ${r.kodeInput}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Petugas
          Row(
            children: [
              Icon(
                Icons.person_rounded,
                size: 18,
                color: p == null ? _err : revisitPrimary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p == null ? 'Belum cocok' : p.nama,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: p == null ? _err : null,
                      ),
                    ),
                    Text(
                      [
                        r.emailInput != null
                            ? 'email: ${r.emailInput}'
                            : 'tertulis: "${r.namaInput}"',
                        if (p != null) revisitRoleLabel(p.role),
                        if (p != null && !p.isRevisit) 'akan masuk tim',
                      ].join(' · '),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: _saving ? null : () => _pilihPetugas(r),
                child: Text(p == null ? 'Pilih petugas' : 'Ubah petugas'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _chipAksi(r.aksi),
              if (_modeGanti && _rekanLain(r).isNotEmpty)
                _chipTukar(_rekanLain(r)),
              if (r.tim != null) _chip(revisitTimLabel(r.tim!)),
              if (r.hariKe != null) _chip('Hari ke-${r.hariKe}'),
            ],
          ),
          if (issues.isNotEmpty) ...[
            const SizedBox(height: 6),
            for (final i in issues)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  children: [
                    Icon(
                      i.isError
                          ? Icons.error_rounded
                          : i.isInfo
                          ? Icons.info_outline_rounded
                          : Icons.warning_amber_rounded,
                      size: 15,
                      color: i.isError
                          ? _err
                          : i.isInfo
                          ? revisitPrimary
                          : _warn,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        i.message,
                        style: TextStyle(
                          fontSize: 12,
                          color: i.isError
                              ? _err
                              : i.isInfo
                              ? revisitPrimary
                              : _warn,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  /// Penanda apa yang akan terjadi: tambah atau sudah ada.
  Widget _chipAksi(RevisitImportAksi aksi) {
    final (label, warna) = switch (aksi) {
      RevisitImportAksi.tambah => ('Tambah', _ok),
      RevisitImportAksi.sudahAda => ('Sudah ada', const Color(0xFF64748B)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: warna.withValues(alpha: 0.12),
        border: Border.all(color: warna.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: warna,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _chipTukar(Set<String> rekan) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _warn.withValues(alpha: 0.12),
        border: Border.all(color: _warn.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'Melepas ${rekan.join(', ')}',
        style: const TextStyle(
          fontSize: 11,
          color: _warn,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _chip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F1FB),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          color: revisitPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _verifikasiActions() {
    final n = _payload.map((p) => p.kodeSls).toSet().length;
    return Row(
      children: [
        OutlinedButton.icon(
          onPressed: _saving ? null : _ambilClipboard,
          icon: const Icon(Icons.content_paste_go_rounded),
          label: const Text('Ambil Ulang'),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton.icon(
            onPressed: _saving || n == 0 ? null : _terapkan,
            style: FilledButton.styleFrom(backgroundColor: revisitPrimary),
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save_rounded),
            label: Text('Simpan $n SLS'),
          ),
        ),
      ],
    );
  }
}

/// Pilih petugas: kandidat hasil pencocokan di atas, lalu semua petugas.
class _CariPetugasSheet extends StatefulWidget {
  final List<RevisitPetugas> petugas;
  final List<RevisitPetugas> kandidat;
  final String namaInput;

  const _CariPetugasSheet({
    required this.petugas,
    required this.kandidat,
    required this.namaInput,
  });

  @override
  State<_CariPetugasSheet> createState() => _CariPetugasSheetState();
}

class _CariPetugasSheetState extends State<_CariPetugasSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = RevisitImportParser.normalizeNama(_query);
    final List<RevisitPetugas> list;
    if (q.isEmpty) {
      final ids = {for (final k in widget.kandidat) k.petugasId};
      list = [
        ...widget.kandidat,
        ...widget.petugas.where((p) => !ids.contains(p.petugasId)),
      ];
    } else {
      list = widget.petugas
          .where(
            (p) =>
                RevisitImportParser.normalizeNama(p.nama).contains(q) ||
                p.email.toLowerCase().contains(q),
          )
          .toList();
    }

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Column(
        children: [
          Text(
            'Pilih petugas untuk "${widget.namaInput}"',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                hintText: 'Cari nama / email',
                prefixIcon: Icon(Icons.search_rounded),
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: list.length,
              itemBuilder: (context, i) {
                final p = list[i];
                final isKandidat = q.isEmpty && i < widget.kandidat.length;
                return ListTile(
                  leading: CircleAvatar(
                    child: Text(
                      revisitRoleLabel(p.role),
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                  title: Text(p.nama),
                  subtitle: Text(
                    [
                      if (p.email.isNotEmpty) p.email,
                      if (p.isRevisit)
                        p.tim.isEmpty ? 'tim revisit' : revisitTimLabel(p.tim),
                    ].join(' · '),
                  ),
                  trailing: isKandidat
                      ? const Icon(Icons.auto_awesome_rounded, size: 18)
                      : null,
                  onTap: () => Navigator.pop(context, p),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
