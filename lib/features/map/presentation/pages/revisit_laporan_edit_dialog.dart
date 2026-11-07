import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models/revisit_models.dart';
import '../../data/services/revisit_service.dart';
import 'revisit_page.dart';

/// Admin: edit progres satu laporan (tanggal, status, angka, catatan,
/// pejabat). Foto tetap dikelola petugas lewat form laporannya. Mengembalikan
/// `true` bila tersimpan.
Future<bool> showRevisitLaporanEditDialog(
  BuildContext context,
  RevisitLaporan laporan,
) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _RevisitLaporanEditDialog(laporan: laporan),
  );
  return ok == true;
}

class _RevisitLaporanEditDialog extends StatefulWidget {
  final RevisitLaporan laporan;

  const _RevisitLaporanEditDialog({required this.laporan});

  @override
  State<_RevisitLaporanEditDialog> createState() =>
      _RevisitLaporanEditDialogState();
}

class _RevisitLaporanEditDialogState extends State<_RevisitLaporanEditDialog> {
  final RevisitService _service = RevisitService();

  late DateTime _tanggal = widget.laporan.tanggal;
  late String? _status = widget.laporan.status.isEmpty
      ? null
      : widget.laporan.status;
  late final _didata = TextEditingController(
    text: '${widget.laporan.jumlahDidata ?? 0}',
  );
  late final _submit = TextEditingController(
    text: '${widget.laporan.jumlahSubmit ?? 0}',
  );
  late final _belum = TextEditingController(
    text: '${widget.laporan.jumlahBelumDidata ?? 0}',
  );
  late final _catatan = TextEditingController(text: widget.laporan.catatan);
  final _pejabatNama = TextEditingController();
  final _pejabatJabatan = TextEditingController();
  final _jalan = TextEditingController();
  final _bangunan = TextEditingController();

  /// Penyisiran tersimpan; hanya dikirim ulang bila berubah.
  RevisitPenyisiran _penyisiranAwal = RevisitPenyisiran.kosongan;

  /// Pejabat tersimpan; hanya dikirim ulang bila berubah.
  RevisitPejabat _pejabatAwal = const RevisitPejabat(nama: '', jabatan: '');
  bool _loadingPejabat = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPejabat();
    _loadPenyisiran();
  }

  Future<void> _loadPenyisiran() async {
    try {
      final p = (await _service.fetchPenyisiran([
        widget.laporan.id,
      ]))[widget.laporan.id];
      if (!mounted || p == null) return;
      setState(() {
        _penyisiranAwal = p;
        _jalan.text = p.jalan;
        _bangunan.text = p.bangunan?.toString() ?? '';
      });
    } catch (_) {
      // Kolom penyisiran belum ada / gagal dibaca: biarkan kosong.
    }
  }

  @override
  void dispose() {
    _didata.dispose();
    _submit.dispose();
    _belum.dispose();
    _catatan.dispose();
    _pejabatNama.dispose();
    _pejabatJabatan.dispose();
    _jalan.dispose();
    _bangunan.dispose();
    super.dispose();
  }

  Future<void> _loadPejabat() async {
    try {
      final hasil = await _service.fetchPejabat([widget.laporan.id]);
      final p = hasil[widget.laporan.id];
      if (!mounted) return;
      if (p != null) {
        _pejabatAwal = p;
        _pejabatNama.text = p.nama;
        _pejabatJabatan.text = p.jabatan;
      }
    } catch (_) {
      // Kolom pejabat belum ada / gagal dibaca: biarkan kosong.
    }
    if (mounted) setState(() => _loadingPejabat = false);
  }

  Future<void> _pickTanggal() async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _tanggal,
      firstDate: DateTime(today.year - 1),
      lastDate: today,
    );
    if (picked != null) setState(() => _tanggal = picked);
  }

  int? _angka(TextEditingController c) => int.tryParse(c.text.trim());

  Future<void> _simpan() async {
    final didata = _angka(_didata);
    final submit = _angka(_submit);
    final belum = _angka(_belum);
    final catatan = _catatan.text.trim();
    if (_status == null ||
        didata == null ||
        submit == null ||
        belum == null ||
        catatan.isEmpty) {
      setState(
        () => _error =
            'Status, jumlah didata, submit, potensi belum didata, dan '
            'catatan wajib diisi.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _service.editLaporanAdmin(
        widget.laporan.id,
        tanggal: _tanggal,
        status: _status!,
        jumlahDidata: didata,
        jumlahSubmit: submit,
        jumlahBelumDidata: belum,
        catatan: catatan,
      );
      final nama = _pejabatNama.text.trim();
      final jabatan = _pejabatJabatan.text.trim();
      if (nama != _pejabatAwal.nama || jabatan != _pejabatAwal.jabatan) {
        await _service.simpanPejabat(
          widget.laporan.id,
          nama: nama,
          jabatan: jabatan,
        );
      }
      final penyisiran = RevisitPenyisiran(
        jalan: _jalan.text.trim(),
        bangunan: _angka(_bangunan),
      );
      if (penyisiran != _penyisiranAwal) {
        await _service.simpanPenyisiran(
          widget.laporan.id,
          jalan: penyisiran.jalan,
          bangunan: penyisiran.bangunan,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Gagal menyimpan: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.laporan;
    return AlertDialog(
      title: const Text('Edit progres'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                [
                  l.slsLabel,
                  if (l.hariKe != null) 'Hari ke-${l.hariKe}',
                  l.petugasNama,
                ].where((e) => e.isNotEmpty).join(' · '),
                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _saving ? null : _pickTanggal,
                icon: const Icon(Icons.event_rounded, size: 18),
                label: Text(revisitDateLabel(_tanggal, withDay: true)),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final s in RevisitStatus.all)
                    ChoiceChip(
                      visualDensity: VisualDensity.compact,
                      label: Text(s.label),
                      selected: _status == s.value,
                      selectedColor: s.color,
                      showCheckmark: false,
                      labelStyle: TextStyle(
                        color: _status == s.value ? Colors.white : s.color,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                      backgroundColor: Colors.white,
                      side: BorderSide(color: s.color.withValues(alpha: 0.5)),
                      onSelected: _saving
                          ? null
                          : (_) => setState(() => _status = s.value),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              _angkaField('Jumlah didata', _didata),
              const SizedBox(height: 8),
              _angkaField('Jumlah submit', _submit),
              const SizedBox(height: 8),
              _angkaField('Potensi belum didata', _belum),
              const SizedBox(height: 12),
              TextField(
                controller: _catatan,
                enabled: !_saving,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Catatan',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _jalan,
                enabled: !_saving,
                decoration: const InputDecoration(
                  labelText: 'Nama jalan/perumahan yang disisir',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              _angkaField('Jumlah bangunan', _bangunan),
              const SizedBox(height: 12),
              TextField(
                controller: _pejabatNama,
                enabled: !_saving && !_loadingPejabat,
                decoration: const InputDecoration(
                  labelText: 'Nama pejabat yang ditemui',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _pejabatJabatan,
                enabled: !_saving && !_loadingPejabat,
                decoration: const InputDecoration(
                  labelText: 'Jabatan pejabat',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: _saving ? null : _simpan,
          style: FilledButton.styleFrom(backgroundColor: revisitPrimary),
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Simpan'),
        ),
      ],
    );
  }

  Widget _angkaField(String label, TextEditingController c) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: Color(0xFF334155),
            ),
          ),
        ),
        SizedBox(
          width: 96,
          child: TextField(
            controller: c,
            enabled: !_saving,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
        ),
      ],
    );
  }
}
