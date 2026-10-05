import 'package:flutter/material.dart';

import '../../data/models/revisit_models.dart';
import '../../data/services/revisit_service.dart';
import '../widgets/revisit_widgets.dart';
import 'revisit_admin_tabs.dart';
import 'revisit_laporan_form_page.dart';
import 'revisit_reject_tab.dart';

const Color revisitPrimary = Color(0xFF0F4C81);
const Color revisitBackground = Color(0xFFF3F6FB);

/// Menu "Revisit": kunjungan ulang SLS oleh tim khusus.
/// - Admin: Rekap (kumulatif per petugas/tim + grafik hari ke-) & Alokasi.
/// - Petugas revisit: Tugas Saya (SLS alokasi) & Riwayat laporan sendiri.
class RevisitPage extends StatefulWidget {
  const RevisitPage({super.key});

  @override
  State<RevisitPage> createState() => _RevisitPageState();
}

class _RevisitPageState extends State<RevisitPage> {
  final RevisitService _service = RevisitService();
  RevisitContext? _context;

  @override
  void initState() {
    super.initState();
    _service.fetchContext().then((ctx) {
      if (mounted) setState(() => _context = ctx);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ctx = _context;
    if (ctx == null) {
      return const Scaffold(
        backgroundColor: revisitBackground,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final tabs = <(Tab, Widget)>[
      if (ctx.isAdmin) ...[
        (
          const Tab(icon: Icon(Icons.insights_rounded), text: 'Rekap'),
          const RevisitRekapTab(),
        ),
        (
          const Tab(icon: Icon(Icons.assignment_ind_rounded), text: 'Alokasi'),
          const RevisitAlokasiTab(),
        ),
      ],
      if (ctx.isRevisit) ...[
        (
          const Tab(icon: Icon(Icons.checklist_rounded), text: 'Tugas Saya'),
          const _TugasSayaTab(),
        ),
        (
          const Tab(icon: Icon(Icons.history_rounded), text: 'Riwayat'),
          const RevisitRiwayatView(),
        ),
      ],
      if (ctx.canOpen)
        (
          const Tab(icon: Icon(Icons.block_rounded), text: 'Reject'),
          RevisitRejectTab(isAdmin: ctx.isAdmin),
        ),
    ];

    if (tabs.isEmpty) {
      return Scaffold(
        backgroundColor: revisitBackground,
        appBar: _appBar(),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              'Anda belum masuk tim revisit. Hubungi admin untuk alokasi SLS.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        backgroundColor: revisitBackground,
        appBar: _appBar(
          bottom: TabBar(
            isScrollable: tabs.length > 3,
            tabAlignment: tabs.length > 3 ? TabAlignment.start : null,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [for (final t in tabs) t.$1],
          ),
        ),
        body: TabBarView(children: [for (final t in tabs) t.$2]),
      ),
    );
  }

  AppBar _appBar({PreferredSizeWidget? bottom}) {
    return AppBar(
      title: const Text('Revisit'),
      backgroundColor: revisitPrimary,
      foregroundColor: Colors.white,
      bottom: bottom,
    );
  }
}

String revisitWilayahLabel(String nmDesa, String nmKec) =>
    [nmDesa, nmKec].where((e) => e.isNotEmpty).join(', ');

Future<bool> openRevisitForm(
  BuildContext context, {
  required String kodeSls,
  required String slsLabel,
  required String wilayahLabel,
  DateTime? tanggal,
  int? hariKe,
  int? belumDidataTerakhir,
}) async {
  final result = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => RevisitLaporanFormPage(
        kodeSls: kodeSls,
        slsLabel: slsLabel,
        wilayahLabel: wilayahLabel,
        tanggal: tanggal,
        hariKe: hariKe,
        belumDidataTerakhir: belumDidataTerakhir,
      ),
    ),
  );
  return result == true;
}

// ── Tugas Saya ───────────────────────────────────────────────────────────────

class _TugasSayaTab extends StatefulWidget {
  const _TugasSayaTab();

  @override
  State<_TugasSayaTab> createState() => _TugasSayaTabState();
}

class _TugasSayaTabState extends State<_TugasSayaTab>
    with AutomaticKeepAliveClientMixin {
  final RevisitService _service = RevisitService();
  final TextEditingController _search = TextEditingController();

  bool _loading = true;
  String? _error;
  String _query = '';
  List<RevisitTugas> _tugas = [];

  /// Laporan hari ini (kode SLS yang sudah dilapor + total didata).
  List<RevisitLaporan> _laporanHariIni = [];
  List<RevisitProgresHari> _progres = [];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _tugas.isEmpty;
      _error = null;
    });
    try {
      final today = DateTime.now();
      final results = await Future.wait([
        _service.fetchTugasSaya(),
        _service.fetchLaporan(dari: today, sampai: today, milikSaya: true),
        _service.fetchProgres(),
      ]);
      if (!mounted) return;
      setState(() {
        _tugas = results[0] as List<RevisitTugas>;
        _laporanHariIni = results[1] as List<RevisitLaporan>;
        _progres = results[2] as List<RevisitProgresHari>;
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

  List<RevisitTugas> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _tugas;
    return _tugas
        .where(
          (t) => [
            t.slsLabel,
            t.nmDesa,
            t.nmKec,
            t.kodeSls,
          ].join(' ').toLowerCase().contains(q),
        )
        .toList();
  }

  Future<void> _open(RevisitTugas t) async {
    await openRevisitForm(
      context,
      kodeSls: t.kodeSls,
      slsLabel: t.slsLabel,
      wilayahLabel: revisitWilayahLabel(t.nmDesa, t.nmKec),
      hariKe: t.hariKe ?? 0,
      tanggal: t.tanggalHari,
      belumDidataTerakhir: t.belumDidata,
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return RevisitErrorView(error: _error!, onRetry: _load);

    final items = _filtered;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _header(),
          const SizedBox(height: 12),
          RevisitProgresCard(progres: _progres, tanggal: DateTime.now()),
          const SizedBox(height: 12),
          RevisitSearchField(
            controller: _search,
            hint: 'Cari SLS / desa / kecamatan',
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: 12),
          if (_tugas.isEmpty)
            const RevisitEmptyView(
              message: 'Belum ada SLS yang dialokasikan kepada Anda.',
            )
          else
            // Dikelompokkan per "hari ke-" (urutan dari server).
            for (final hari in {for (final t in items) t.hariKe}) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                child: Text(
                  '${hari == null ? 'Hari belum ditentukan' : 'Hari ke-$hari'}'
                  ' · ${items.where((t) => t.hariKe == hari).length} SLS'
                  ' · ${items.where((t) => t.hariKe == hari && t.sudahDikunjungi).length} sudah',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: revisitPrimary,
                  ),
                ),
              ),
              for (final t in items.where((t) => t.hariKe == hari)) ...[
                _tugasCard(t),
                const SizedBox(height: 10),
              ],
            ],
        ],
      ),
    );
  }

  Widget _header() {
    // Satu SLS bisa dijadwalkan beberapa hari; hitung SLS-nya sekali saja.
    final kodeUnik = <String, RevisitTugas>{
      for (final t in _tugas) t.kodeSls: t,
    };
    final jadwalSudah = _tugas.where((t) => t.sudahDikunjungi).length;
    return RevisitHeaderCard(
      title: 'Tugas Revisit',
      subtitle: revisitDateLabel(DateTime.now(), withDay: true),
      stats: [
        ('$jadwalSudah/${_tugas.length}', 'jadwal sudah dilapor'),
        ('${kodeUnik.length}', 'SLS alokasi'),
        ('${revisitTotalDidata(_laporanHariIni)}', 'didata hari ini'),
        ('${revisitTotalSubmit(_laporanHariIni)}', 'submit hari ini'),
        (
          '${kodeUnik.values.fold<int>(0, (s, t) => s + (t.belumDidata ?? 0))}',
          'potensi belum didata',
        ),
        (
          '${kodeUnik.values.where((t) => t.statusTerakhir == 'selesai').length}',
          'SLS selesai',
        ),
      ],
    );
  }

  Widget _tugasCard(RevisitTugas t) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _open(t),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.slsLabel,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      revisitWilayahLabel(t.nmDesa, t.nmKec),
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        // Status laporan JADWAL ini (bukan status SLS).
                        RevisitStatusBadge(status: t.statusHari),
                        if (t.tanggalHari != null)
                          Text(
                            'dilapor ${revisitDateLabel(t.tanggalHari!)}'
                            ' · ${t.didataHari ?? 0} didata'
                            ' · ${t.submitHari ?? 0} submit',
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                    if (t.jumlahLaporan > 0) ...[
                      const SizedBox(height: 8),
                      RevisitSlsAngka(tugas: t),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              t.sudahDikunjungi
                  ? OutlinedButton(
                      onPressed: () => _open(t),
                      child: const Text('Ubah'),
                    )
                  : FilledButton.tonal(
                      onPressed: () => _open(t),
                      child: const Text('Lapor'),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Riwayat laporan ──────────────────────────────────────────────────────────

/// Riwayat laporan 30 hari terakhir, dikelompokkan per tanggal. Tanpa
/// [petugasId] = milik pengguna sendiri (atau semua bila admin).
class RevisitRiwayatView extends StatefulWidget {
  final String? petugasId;
  final bool showPetugas;
  final bool canEdit;

  const RevisitRiwayatView({
    super.key,
    this.petugasId,
    this.showPetugas = false,
    this.canEdit = true,
  });

  @override
  State<RevisitRiwayatView> createState() => _RevisitRiwayatViewState();
}

class _RevisitRiwayatViewState extends State<RevisitRiwayatView>
    with AutomaticKeepAliveClientMixin {
  static const int _hari = 30;

  final RevisitService _service = RevisitService();
  bool _loading = true;
  String? _error;
  List<RevisitLaporan> _items = [];
  List<RevisitProgresHari> _progres = [];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _items.isEmpty;
      _error = null;
    });
    try {
      final today = DateTime.now();
      final results = await Future.wait([
        _service.fetchLaporan(
          dari: today.subtract(const Duration(days: _hari)),
          sampai: today,
          petugasId: widget.petugasId,
        ),
        _service.fetchProgres(petugasId: widget.petugasId),
      ]);
      if (!mounted) return;
      setState(() {
        _items = results[0] as List<RevisitLaporan>;
        _progres = results[1] as List<RevisitProgresHari>;
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

  Future<void> _edit(RevisitLaporan l) async {
    await openRevisitForm(
      context,
      kodeSls: l.kodeSls,
      slsLabel: l.slsLabel,
      wilayahLabel: revisitWilayahLabel(l.nmDesa, l.nmKec),
      tanggal: l.tanggal,
      hariKe: l.hariKe ?? 0,
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return RevisitErrorView(error: _error!, onRetry: _load);

    final byDate = <DateTime, List<RevisitLaporan>>{};
    for (final l in _items) {
      byDate.putIfAbsent(l.tanggal, () => []).add(l);
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          RevisitProgresCard(progres: _progres, tanggal: DateTime.now()),
          const SizedBox(height: 12),
          Text(
            'Laporan $_hari hari terakhir · ${_items.length} laporan',
            style: const TextStyle(color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 8),
          if (_items.isEmpty)
            const RevisitEmptyView(message: 'Belum ada laporan.')
          else
            for (final entry in byDate.entries) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
                child: Text(
                  '${revisitDateLabel(entry.key, withDay: true)}'
                  ' · ${entry.value.length} SLS'
                  ' · ${revisitTotalDidata(entry.value)} didata',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: revisitPrimary,
                  ),
                ),
              ),
              for (final l in entry.value) ...[
                RevisitLaporanCard(
                  laporan: l,
                  showPetugas: widget.showPetugas,
                  onTap: widget.canEdit ? () => _edit(l) : null,
                ),
                const SizedBox(height: 10),
              ],
            ],
        ],
      ),
    );
  }
}

// ── Komponen umum ────────────────────────────────────────────────────────────

class RevisitHeaderCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<(String, String)> stats;
  final Widget? trailing;

  const RevisitHeaderCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.stats,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F4C81), Color(0xFF2D77D0)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (value, label) in stats)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        value,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class RevisitSearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  const RevisitSearchField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.clear_rounded),
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              ),
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class RevisitEmptyView extends StatelessWidget {
  final String message;

  const RevisitEmptyView({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          const Icon(Icons.inbox_rounded, size: 48, color: Color(0xFF94A3B8)),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }
}

class RevisitErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;

  const RevisitErrorView({
    super.key,
    required this.error,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 40),
            const SizedBox(height: 8),
            Text(error, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Coba lagi')),
          ],
        ),
      ),
    );
  }
}
