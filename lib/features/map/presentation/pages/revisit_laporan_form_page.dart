import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/models/revisit_models.dart';
import '../../data/services/revisit_service.dart';
import '../widgets/revisit_widgets.dart';

/// Form laporan harian revisit untuk satu SLS pada satu tanggal. Laporan
/// SLS+tanggal yang sama di-update (bukan dobel). Mengembalikan `true` bila
/// ada perubahan tersimpan.
class RevisitLaporanFormPage extends StatefulWidget {
  final String kodeSls;
  final String slsLabel;
  final String wilayahLabel;
  final DateTime? tanggal;

  /// Jadwal yang dilaporkan (hari ke-; null/0 = jadwal tanpa hari). Satu
  /// laporan per (SLS, petugas, hari ke-).
  final int? hariKe;

  /// Sisa potensi belum didata dari laporan terakhir SLS ini; mengisi awal
  /// kolom tsb pada laporan baru agar petugas cukup memperbaruinya.
  final int? belumDidataTerakhir;

  const RevisitLaporanFormPage({
    super.key,
    required this.kodeSls,
    required this.slsLabel,
    required this.wilayahLabel,
    this.tanggal,
    this.hariKe,
    this.belumDidataTerakhir,
  });

  @override
  State<RevisitLaporanFormPage> createState() => _RevisitLaporanFormPageState();
}

class _PickedFoto {
  final Uint8List bytes;
  final String extension;

  const _PickedFoto(this.bytes, this.extension);
}

class _RevisitLaporanFormPageState extends State<RevisitLaporanFormPage> {
  static const Color _primary = Color(0xFF0F4C81);

  final RevisitService _service = RevisitService();
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _jumlahController = TextEditingController();
  final TextEditingController _belumController = TextEditingController();
  final TextEditingController _submitController = TextEditingController();
  final TextEditingController _catatanController = TextEditingController();

  late DateTime _tanggal;
  String? _status;
  RevisitLaporan? _existing;
  List<RevisitFoto> _existingFoto = [];
  final List<_PickedFoto> _newFoto = [];

  bool _loading = true;
  bool _saving = false;
  bool _changed = false;

  /// true setelah Simpan ditekan: kolom yang masih kosong ditandai merah.
  bool _cekWajib = false;

  static const Color _merah = Color(0xFFC62828);

  bool get _fotoKosong => _existingFoto.isEmpty && _newFoto.isEmpty;
  bool _kosong(TextEditingController c) => c.text.trim().isEmpty;

  /// Daftar isian wajib yang belum diisi (urut sesuai tampilan form).
  List<String> get _belumDiisi => [
    if (_fotoKosong) 'foto',
    if (_status == null) 'status',
    if (_kosong(_jumlahController)) 'jumlah didata',
    if (_kosong(_submitController)) 'jumlah submit',
    if (_kosong(_belumController)) 'potensi belum didata',
    if (_kosong(_catatanController)) 'catatan',
  ];
  String? _progress;

  @override
  void initState() {
    super.initState();
    final t = widget.tanggal ?? DateTime.now();
    _tanggal = DateTime(t.year, t.month, t.day);
    _loadExisting();
  }

  @override
  void dispose() {
    _jumlahController.dispose();
    _belumController.dispose();
    _submitController.dispose();
    _catatanController.dispose();
    super.dispose();
  }

  Future<void> _loadExisting() async {
    setState(() => _loading = true);
    try {
      // Laporan milik sendiri saja: satu SLS+tanggal bisa punya laporan
      // dari beberapa petugas.
      // Laporan jadwal ini saja (SLS + hari ke- + petugas yang login).
      // Rentang tanggal dilebarkan karena laporan boleh diisi tanggal lain.
      final list = await _service.fetchLaporan(
        dari: _tanggal.subtract(const Duration(days: 365)),
        sampai: DateTime.now(),
        kodeSls: widget.kodeSls,
        milikSaya: true,
        hariKe: widget.hariKe ?? 0,
      );
      if (!mounted) return;
      final existing = list.isEmpty ? null : list.first;
      setState(() {
        _existing = existing;
        if (existing != null) _tanggal = existing.tanggal;
        _status = existing?.status;
        // Laporan baru: angka diisi 0 (bukan sekadar hint abu-abu) agar
        // petugas tinggal mengubah yang perlu dan tidak mengira sudah terisi.
        _jumlahController.text = existing?.jumlahDidata?.toString() ?? '0';
        _submitController.text = existing?.jumlahSubmit?.toString() ?? '0';
        _belumController.text =
            (existing == null
                    ? widget.belumDidataTerakhir
                    : existing.jumlahBelumDidata)
                ?.toString() ??
            '0';
        _catatanController.text = existing?.catatan ?? '';
        _existingFoto = List.of(existing?.foto ?? const []);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showSnack('Gagal memuat laporan: $e', error: true);
    }
  }

  Future<void> _pickTanggal() async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _tanggal,
      firstDate: DateTime(today.year - 1),
      lastDate: today,
    );
    if (picked == null || picked == _tanggal) return;
    if (_newFoto.isNotEmpty) {
      final ok = await _confirm(
        'Ganti tanggal?',
        'Foto baru yang belum disimpan akan dibuang.',
      );
      if (!ok) return;
    }
    setState(() {
      _tanggal = picked;
      _newFoto.clear();
    });
    await _loadExisting();
  }

  bool get _usesDesktopPicker =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux);

  Future<void> _addFoto(ImageSource source) async {
    try {
      if (_usesDesktopPicker) {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.image,
          allowMultiple: true,
          withData: true,
        );
        if (result == null) return;
        setState(() {
          for (final f in result.files) {
            if (f.bytes != null) {
              _newFoto.add(_PickedFoto(f.bytes!, _ext(f.name)));
            }
          }
        });
        return;
      }

      if (source == ImageSource.camera) {
        // Kamera terbuka lagi setelah tiap jepretan agar bisa memotret
        // beberapa foto berturut-turut; tekan batal di kamera untuk selesai.
        while (mounted) {
          final image = await _picker.pickImage(
            source: ImageSource.camera,
            maxWidth: 1920,
            maxHeight: 1920,
            imageQuality: 85,
          );
          if (image == null) break;
          final bytes = await image.readAsBytes();
          if (!mounted) return;
          setState(() => _newFoto.add(_PickedFoto(bytes, _ext(image.name))));
        }
        return;
      }

      // Galeri: pilih banyak foto sekaligus.
      final images = await _picker.pickMultiImage(
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      for (final image in images) {
        final bytes = await image.readAsBytes();
        if (!mounted) return;
        setState(() => _newFoto.add(_PickedFoto(bytes, _ext(image.name))));
      }
    } catch (e) {
      _showSnack('Gagal mengambil foto: $e', error: true);
    }
  }

  String _ext(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'png';
    if (lower.endsWith('.webp')) return 'webp';
    if (lower.endsWith('.heic')) return 'heic';
    return 'jpg';
  }

  Future<void> _hapusFotoTersimpan(RevisitFoto foto) async {
    final ok = await _confirm('Hapus foto?', 'Foto akan dihapus permanen.');
    if (!ok) return;
    try {
      await _service.hapusFoto(foto);
      if (!mounted) return;
      setState(() {
        _existingFoto.removeWhere((f) => f.id == foto.id);
        _changed = true;
      });
    } catch (e) {
      _showSnack('Gagal menghapus foto: $e', error: true);
    }
  }

  Future<void> _simpan() async {
    final kurang = _belumDiisi;
    if (kurang.isNotEmpty) {
      setState(() => _cekWajib = true);
      _showSnack('Wajib diisi: ${kurang.join(', ')}', error: true);
      return;
    }
    final jumlahText = _jumlahController.text.trim();
    final belumText = _belumController.text.trim();
    final submitText = _submitController.text.trim();

    setState(() {
      _saving = true;
      _progress = 'Menyimpan laporan…';
    });
    try {
      final laporanId = await _service.simpanLaporan(
        kodeSls: widget.kodeSls,
        tanggal: _tanggal,
        hariKe: widget.hariKe ?? 0,
        status: _status!,
        jumlahDidata: jumlahText.isEmpty ? null : int.tryParse(jumlahText),
        jumlahBelumDidata: belumText.isEmpty ? null : int.tryParse(belumText),
        jumlahSubmit: submitText.isEmpty ? null : int.tryParse(submitText),
        catatan: _catatanController.text,
      );
      _changed = true;

      final total = _newFoto.length;
      for (var i = 0; i < total; i++) {
        if (!mounted) return;
        setState(() => _progress = 'Mengunggah foto ${i + 1}/$total…');
        final foto = _newFoto.first;
        await _service.uploadFoto(
          laporanId: laporanId,
          kodeSls: widget.kodeSls,
          tanggal: _tanggal,
          bytes: foto.bytes,
          extension: foto.extension,
        );
        _newFoto.removeAt(0);
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _progress = null;
      });
      // Foto yang gagal tetap di daftar agar bisa dicoba simpan lagi.
      await _loadExistingFotoOnly();
      _showSnack('Gagal menyimpan: $e', error: true);
    }
  }

  Future<void> _hapusLaporan() async {
    final existing = _existing;
    if (existing == null) return;
    final ok = await _confirm(
      'Hapus laporan?',
      'Laporan ${revisitDateLabel(_tanggal)} beserta semua fotonya akan '
          'dihapus permanen.',
    );
    if (!ok) return;
    setState(() {
      _saving = true;
      _progress = 'Menghapus…';
    });
    try {
      await _service.hapusLaporan(existing);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _progress = null;
      });
      _showSnack('Gagal menghapus: $e', error: true);
    }
  }

  /// Muat ulang foto tersimpan tanpa menimpa isian form.
  Future<void> _loadExistingFotoOnly() async {
    try {
      final list = await _service.fetchLaporan(
        dari: _tanggal.subtract(const Duration(days: 365)),
        sampai: DateTime.now(),
        kodeSls: widget.kodeSls,
        milikSaya: true,
        hariKe: widget.hariKe ?? 0,
      );
      if (!mounted || list.isEmpty) return;
      setState(() {
        _existing = list.first;
        _existingFoto = List.of(list.first.foto);
      });
    } catch (_) {}
  }

  Future<bool> _confirm(String title, String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ya'),
          ),
        ],
      ),
    );
    return result == true;
  }

  void _showSnack(String message, {bool error = false}) {
    if (!mounted) return;
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
      // Back sistem tidak membawa hasil; halaman induk tetap memuat ulang.
      canPop: !_saving,
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F6FB),
        appBar: AppBar(
          title: Text(
            '${_existing == null ? 'Laporan' : 'Ubah Laporan'}'
            '${widget.hariKe != null && widget.hariKe! > 0 ? ' · Hari ke-${widget.hariKe}' : ''}',
          ),
          backgroundColor: _primary,
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _saving
                ? null
                : () => Navigator.of(context).pop(_changed),
          ),
          actions: [
            if (_existing != null)
              IconButton(
                tooltip: 'Hapus laporan',
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: _saving ? null : _hapusLaporan,
              ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                children: [
                  _buildSlsHeader(),
                  const SizedBox(height: 10),
                  _card([
                    _buildFoto(),
                    const Divider(height: 24),
                    _label(
                      'Status kunjungan *',
                      trailing: _cekWajib && _status == null
                          ? const Text(
                              'wajib dipilih',
                              style: TextStyle(fontSize: 12, color: _merah),
                            )
                          : null,
                    ),
                    _buildStatus(),
                    const Divider(height: 24),
                    _angkaField(
                      'Jumlah Usaha/Keluarga Didata *',
                      _jumlahController,
                    ),
                    const SizedBox(height: 10),
                    _angkaField(
                      'Jumlah Usaha/Keluarga Submit *',
                      _submitController,
                    ),
                    const SizedBox(height: 10),
                    _angkaField(
                      'Jumlah Potensi Belum Didata *',
                      _belumController,
                      keterangan: widget.belumDidataTerakhir == null
                          ? 'Sisa yang belum didata di SLS ini'
                          : 'Laporan terakhir: ${widget.belumDidataTerakhir}. '
                                'Ubah bila sudah ada yang didata.',
                    ),
                    const SizedBox(height: 10),
                    _buildCatatan(),
                  ]),
                ],
              ),
        bottomNavigationBar: _loading
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _simpan,
                    style: FilledButton.styleFrom(
                      backgroundColor: _primary,
                      minimumSize: const Size.fromHeight(52),
                    ),
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
                    label: Text(_progress ?? 'Simpan Laporan'),
                  ),
                ),
              ),
      ),
    );
  }

  /// SLS + tanggal dalam satu kartu ringkas; tap tanggal untuk mengganti.
  Widget _buildSlsHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: _primary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.slsLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  [
                    widget.wilayahLabel,
                    widget.kodeSls,
                  ].where((e) => e.isNotEmpty).join(' · '),
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: Colors.white.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: _saving ? null : _pickTanggal,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.event_rounded,
                          size: 14,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          revisitDateLabel(_tanggal),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    if (_existing != null)
                      const Text(
                        'sudah ada laporan',
                        style: TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _label(String text, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: Color(0xFF334155),
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }

  Widget _buildStatus() {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final s in RevisitStatus.all)
          ChoiceChip(
            visualDensity: VisualDensity.compact,
            avatar: Icon(
              s.icon,
              size: 16,
              color: _status == s.value ? Colors.white : s.color,
            ),
            label: Text(s.label),
            selected: _status == s.value,
            selectedColor: s.color,
            labelStyle: TextStyle(
              color: _status == s.value ? Colors.white : s.color,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
            showCheckmark: false,
            backgroundColor: Colors.white,
            side: BorderSide(color: s.color.withValues(alpha: 0.5)),
            onSelected: _saving
                ? null
                : (_) => setState(() => _status = s.value),
          ),
      ],
    );
  }

  Widget _angkaField(
    String label,
    TextEditingController controller, {
    String? keterangan,
  }) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: Color(0xFF334155),
                ),
              ),
              if (keterangan != null)
                Text(
                  keterangan,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF64748B),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 96,
          child: TextField(
            controller: controller,
            enabled: !_saving,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) {
              if (_cekWajib) setState(() {});
            },
            // Ketuk = pilih semua, supaya angka lama langsung tertimpa.
            onTap: () => controller.selection = TextSelection(
              baseOffset: 0,
              extentOffset: controller.text.length,
            ),
            decoration: InputDecoration(
              hintText: 'isi angka',
              isDense: true,
              border: const OutlineInputBorder(),
              enabledBorder: _cekWajib && _kosong(controller)
                  ? const OutlineInputBorder(
                      borderSide: BorderSide(color: _merah, width: 1.5),
                    )
                  : null,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCatatan() {
    return TextField(
      controller: _catatanController,
      enabled: !_saving,
      minLines: 2,
      maxLines: 5,
      onChanged: (_) {
        if (_cekWajib) setState(() {});
      },
      decoration: InputDecoration(
        labelText: 'Catatan / temuan *',
        hintText: 'mis. 3 usaha baru, 1 usaha tutup, pemilik tidak di tempat',
        isDense: true,
        border: const OutlineInputBorder(),
        errorText: _cekWajib && _kosong(_catatanController)
            ? 'Catatan wajib diisi'
            : null,
      ),
    );
  }

  Widget _buildFoto() {
    const size = 84.0;
    final jumlah = _existingFoto.length + _newFoto.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(
          'Foto kunjungan *${jumlah > 0 ? ' ($jumlah)' : ''}',
          trailing: jumlah == 0
              ? Text(
                  'minimal 1',
                  style: TextStyle(
                    fontSize: 12,
                    color: _cekWajib ? _merah : const Color(0xFFB45309),
                    fontWeight: _cekWajib ? FontWeight.w700 : null,
                  ),
                )
              : null,
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final foto in _existingFoto)
              _fotoTile(
                RevisitFotoThumb(foto: foto, size: size),
                onRemove: _saving ? null : () => _hapusFotoTersimpan(foto),
              ),
            for (final foto in _newFoto)
              _fotoTile(
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(
                    foto.bytes,
                    width: size,
                    height: size,
                    fit: BoxFit.cover,
                  ),
                ),
                badge: 'baru',
                onRemove: _saving
                    ? null
                    : () => setState(() => _newFoto.remove(foto)),
              ),
            if (!_usesDesktopPicker)
              _addTile(
                size,
                Icons.photo_camera_rounded,
                'Kamera',
                () => _addFoto(ImageSource.camera),
              ),
            _addTile(
              size,
              Icons.add_photo_alternate_rounded,
              _usesDesktopPicker ? 'Pilih foto' : 'Galeri',
              () => _addFoto(ImageSource.gallery),
            ),
          ],
        ),
      ],
    );
  }

  Widget _addTile(
    double size,
    IconData icon,
    String label,
    VoidCallback onTap,
  ) {
    return Material(
      color: const Color(0xFFE8F1FB),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _saving ? null : onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: _primary),
              const SizedBox(height: 4),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  color: _primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fotoTile(Widget image, {VoidCallback? onRemove, String? badge}) {
    return Stack(
      children: [
        image,
        if (badge != null)
          Positioned(
            left: 4,
            bottom: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _primary,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                badge,
                style: const TextStyle(color: Colors.white, fontSize: 10),
              ),
            ),
          ),
        if (onRemove != null)
          Positioned(
            right: 2,
            top: 2,
            child: InkWell(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ),
          ),
      ],
    );
  }
}
