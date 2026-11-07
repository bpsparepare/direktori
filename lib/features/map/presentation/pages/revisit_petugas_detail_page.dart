import 'package:flutter/material.dart';

import '../../data/models/revisit_models.dart';
import '../../data/services/revisit_service.dart';
import '../widgets/revisit_widgets.dart';
import 'revisit_laporan_edit_dialog.dart';
import 'revisit_page.dart';

/// Detail progres satu petugas revisit (dibuka admin dari Rekap Harian):
/// ringkasan, grafik progres, progres tiap SLS alokasi, dan laporan pada
/// tanggal terpilih (tap batang grafik untuk ganti tanggal).
class RevisitPetugasDetailPage extends StatefulWidget {
  final RevisitPetugas petugas;
  final DateTime tanggal;

  const RevisitPetugasDetailPage({
    super.key,
    required this.petugas,
    required this.tanggal,
  });

  @override
  State<RevisitPetugasDetailPage> createState() =>
      _RevisitPetugasDetailPageState();
}

class _RevisitPetugasDetailPageState extends State<RevisitPetugasDetailPage> {
  final RevisitService _service = RevisitService();

  late DateTime _tanggal = DateTime(
    widget.tanggal.year,
    widget.tanggal.month,
    widget.tanggal.day,
  );
  bool _loading = true;
  String? _error;
  List<RevisitTugas> _sls = [];
  List<RevisitProgresHari> _progres = [];
  List<RevisitLaporan> _laporan = [];
  bool _loadingLaporan = false;

  String get _id => widget.petugas.petugasId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _sls.isEmpty && _progres.isEmpty;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _service.fetchTugasSaya(petugasId: _id),
        _service.fetchProgres(petugasId: _id),
        _service.fetchLaporan(dari: _tanggal, sampai: _tanggal, petugasId: _id),
      ]);
      if (!mounted) return;
      setState(() {
        _sls = results[0] as List<RevisitTugas>;
        _progres = results[1] as List<RevisitProgresHari>;
        _laporan = results[2] as List<RevisitLaporan>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _gantiTanggal(DateTime d) async {
    final today = DateTime.now();
    if (d.isAfter(DateTime(today.year, today.month, today.day))) return;
    setState(() {
      _tanggal = d;
      _loadingLaporan = true;
    });
    try {
      final laporan = await _service.fetchLaporan(
        dari: d,
        sampai: d,
        petugasId: _id,
      );
      if (!mounted) return;
      setState(() {
        _laporan = laporan;
        _loadingLaporan = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingLaporan = false);
    }
  }

  /// Detail satu jadwal: semua laporan petugas ini untuk SLS + hari ke-
  /// tersebut (tanpa memilih tanggal), lengkap dengan catatan & foto.
  Future<void> _lihatJadwal(RevisitTugas t) async {
    final hari = t.hariKe == null ? 'Tanpa hari' : 'Hari ke-${t.hariKe}';
    final laporan = _service.fetchLaporan(
      dari: DateTime(2026, 1, 1),
      sampai: DateTime(2027, 12, 31),
      petugasId: _id,
      kodeSls: t.kodeSls,
      hariKe: t.hariKe ?? 0,
    );
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: revisitBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheet) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (_, scroll) => FutureBuilder<List<RevisitLaporan>>(
          future: laporan,
          builder: (_, snap) {
            final isi = snap.data ?? const <RevisitLaporan>[];
            return ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  t.slsLabel,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                Text(
                  [
                    revisitWilayahLabel(t.nmDesa, t.nmKec),
                    hari,
                    widget.petugas.nama,
                  ].where((e) => e.isNotEmpty).join(' · '),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 12),
                if (snap.connectionState != ConnectionState.done)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (snap.hasError)
                  RevisitEmptyView(message: 'Gagal memuat: ${snap.error}')
                else if (isi.isEmpty)
                  const RevisitEmptyView(
                    message: 'Belum ada laporan untuk jadwal ini.',
                  )
                else
                  for (final l in isi) ...[
                    RevisitLaporanCard(
                      laporan: l,
                      showTanggal: true,
                      onEdit: () {
                        Navigator.pop(sheet);
                        _edit(l);
                      },
                      onDelete: () {
                        Navigator.pop(sheet);
                        _hapus(l);
                      },
                    ),
                    const SizedBox(height: 10),
                  ],
              ],
            );
          },
        ),
      ),
    );
  }

  /// Admin: edit progres laporan, lalu muat ulang progres & ringkasan.
  Future<void> _edit(RevisitLaporan l) async {
    final ok = await showRevisitLaporanEditDialog(context, l);
    if (!ok || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Progres diperbarui.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    await _load();
  }

  /// Admin: edit progres dari list per jadwal; laporan jadwal (SLS + hari
  /// ke- + petugas) diambil dulu karena tile hanya memuat ringkasannya.
  Future<void> _editJadwal(RevisitTugas t) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final laporan = await _service.fetchLaporan(
        dari: DateTime(2026, 1, 1),
        sampai: DateTime(2027, 12, 31),
        petugasId: _id,
        kodeSls: t.kodeSls,
        hariKe: t.hariKe ?? 0,
      );
      if (!mounted) return;
      if (laporan.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Jadwal ini belum punya laporan untuk diedit.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      await _edit(laporan.first);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Gagal memuat laporan: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Admin: hapus satu jadwal alokasi (SLS + hari ke-) milik petugas ini
  /// saja; petugas lain pada SLS & hari yang sama tidak tersentuh.
  Future<void> _hapusJadwal(RevisitTugas t) async {
    final hari = t.hariKe == null ? 'tanpa hari' : 'Hari ke-${t.hariKe}';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus jadwal?'),
        content: Text(
          '${t.slsLabel} · $hari\n'
          'Jadwal ini dilepas dari ${widget.petugas.nama}.'
          '${t.sudahDikunjungi ? '\n\nJadwal ini sudah dilaporkan. Laporannya '
                    'tetap tersimpan (bisa dihapus terpisah).' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      // Hari wajib dikirim (0 = tanpa hari); null akan melepas semua hari.
      await _service.setAlokasi(
        [t.kodeSls],
        _id,
        hariKe: t.hariKe ?? 0,
        lepasPetugas: true,
      );
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Jadwal dihapus.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      _load();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Gagal menghapus jadwal: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Admin: hapus laporan (beserta fotonya di Drive) setelah konfirmasi.
  Future<void> _hapus(RevisitLaporan l) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus laporan?'),
        content: Text(
          '${l.slsLabel} · ${revisitDateLabel(l.tanggal)}'
          '${l.hariKe == null ? '' : ' · Hari ke-${l.hariKe}'}\n'
          '${l.foto.isEmpty ? 'Tanpa foto.' : '${l.foto.length} foto di Drive ikut dihapus.'}'
          '\n\nLaporan yang dihapus tidak bisa dikembalikan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _service.hapusLaporan(l);
      if (!mounted) return;
      setState(() => _laporan.removeWhere((x) => x.id == l.id));
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Laporan dihapus.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      _load(); // perbarui progres & ringkasan
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Gagal menghapus: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.petugas;
    return Scaffold(
      backgroundColor: revisitBackground,
      appBar: AppBar(
        title: Text(p.nama),
        backgroundColor: revisitPrimary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Muat ulang',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? RevisitErrorView(error: _error!, onRetry: _load)
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  _header(),
                  const SizedBox(height: 12),
                  RevisitProgresCard(
                    progres: _progres,
                    tanggal: _tanggal,
                    onSelect: _gantiTanggal,
                  ),
                  const SizedBox(height: 16),
                  _judul(
                    'Progres per jadwal',
                    '${_sls.where((t) => t.sudahDikunjungi).length}'
                        '/${_sls.length} jadwal dilaporkan'
                        ' · ${_slsUnik.length} SLS',
                  ),
                  if (_sls.isEmpty)
                    const RevisitEmptyView(message: 'Belum ada SLS alokasi.')
                  else
                    for (final t in _sls) ...[
                      _slsTile(t),
                      const SizedBox(height: 8),
                    ],
                  const SizedBox(height: 8),
                  _judul(
                    'Laporan ${revisitDateLabel(_tanggal, withDay: true)}',
                    _laporan.isEmpty
                        ? 'belum ada laporan'
                        : '${_laporan.length} SLS · '
                              '${revisitTotalDidata(_laporan)} didata · '
                              '${revisitTotalSubmit(_laporan)} submit',
                  ),
                  if (_loadingLaporan)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_laporan.isEmpty)
                    const RevisitEmptyView(
                      message: 'Tidak ada laporan pada tanggal ini.',
                    )
                  else
                    for (final l in _laporan) ...[
                      RevisitLaporanCard(
                        laporan: l,
                        onEdit: () => _edit(l),
                        onDelete: () => _hapus(l),
                      ),
                      const SizedBox(height: 10),
                    ],
                ],
              ),
            ),
    );
  }

  /// Satu SLS bisa punya beberapa baris jadwal; ringkasan pakai SLS unik.
  Map<String, RevisitTugas> get _slsUnik => {
    for (final t in _sls) t.kodeSls: t,
  };

  Widget _header() {
    final p = widget.petugas;
    final unik = _slsUnik.values;
    final dikunjungi = unik.where((t) => t.jumlahLaporan > 0).length;
    final selesai = unik.where((t) => t.statusTerakhir == 'selesai').length;
    return RevisitHeaderCard(
      title: p.nama,
      subtitle: [
        revisitRoleLabel(p.role),
        if (p.tim.isNotEmpty) revisitTimLabel(p.tim),
        if (p.email.isNotEmpty) p.email,
      ].join(' · '),
      stats: [
        ('${_slsUnik.length}', 'SLS alokasi'),
        ('$dikunjungi', 'SLS dikunjungi'),
        ('$selesai', 'SLS selesai'),
      ],
    );
  }

  Widget _judul(String title, String sub) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: revisitPrimary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              sub,
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
          ),
        ],
      ),
    );
  }

  TextSpan _angka(String v, Color c) => TextSpan(
    text: v,
    style: TextStyle(fontWeight: FontWeight.w800, color: c),
  );

  Widget _slsTile(RevisitTugas t) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _lihatJadwal(t),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.slsLabel,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          [
                            revisitWilayahLabel(t.nmDesa, t.nmKec),
                            if (t.hariKe != null) 'Hari ke-${t.hariKe}',
                          ].where((e) => e.isNotEmpty).join(' · '),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Status laporan JADWAL ini, bukan status SLS.
                  RevisitStatusBadge(status: t.statusHari),
                  if (t.sudahDikunjungi)
                    IconButton(
                      tooltip: 'Edit progres jadwal ini',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(
                        Icons.edit_outlined,
                        color: revisitPrimary,
                      ),
                      onPressed: () => _editJadwal(t),
                    ),
                  IconButton(
                    tooltip: 'Hapus jadwal ini',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      color: Colors.red,
                    ),
                    onPressed: () => _hapusJadwal(t),
                  ),
                ],
              ),
              if (t.sudahDikunjungi) ...[
                const SizedBox(height: 8),
                Text.rich(
                  TextSpan(
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF475569),
                    ),
                    children: [
                      _angka('${t.didataHari ?? 0}', revisitWarnaDidata),
                      const TextSpan(text: ' didata · '),
                      _angka('${t.submitHari ?? 0}', revisitWarnaSubmit),
                      const TextSpan(text: ' submit'),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'dilapor ${t.tanggalHari == null ? '-' : revisitDateLabel(t.tanggalHari!)}'
                  ' · SLS ini total ${t.jumlahLaporan} laporan'
                  ', ${t.totalDidata} didata, sisa ${t.belumDidata ?? 0}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ] else ...[
                const SizedBox(height: 6),
                Text(
                  t.jumlahLaporan > 0
                      ? 'Jadwal ini belum dilaporkan · SLS sudah punya '
                            '${t.jumlahLaporan} laporan dari jadwal lain'
                      : 'Belum ada laporan',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFFB45309),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
