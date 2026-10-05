import 'package:flutter/material.dart';

import '../../data/models/revisit_models.dart';
import '../../data/services/revisit_service.dart';
import '../widgets/revisit_widgets.dart';
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
                      RevisitLaporanCard(laporan: l),
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
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
            ],
          ),
          if (t.sudahDikunjungi) ...[
            const SizedBox(height: 8),
            Text.rich(
              TextSpan(
                style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
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
              style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
            ),
          ] else ...[
            const SizedBox(height: 6),
            Text(
              t.jumlahLaporan > 0
                  ? 'Jadwal ini belum dilaporkan · SLS sudah punya '
                        '${t.jumlahLaporan} laporan dari jadwal lain'
                  : 'Belum ada laporan',
              style: const TextStyle(fontSize: 11, color: Color(0xFFB45309)),
            ),
          ],
        ],
      ),
    );
  }
}
