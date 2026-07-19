import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_file/open_file.dart';

import '../../data/services/fasih_rekap_service.dart';
import '../../data/services/groundcheck_supabase_service.dart';
import '../../data/services/lembar_kerja_export_service.dart';

/// Lembar Kerja: progres pendataan per petugas dengan detail per SLS/sub-SLS.
///
/// - admin    : tabel semua petugas -> tabel wilayah (SLS/sub-SLS) petugas
/// - pengawas : tabel petugas binaan -> tabel wilayah petugas
/// - pendata  : langsung melihat tabel wilayah tugasnya sendiri
class LembarKerjaPage extends StatefulWidget {
  const LembarKerjaPage({super.key});

  @override
  State<LembarKerjaPage> createState() => _LembarKerjaPageState();
}

class _LembarKerjaPageState extends State<LembarKerjaPage> {
  final GroundcheckSupabaseService _profileService =
      GroundcheckSupabaseService();
  final FasihRekapService _rekapService = FasihRekapService();
  final LembarKerjaExportService _exportService = LembarKerjaExportService();
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  bool _isExporting = false;
  String? _error;
  Se2026UserProfile? _profile;
  FasihRekapPayload _payload = FasihRekapPayload.empty();
  FasihRekapRow? _selectedPetugas;

  /// Target prelist per wilayah (key: id wilayah 16 digit) dan
  /// agregatnya per petugas (key: id petugas/ppl_id).
  Map<String, int> _prelistByWilayah = {};
  Map<String, int> _prelistByPetugas = {};
  bool _prelistLoaded = false;

  /// Distribusi kode_bang (submitted) per wilayah 16 digit dan per petugas
  /// (ppl_id), dibangun langsung dari RPC.
  Map<String, Map<String, int>> _kodeBangByWilayah = {};
  Map<String, Map<String, int>> _kodeBangByPetugas = {};
  bool _kodeBangLoaded = false;

  /// Tab tabel: 0 = Progres, 1 = Jenis Bangunan (kode_bang).
  int _tableTab = 0;

  /// Filter tabel berdasarkan kategori sebaran (indeks _tiers). null = semua.
  int? _selectedTier;

  /// Data tab Pengawas (khusus admin, dimuat saat tab dibuka).
  FasihRekapPayload? _pengawasPayload;
  bool _pengawasLoading = false;
  Map<String, int> _prelistByPengawas = {};

  /// State sort tabel. null = urutan default (per kode wilayah / dari server).
  int? _sortColumnIndex;
  bool _sortAscending = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String get _role => _profile?.role ?? '';

  bool get _isPetugasLevel =>
      (_role == 'admin' || _role == 'pengawas') && _selectedPetugas == null;

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final profile =
          _profile ?? await _profileService.fetchCurrentSe2026Profile();
      if (profile == null) {
        throw Exception('Profil petugas SE2026 tidak ditemukan.');
      }

      final payloadFuture = _fetchPayload(profile);
      final preFutures = <Future<void>>[];
      if (!_prelistLoaded) preFutures.add(_loadPrelistTargets(profile));
      if (!_kodeBangLoaded) preFutures.add(_loadKodeBang());
      if (preFutures.isNotEmpty) await Future.wait(preFutures);
      final payload = await payloadFuture;
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _payload = payload;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<FasihRekapPayload> _fetchPayload(Se2026UserProfile profile) {
    final search = _searchController.text;
    switch (profile.role) {
      case 'pendata':
        return _rekapService.fetchPendataWilayah(search: search, limit: 300);
      case 'pengawas':
        if (_selectedPetugas != null) {
          return _rekapService.fetchPengawasWilayahPetugas(
            petugasId: _selectedPetugas!.unitId,
            search: search,
            limit: 300,
          );
        }
        return _rekapService.fetchPengawasPetugas(
          search: search,
          limit: 150,
          sortBy: 'title',
          sortDir: 'asc',
        );
      case 'admin':
        if (_selectedPetugas != null) {
          return _rekapService.fetchAdminWilayahByPetugas(
            petugasId: _selectedPetugas!.unitId,
            search: search,
            limit: 300,
          );
        }
        return _rekapService.fetchAdminPetugas(
          search: search,
          limit: 300,
          sortBy: 'title',
          sortDir: 'asc',
        );
      default:
        return Future.value(FasihRekapPayload.empty());
    }
  }

  Future<void> _loadPrelistTargets(Se2026UserProfile profile) async {
    final records = await _rekapService.fetchPrelistTargets(
      pmlId: profile.role == 'pengawas' ? profile.petugasId : null,
      pplId: profile.role == 'pendata' ? profile.petugasId : null,
    );
    final byWilayah = <String, int>{};
    final byPetugas = <String, int>{};
    final byPengawas = <String, int>{};
    for (final record in records) {
      if (record.id.isNotEmpty) {
        byWilayah[record.id] = (byWilayah[record.id] ?? 0) + record.prelist;
      }
      if (record.pplId.isNotEmpty) {
        byPetugas[record.pplId] =
            (byPetugas[record.pplId] ?? 0) + record.prelist;
      }
      if (record.pmlId.isNotEmpty) {
        byPengawas[record.pmlId] =
            (byPengawas[record.pmlId] ?? 0) + record.prelist;
      }
    }
    _prelistByWilayah = byWilayah;
    _prelistByPetugas = byPetugas;
    _prelistByPengawas = byPengawas;
    _prelistLoaded = true;
  }

  /// Muat rekap per pengawas (untuk tab Pengawas, khusus admin).
  Future<void> _loadPengawas() async {
    if (_pengawasLoading) return;
    setState(() => _pengawasLoading = true);
    try {
      final payload = await _rekapService.fetchAdminPengawas(
        limit: 200,
        sortBy: 'title',
        sortDir: 'asc',
      );
      if (!mounted) return;
      setState(() {
        _pengawasPayload = payload;
        _pengawasLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _pengawasLoading = false);
    }
  }

  /// Jumlah APPROVED dari rincian status (alias mengandung APPROV).
  static int _approvedOf(Map<String, int> statusCounts) {
    var approved = 0;
    statusCounts.forEach((alias, count) {
      if (alias.toUpperCase().contains('APPROV')) approved += count;
    });
    return approved;
  }

  /// Approved+: semua status dijumlah KECUALI OPEN, DRAFT, dan
  /// SUBMITTED BY PENCACAH.
  static int _approvedPlusOf(Map<String, int> statusCounts) {
    var total = 0;
    statusCounts.forEach((alias, count) {
      final upper = alias.toUpperCase();
      final isOpen = upper.startsWith('OPEN');
      final isDraft = upper.startsWith('DRAFT');
      final isSubmitPencacah =
          upper.contains('SUBMIT') && upper.contains('PENCACAH');
      if (!isOpen && !isDraft && !isSubmitPencacah) total += count;
    });
    return total;
  }

  /// Muat distribusi kode_bang dari RPC lalu bangun agregat per wilayah dan
  /// per petugas langsung dari baris RPC (lengkap, tidak bergantung prelist).
  Future<void> _loadKodeBang() async {
    final rows = await _rekapService.fetchKodeBangByWilayah();
    final byWilayah = <String, Map<String, int>>{};
    final byPetugas = <String, Map<String, int>>{};
    for (final r in rows) {
      if (r.counts.isEmpty) continue;
      if (r.kodeWilayah.isNotEmpty) {
        final m = byWilayah.putIfAbsent(r.kodeWilayah, () => <String, int>{});
        r.counts.forEach((code, n) => m[code] = (m[code] ?? 0) + n);
      }
      if (r.pplId.isNotEmpty) {
        final m = byPetugas.putIfAbsent(r.pplId, () => <String, int>{});
        r.counts.forEach((code, n) => m[code] = (m[code] ?? 0) + n);
      }
    }
    _kodeBangByWilayah = byWilayah;
    _kodeBangByPetugas = byPetugas;
    _kodeBangLoaded = true;
  }

  /// Distribusi kode_bang untuk satu baris tabel sesuai level tampil.
  Map<String, int> _kodeBangForRow(FasihRekapRow row) {
    return _isPetugasLevel
        ? (_kodeBangByPetugas[row.unitId] ?? const {})
        : (_kodeBangByWilayah[row.unitId] ?? const {});
  }

  /// Target prelist untuk satu baris tabel sesuai level yang sedang tampil.
  int _targetOf(FasihRekapRow row) {
    return _isPetugasLevel
        ? (_prelistByPetugas[row.unitId] ?? 0)
        : (_prelistByWilayah[row.unitId] ?? 0);
  }

  /// Total target seluruh baris yang sedang tampil.
  int get _summaryTarget =>
      _payload.rows.fold(0, (sum, row) => sum + _targetOf(row));

  /// Kategori sebaran bertingkat (dievaluasi berurutan, ambil yang pertama
  /// terpenuhi). "Potensi" = submitted + draft.
  static const List<_Tier> _tiers = [
    _Tier(label: '> 300', sub: 'Submitted', color: Color(0xFF1B7A43)),
    _Tier(label: '> 270', sub: 'Submitted', color: Color(0xFF1D8F5A)),
    _Tier(
      label: '> 270 Potensi',
      sub: 'Submitted + Draft',
      color: Color(0xFF2D77D0),
    ),
    _Tier(
      label: '> 250 Potensi',
      sub: 'Submitted + Draft',
      color: Color(0xFFF59E0B),
    ),
    _Tier(label: 'Lainnya', sub: 'Di bawah ambang', color: Color(0xFF8895A7)),
  ];

  /// Tentukan indeks tier untuk satu baris.
  int _tierIndexOf(FasihRekapRow row) {
    final breakdown = _breakdownOf(
      row.statusCounts,
      row.totalAssignment,
      row.totalTerkirim,
    );
    final submitted = breakdown.submitted;
    final potensi = submitted + breakdown.draft;
    if (submitted > 300) return 0;
    if (submitted > 270) return 1;
    if (potensi > 270) return 2;
    if (potensi > 250) return 3;
    return 4;
  }

  /// Hitung jumlah baris per tier untuk baris yang sedang tampil.
  List<int> get _tierCounts {
    final counts = List<int>.filled(_tiers.length, 0);
    for (final row in _payload.rows) {
      counts[_tierIndexOf(row)]++;
    }
    return counts;
  }

  /// Baris yang ditampilkan tabel, sudah menerapkan filter kategori (bila ada).
  List<FasihRekapRow> get _filteredRows {
    if (_selectedTier == null) return _payload.rows;
    return _payload.rows
        .where((row) => _tierIndexOf(row) == _selectedTier)
        .toList();
  }

  void _toggleTierFilter(int index) {
    setState(() {
      _selectedTier = _selectedTier == index ? null : index;
      _resetSort();
    });
  }

  void _openPetugas(FasihRekapRow petugas) {
    setState(() {
      _selectedPetugas = petugas;
      _searchController.clear();
      _resetSort();
      _selectedTier = null;
      // Tab Pengawas hanya ada di level atas.
      if (_tableTab == 3) _tableTab = 0;
    });
    _loadData();
  }

  void _backToPetugasList() {
    setState(() {
      _selectedPetugas = null;
      _searchController.clear();
      _resetSort();
      _selectedTier = null;
    });
    _loadData();
  }

  void _resetSort() {
    _sortColumnIndex = null;
    _sortAscending = true;
  }

  void _onSort(int columnIndex, bool ascending) {
    setState(() {
      _sortColumnIndex = columnIndex;
      _sortAscending = ascending;
    });
  }

  // ---------------------------------------------------------------------
  // Export Excel: SEMUA wilayah (SLS/sub-SLS) untuk seluruh petugas dalam
  // scope pengguna, apa pun level yang sedang tampil.
  // ---------------------------------------------------------------------

  Future<void> _exportAllWilayah() async {
    if (_isExporting) return;
    final profile = _profile;
    if (profile == null) return;

    setState(() => _isExporting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final rows = await _collectAllWilayahRows(profile);
      if (rows.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Tidak ada wilayah untuk diekspor.')),
        );
        return;
      }
      final path = await _exportService.exportToFile(rows);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Berhasil mengekspor ${rows.length} wilayah.')),
      );
      await OpenFile.open(path);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Gagal mengekspor: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  /// Kumpulkan seluruh baris wilayah untuk semua petugas dalam scope pengguna.
  Future<List<LembarKerjaExportRow>> _collectAllWilayahRows(
    Se2026UserProfile profile,
  ) async {
    // Pastikan target prelist & distribusi kode_bang tersedia.
    if (!_prelistLoaded) {
      await _loadPrelistTargets(profile);
    }
    if (!_kodeBangLoaded) {
      await _loadKodeBang();
    }

    // Pendata: cukup wilayah tugasnya sendiri.
    if (profile.role == 'pendata') {
      final payload = await _rekapService.fetchPendataWilayah(limit: 500);
      return payload.rows
          .map((row) => _toExportRow(row, petugas: '(Saya)', email: ''))
          .toList();
    }

    // Admin & pengawas: ambil daftar petugas, lalu wilayah tiap petugas.
    final petugasPayload = profile.role == 'admin'
        ? await _rekapService.fetchAdminPetugas(limit: 500, sortBy: 'title')
        : await _rekapService.fetchPengawasPetugas(limit: 500, sortBy: 'title');

    final result = <LembarKerjaExportRow>[];
    for (final petugas in petugasPayload.rows) {
      // Lewati baris "tanpa petugas" (ppl_id null → unitId kosong); tidak bisa
      // di-drill per petugas dan string kosong tak valid sebagai UUID.
      if (petugas.unitId.trim().isEmpty) continue;
      final wilayahPayload = profile.role == 'admin'
          ? await _rekapService.fetchAdminWilayahByPetugas(
              petugasId: petugas.unitId,
              limit: 500,
            )
          : await _rekapService.fetchPengawasWilayahPetugas(
              petugasId: petugas.unitId,
              limit: 500,
            );
      for (final row in wilayahPayload.rows) {
        result.add(
          _toExportRow(
            row,
            petugas: petugas.title,
            email: petugas.subtitle == '-' ? '' : petugas.subtitle,
          ),
        );
      }
    }
    return result;
  }

  LembarKerjaExportRow _toExportRow(
    FasihRekapRow row, {
    required String petugas,
    required String email,
  }) {
    final breakdown = _breakdownOf(
      row.statusCounts,
      row.totalAssignment,
      row.totalTerkirim,
    );
    return LembarKerjaExportRow(
      petugas: petugas,
      petugasEmail: email,
      kodeWilayah: row.unitId,
      namaSls: row.title,
      kecDesa: row.subtitle == '-' ? '' : row.subtitle,
      target: _prelistByWilayah[row.unitId] ?? 0,
      total: row.totalAssignment,
      submitted: breakdown.submitted,
      draft: breakdown.draft,
      open: breakdown.open,
      kodeBang: _kodeBangByWilayah[row.unitId] ?? const {},
    );
  }

  // ---------------------------------------------------------------------
  // Hitungan status: submitted = semua status selain DRAFT dan OPEN.
  // ---------------------------------------------------------------------

  static bool _isOpenStatus(String status) =>
      status.trim().toUpperCase().startsWith('OPEN');

  static bool _isDraftStatus(String status) =>
      status.trim().toUpperCase().startsWith('DRAFT');

  /// Hitung open/draft/submitted dari rincian status sebuah unit.
  /// [totalAssignment] dan [totalTerkirim] dipakai sebagai fallback jika
  /// rincian status kosong.
  static _StatusBreakdown _breakdownOf(
    Map<String, int> statusCounts,
    int totalAssignment,
    int totalTerkirim,
  ) {
    if (statusCounts.isEmpty) {
      return _StatusBreakdown(
        open: totalAssignment - totalTerkirim,
        draft: 0,
        submitted: totalTerkirim,
      );
    }
    int open = 0;
    int draft = 0;
    int submitted = 0;
    statusCounts.forEach((status, count) {
      if (_isOpenStatus(status)) {
        open += count;
      } else if (_isDraftStatus(status)) {
        draft += count;
      } else {
        submitted += count;
      }
    });
    return _StatusBreakdown(open: open, draft: draft, submitted: submitted);
  }

  /// Breakdown gabungan seluruh payload (dipakai kartu ringkasan).
  _StatusBreakdown get _summaryBreakdown {
    final counts = <String, int>{};
    for (final alias in _payload.statusAliases) {
      counts[alias.alias] = (counts[alias.alias] ?? 0) + alias.total;
    }
    return _breakdownOf(
      counts,
      _payload.summary.totalAssignments,
      _payload.summary.totalTerkirim,
    );
  }

  String get _pageTitle {
    if (_role == 'pendata') return 'Lembar Kerja Saya';
    return _selectedPetugas == null
        ? 'Lembar Kerja Petugas'
        : 'Lembar Kerja: ${_selectedPetugas!.title}';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _selectedPetugas == null || _role == 'pendata',
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _selectedPetugas != null && _role != 'pendata') {
          _backToPetugasList();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F6FB),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0F4C81),
          foregroundColor: Colors.white,
          title: Text(_pageTitle, overflow: TextOverflow.ellipsis),
          leading: _selectedPetugas != null && _role != 'pendata'
              ? IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: _backToPetugasList,
                )
              : null,
          actions: [
            IconButton(
              tooltip: 'Export Excel (semua wilayah)',
              onPressed: _isExporting || _isLoading ? null : _exportAllWilayah,
              icon: _isExporting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.file_download_outlined),
            ),
          ],
        ),
        body: SafeArea(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? _buildErrorState()
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                    children: [
                      _buildSummaryCard(),
                      const SizedBox(height: 12),
                      _buildDistributionCard(),
                      const SizedBox(height: 12),
                      _buildSearchField(),
                      const SizedBox(height: 12),
                      _buildTableCard(),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 56, color: Colors.red[300]),
            const SizedBox(height: 12),
            Text(
              _error ?? 'Terjadi kesalahan.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.blueGrey[700]),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Coba Lagi'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard() {
    final summary = _payload.summary;
    final breakdown = _summaryBreakdown;
    final target = _summaryTarget;
    // Capaian dibandingkan terhadap target prelist; jika target belum diisi,
    // pakai total assignment sebagai pembanding.
    final percent = target > 0
        ? breakdown.submitted / target
        : (summary.totalAssignments == 0
              ? 0.0
              : breakdown.submitted / summary.totalAssignments);
    final unitLabel = _isPetugasLevel ? 'Petugas' : 'SLS/Sub-SLS';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F4C81), Color(0xFF2D77D0), Color(0xFF7AB6FF)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2D77D0).withValues(alpha: 0.25),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.assignment_turned_in_rounded,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _selectedPetugas?.title ??
                          (_role == 'pendata'
                              ? 'Progres Wilayah Tugas Anda'
                              : 'Progres Per Petugas'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      target > 0
                          ? '${summary.totalUnits} $unitLabel • '
                                '${breakdown.submitted} submitted dari target $target'
                          : '${summary.totalUnits} $unitLabel • '
                                '${breakdown.submitted}/${summary.totalAssignments} submitted',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${(percent * 100).toStringAsFixed(1)}%',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: percent.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: Colors.white.withValues(alpha: 0.25),
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFF7CFFB2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _buildSummaryStat('Target', target)),
              const SizedBox(width: 8),
              Expanded(
                child: _buildSummaryStat('Submitted', breakdown.submitted),
              ),
              const SizedBox(width: 8),
              Expanded(child: _buildSummaryStat('Draft', breakdown.draft)),
              const SizedBox(width: 8),
              Expanded(child: _buildSummaryStat('Open', breakdown.open)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryStat(String label, int value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            '$value',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDistributionCard() {
    final counts = _tierCounts;
    final unitLabel = _isPetugasLevel ? 'petugas' : 'SLS/sub-SLS';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sebaran Capaian $unitLabel',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            _selectedTier == null
                ? 'Ketuk kategori untuk memfilter tabel.'
                : 'Filter aktif: ${_tiers[_selectedTier!].label}. '
                      'Ketuk lagi untuk hapus.',
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
          const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (int i = 0; i < _tiers.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(child: _buildTierTile(i, _tiers[i], counts[i])),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTierTile(int index, _Tier tier, int value) {
    final selected = _selectedTier == index;
    return Material(
      color: selected
          ? tier.color.withValues(alpha: 0.18)
          : tier.color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _toggleTierFilter(index),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: tier.color.withValues(alpha: selected ? 0.9 : 0.22),
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Column(
            children: [
              Text(
                '$value',
                style: TextStyle(
                  color: tier.color,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                tier.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: tier.color,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Urutan kolom kode_bang. Bucket "tidak ditemukan" (kode_bang kosong) sudah
  /// dipecah RPC menjadi TD_USAHA & TD_KELUARGA berdasarkan jenis_prelist.
  static const List<String> _kodeBangOrder = [
    '1', '2', '3', '4', '5', '6', '7', '8', '9', 'TD_USAHA', 'TD_KELUARGA',
  ];

  /// Label singkat kode_bang untuk header kolom tabel.
  static const Map<String, String> _kodeBangShort = {
    '1': 'Khusus Usaha',
    '2': 'Campuran',
    '3': 'Tempat Tinggal',
    '4': 'Ibadah/Ormas',
    '5': 'Pemerintah',
    '6': 'Lainnya',
    '7': 'Virtual Office',
    '8': 'Panti/Lapas',
    '9': 'Non Respon',
    'TD_USAHA': 'Usaha Tdk Ditemukan',
    'TD_KELUARGA': 'Keluarga Tdk Ditemukan',
  };

  String _kodeBangColLabel(String code) {
    final short = _kodeBangShort[code] ?? (code.isEmpty ? 'Tdk Diketahui' : code);
    if (code.startsWith('TD')) return short;
    return '$code. $short';
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => _loadData(),
      decoration: InputDecoration(
        hintText: _isPetugasLevel
            ? 'Cari nama petugas...'
            : 'Cari nama SLS / desa / kecamatan...',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _searchController.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () {
                  _searchController.clear();
                  _loadData();
                },
              ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Tabel
  // ---------------------------------------------------------------------

  Widget _buildTableCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _tableTab == 3
                      ? 'Tabel Per Pengawas'
                      : _isPetugasLevel
                      ? 'Tabel Per Petugas'
                      : 'Tabel Per SLS/Sub-SLS',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _payload.rows.isEmpty ? null : _copyCurrentTable,
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Salin'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF0F4C81),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(_tableSubtitle(), style: TextStyle(color: Colors.grey[600], fontSize: 12)),
          const SizedBox(height: 12),
          _buildTableTabs(),
          const SizedBox(height: 12),
          if (_tableTab == 3)
            _buildPengawasTable()
          else if (_payload.rows.isEmpty)
            _buildEmptyState(
              _isPetugasLevel
                  ? 'Belum ada data petugas.'
                  : 'Belum ada wilayah tugas untuk ditampilkan.',
            )
          else if (_filteredRows.isEmpty)
            _buildEmptyState('Tidak ada baris pada kategori ini.')
          else if (_tableTab == 0)
            (_isPetugasLevel ? _buildPetugasTable() : _buildWilayahTable())
          else if (_tableTab == 1)
            _buildKodeBangTable()
          else
            _buildRekapTable(),
        ],
      ),
    );
  }

  /// Baris yang ditampilkan tabel aktif: terfilter + terurut sesuai sort.
  List<FasihRekapRow> _displayRows() {
    final rows = [..._filteredRows];
    if (_sortColumnIndex != null) {
      switch (_tableTab) {
        case 1:
          _sortRows(rows, (r) => _bangunanSortValue(r, _sortColumnIndex!));
          break;
        case 2:
          _sortRows(rows, (r) => _rekapSortValue(r, _sortColumnIndex!));
          break;
        default:
          _sortRows(
            rows,
            (r) => _isPetugasLevel
                ? _petugasSortValue(r, _sortColumnIndex!)
                : _wilayahSortValue(r, _sortColumnIndex!),
          );
      }
    } else if (!_isPetugasLevel) {
      rows.sort((a, b) => a.unitId.compareTo(b.unitId));
    }
    return rows;
  }

  /// Salin tabel yang sedang tampil ke clipboard sebagai TSV (siap tempel ke
  /// Excel/Sheets), mengikuti tab, level, filter, dan sort aktif.
  Future<void> _copyCurrentTable() async {
    final messenger = ScaffoldMessenger.of(context);
    final lines = <List<String>>[];

    String pct(int submitted, int target) =>
        target > 0 ? '${(submitted / target * 100).toStringAsFixed(2)}%' : '';

    // Tab Pengawas punya sumber baris sendiri.
    if (_tableTab == 3) {
      final pengawasRows = (_pengawasPayload?.rows ?? const <FasihRekapRow>[])
          .where((row) => row.unitId.trim().isNotEmpty)
          .toList();
      if (_sortColumnIndex != null) {
        _sortRows(
          pengawasRows,
          (row) => _pengawasSortValue(row, _sortColumnIndex!),
        );
      }
      lines.add([
        'No', 'Pengawas', 'Email', 'Target', 'Total', 'Submitted', 'Draft',
        'Open', 'Approved', 'Approved+', '%',
      ]);
      for (var i = 0; i < pengawasRows.length; i++) {
        final row = pengawasRows[i];
        final b = _breakdownOf(
          row.statusCounts,
          row.totalAssignment,
          row.totalTerkirim,
        );
        final target = _prelistByPengawas[row.unitId] ?? 0;
        final approved = _approvedOf(row.statusCounts);
        final approvedPlus = _approvedPlusOf(row.statusCounts);
        lines.add([
          '${i + 1}', row.title, row.subtitle == '-' ? '' : row.subtitle,
          '$target', '${row.totalAssignment}', '${b.submitted}',
          '${b.draft}', '${b.open}', '$approved', '$approvedPlus',
          pct(approvedPlus, target),
        ]);
      }
      final text = lines.map((r) => r.join('\t')).join('\n');
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Tersalin ${pengawasRows.length} baris ke clipboard.'),
        ),
      );
      return;
    }

    final rows = _displayRows();
    List<String> identityHeaders() =>
        _isPetugasLevel ? ['Petugas'] : ['SLS', 'Sub', 'Nama SLS'];
    List<String> identityValues(FasihRekapRow row) {
      if (_isPetugasLevel) return [row.title];
      final kodeSls = row.unitId.length >= 14
          ? row.unitId.substring(10, 14)
          : row.unitId;
      final kodeSubsls = row.unitId.length >= 16
          ? row.unitId.substring(14, 16)
          : '-';
      return [kodeSls, kodeSubsls, row.title];
    }

    if (_tableTab == 0) {
      // Progres.
      lines.add(
        _isPetugasLevel
            ? ['No', 'Petugas', 'Email', 'Target', 'Total', 'Submitted',
                'Draft', 'Open', '%']
            : ['No', 'SLS', 'Sub', 'Nama SLS', 'Kec/Desa', 'Target', 'Total',
                'Submitted', 'Draft', 'Open', '%'],
      );
      for (var i = 0; i < rows.length; i++) {
        final row = rows[i];
        final b = _breakdownOf(
          row.statusCounts,
          row.totalAssignment,
          row.totalTerkirim,
        );
        final target = _targetOf(row);
        final sub = row.subtitle == '-' ? '' : row.subtitle;
        if (_isPetugasLevel) {
          lines.add([
            '${i + 1}', row.title, sub, '$target', '${row.totalAssignment}',
            '${b.submitted}', '${b.draft}', '${b.open}',
            pct(b.submitted, target),
          ]);
        } else {
          final ids = identityValues(row);
          lines.add([
            '${i + 1}', ids[0], ids[1], ids[2], sub, '$target',
            '${row.totalAssignment}', '${b.submitted}', '${b.draft}',
            '${b.open}', pct(b.submitted, target),
          ]);
        }
      }
    } else if (_tableTab == 1) {
      // Jenis Bangunan.
      lines.add([
        'No',
        ...identityHeaders(),
        for (final c in _kodeBangOrder) _kodeBangColLabel(c),
        'Total',
      ]);
      for (var i = 0; i < rows.length; i++) {
        final kb = _kodeBangForRow(rows[i]);
        final total = kb.values.fold<int>(0, (s, v) => s + v);
        lines.add([
          '${i + 1}',
          ...identityValues(rows[i]),
          for (final c in _kodeBangOrder) '${kb[c] ?? 0}',
          '$total',
        ]);
      }
    } else {
      // Rekap.
      lines.add(['No', ...identityHeaders(), ..._rekapGroupLabels, 'Total']);
      for (var i = 0; i < rows.length; i++) {
        final g = _rekapGroupsOf(_kodeBangForRow(rows[i]));
        final total = g.fold<int>(0, (s, v) => s + v);
        lines.add([
          '${i + 1}',
          ...identityValues(rows[i]),
          for (final v in g) '$v',
          '$total',
        ]);
      }
    }

    final text = lines.map((r) => r.join('\t')).join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text('Tersalin ${rows.length} baris ke clipboard.')),
    );
  }

  String _tableSubtitle() {
    switch (_tableTab) {
      case 1:
        return 'Rincian record submitted per jenis bangunan (kode_bang).';
      case 2:
        return 'Rekap submitted: Usaha (BKU), Keluarga (campuran + tempat '
            'tinggal), Lainnya (4–9), Tidak ditemukan (kosong).';
      case 3:
        return 'Approved = disetujui pengawas. Approved+ = semua status selain '
            'OPEN, DRAFT & SUBMITTED BY PENCACAH. % = Approved+/target; '
            'baris hijau = capaian 40% ke atas.';
      default:
        return _isPetugasLevel
            ? 'Ketuk baris petugas untuk detail per SLS/sub-SLS. '
                  '% = submitted dibanding target prelist.'
            : 'Target = prelist wilayah. % = submitted dibanding target.';
    }
  }

  Widget _buildTableTabs() {
    Widget seg(int idx, IconData icon, String label) {
      final active = _tableTab == idx;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            if (_tableTab == idx) return;
            setState(() {
              _tableTab = idx;
              _resetSort();
            });
            if (idx == 3 && _pengawasPayload == null) {
              _loadPengawas();
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
            decoration: BoxDecoration(
              color: active ? const Color(0xFF0F4C81) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 15,
                  color: active ? Colors.white : Colors.blueGrey,
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: active ? Colors.white : Colors.blueGrey[700],
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5FB),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          seg(0, Icons.insights_rounded, 'Progres'),
          const SizedBox(width: 4),
          seg(1, Icons.home_work_outlined, 'Bangunan'),
          const SizedBox(width: 4),
          seg(2, Icons.summarize_outlined, 'Rekap'),
          if (_role == 'admin' && _isPetugasLevel) ...[
            const SizedBox(width: 4),
            seg(3, Icons.supervisor_account_rounded, 'Pengawas'),
          ],
        ],
      ),
    );
  }

  /// Jumlahkan seluruh baris yang tampil untuk baris "Total" di bawah tabel.
  _TableTotals _totalsOf(List<FasihRekapRow> rows) {
    int target = 0;
    int assignment = 0;
    int submitted = 0;
    int draft = 0;
    int open = 0;
    for (final row in rows) {
      final breakdown = _breakdownOf(
        row.statusCounts,
        row.totalAssignment,
        row.totalTerkirim,
      );
      target += _targetOf(row);
      assignment += row.totalAssignment;
      submitted += breakdown.submitted;
      draft += breakdown.draft;
      open += breakdown.open;
    }
    return _TableTotals(
      target: target,
      assignment: assignment,
      submitted: submitted,
      draft: draft,
      open: open,
    );
  }

  DataCell _totalLabelCell(String label) {
    return DataCell(
      Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
      ),
    );
  }

  List<DataCell> _totalNumberCells(_TableTotals totals) {
    return [
      _numCell(totals.target, color: const Color(0xFF0F4C81)),
      _numCell(totals.assignment),
      _numCell(totals.submitted, color: const Color(0xFF1D8F5A)),
      _numCell(totals.draft, color: Colors.orange[800]),
      _numCell(totals.open, color: Colors.blueGrey[500]),
      _percentCell(totals.submitted, totals.target),
    ];
  }

  Widget _buildPetugasTable() {
    final totals = _totalsOf(_filteredRows);
    final rows = [..._filteredRows];
    if (_sortColumnIndex != null) {
      _sortRows(rows, (row) => _petugasSortValue(row, _sortColumnIndex!));
    }
    return _fullWidthScroll(
      DataTable(
        showCheckboxColumn: false,
        horizontalMargin: 12,
        columnSpacing: 18,
        headingRowHeight: 48,
        dataRowMinHeight: 46,
        dataRowMaxHeight: 60,
        sortColumnIndex: _sortColumnIndex,
        sortAscending: _sortAscending,
        headingRowColor: WidgetStateProperty.all(const Color(0xFFF5F8FD)),
        columns: [
          _noColumn(),
          DataColumn(onSort: _onSort, label: const Text('Petugas')),
          _numColumn('Target'),
          _numColumn('Total'),
          _numColumn('Submitted'),
          _numColumn('Draft'),
          _numColumn('Open'),
          _numColumn('%'),
        ],
        rows: rows.asMap().entries.map((entry) {
          final row = entry.value;
          final breakdown = _breakdownOf(
            row.statusCounts,
            row.totalAssignment,
            row.totalTerkirim,
          );
          final target = _targetOf(row);
          return DataRow(
            onSelectChanged: (_) => _openPetugas(row),
            cells: [
              _noCell(entry.key + 1),
              DataCell(
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 190),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            row.title,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (row.subtitle.isNotEmpty && row.subtitle != '-')
                            Text(
                              row.subtitle,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.blueGrey[400],
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right_rounded, size: 18),
                  ],
                ),
              ),
              _numCell(target, color: const Color(0xFF0F4C81)),
              _numCell(row.totalAssignment),
              _numCell(breakdown.submitted, color: const Color(0xFF1D8F5A)),
              _numCell(breakdown.draft, color: Colors.orange[800]),
              _numCell(breakdown.open, color: Colors.blueGrey[500]),
              _percentCell(breakdown.submitted, target),
            ],
          );
        }).toList()..add(
          DataRow(
            color: WidgetStateProperty.all(const Color(0xFFF5F8FD)),
            cells: [
              const DataCell(Text('')),
              _totalLabelCell('Total (${rows.length} petugas)'),
              ..._totalNumberCells(totals),
            ],
          ),
        ),
      ),
    );
  }

  /// Nilai sortir kolom tabel pengawas (indeks sesuai urutan header).
  Comparable<dynamic> _pengawasSortValue(FasihRekapRow row, int index) {
    final breakdown = _breakdownOf(
      row.statusCounts,
      row.totalAssignment,
      row.totalTerkirim,
    );
    final target = _prelistByPengawas[row.unitId] ?? 0;
    final approved = _approvedOf(row.statusCounts);
    switch (index) {
      case 2:
        return target;
      case 3:
        return row.totalAssignment;
      case 4:
        return breakdown.submitted;
      case 5:
        return breakdown.draft;
      case 6:
        return breakdown.open;
      case 7:
        return approved;
      case 8:
        return _approvedPlusOf(row.statusCounts);
      case 9:
        final approvedPlus = _approvedPlusOf(row.statusCounts);
        return target > 0 ? approvedPlus / target : -1.0;
      default:
        return row.title.toLowerCase();
    }
  }

  /// Tabel tab "Pengawas": progres per pengawas + kolom Approved dan
  /// persentase Approved terhadap target prelist binaannya.
  Widget _buildPengawasTable() {
    if (_pengawasLoading || _pengawasPayload == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final payload = _pengawasPayload!;
    if (payload.rows.isEmpty) {
      return _buildEmptyState('Belum ada data pengawas.');
    }

    final rows = payload.rows
        .where((row) => row.unitId.trim().isNotEmpty)
        .toList();
    if (_sortColumnIndex != null) {
      _sortRows(rows, (row) => _pengawasSortValue(row, _sortColumnIndex!));
    }

    // Baris total.
    var totTarget = 0;
    var totAssignment = 0;
    var totSubmitted = 0;
    var totDraft = 0;
    var totOpen = 0;
    var totApproved = 0;
    var totApprovedPlus = 0;
    for (final row in rows) {
      final b = _breakdownOf(
        row.statusCounts,
        row.totalAssignment,
        row.totalTerkirim,
      );
      totTarget += _prelistByPengawas[row.unitId] ?? 0;
      totAssignment += row.totalAssignment;
      totSubmitted += b.submitted;
      totDraft += b.draft;
      totOpen += b.open;
      totApproved += _approvedOf(row.statusCounts);
      totApprovedPlus += _approvedPlusOf(row.statusCounts);
    }

    return _fullWidthScroll(
      DataTable(
        showCheckboxColumn: false,
        horizontalMargin: 12,
        columnSpacing: 18,
        headingRowHeight: 48,
        dataRowMinHeight: 46,
        dataRowMaxHeight: 60,
        sortColumnIndex: _sortColumnIndex,
        sortAscending: _sortAscending,
        headingRowColor: WidgetStateProperty.all(const Color(0xFFF5F8FD)),
        columns: [
          _noColumn(),
          DataColumn(onSort: _onSort, label: const Text('Pengawas')),
          _numColumn('Target'),
          _numColumn('Total'),
          _numColumn('Submitted'),
          _numColumn('Draft'),
          _numColumn('Open'),
          _numColumn('Approved'),
          _numColumn('Approved+'),
          _numColumn('%'),
        ],
        rows: rows.asMap().entries.map((entry) {
          final row = entry.value;
          final b = _breakdownOf(
            row.statusCounts,
            row.totalAssignment,
            row.totalTerkirim,
          );
          final target = _prelistByPengawas[row.unitId] ?? 0;
          final approved = _approvedOf(row.statusCounts);
          final approvedPlus = _approvedPlusOf(row.statusCounts);
          final hijau = target > 0 && approvedPlus / target >= 0.4;
          return DataRow(
            color: hijau
                ? WidgetStateProperty.all(const Color(0xFFE3F4EA))
                : null,
            cells: [
              _noCell(entry.key + 1),
              DataCell(
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 190),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.title,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (row.subtitle.isNotEmpty && row.subtitle != '-')
                        Text(
                          row.subtitle,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.blueGrey[400],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              _numCell(target, color: const Color(0xFF0F4C81)),
              _numCell(row.totalAssignment),
              _numCell(b.submitted, color: const Color(0xFF1D8F5A)),
              _numCell(b.draft, color: Colors.orange[800]),
              _numCell(b.open, color: Colors.blueGrey[500]),
              _numCell(approved, color: const Color(0xFF6B4FBB)),
              _numCell(approvedPlus, color: const Color(0xFF0F766E)),
              _percentCell(approvedPlus, target),
            ],
          );
        }).toList()..add(
          DataRow(
            color: WidgetStateProperty.all(const Color(0xFFF5F8FD)),
            cells: [
              const DataCell(Text('')),
              _totalLabelCell('Total (${rows.length} pengawas)'),
              _numCell(totTarget, color: const Color(0xFF0F4C81)),
              _numCell(totAssignment),
              _numCell(totSubmitted, color: const Color(0xFF1D8F5A)),
              _numCell(totDraft, color: Colors.orange[800]),
              _numCell(totOpen, color: Colors.blueGrey[500]),
              _numCell(totApproved, color: const Color(0xFF6B4FBB)),
              _numCell(totApprovedPlus, color: const Color(0xFF0F766E)),
              _percentCell(totApprovedPlus, totTarget),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWilayahTable() {
    final rows = [..._filteredRows];
    if (_sortColumnIndex != null) {
      _sortRows(rows, (row) => _wilayahSortValue(row, _sortColumnIndex!));
    } else {
      // Default: urutkan per kode wilayah agar sub-SLS dalam SLS yang sama
      // berdekatan.
      rows.sort((a, b) => a.unitId.compareTo(b.unitId));
    }
    final totals = _totalsOf(rows);

    return _fullWidthScroll(
      DataTable(
        showCheckboxColumn: false,
        horizontalMargin: 12,
        columnSpacing: 18,
        headingRowHeight: 48,
        dataRowMinHeight: 46,
        dataRowMaxHeight: 60,
        sortColumnIndex: _sortColumnIndex,
        sortAscending: _sortAscending,
        headingRowColor: WidgetStateProperty.all(const Color(0xFFF5F8FD)),
        columns: [
          _noColumn(),
          DataColumn(onSort: _onSort, label: const Text('SLS')),
          DataColumn(onSort: _onSort, label: const Text('Sub')),
          DataColumn(onSort: _onSort, label: const Text('Nama SLS')),
          _numColumn('Target'),
          _numColumn('Total'),
          _numColumn('Submitted'),
          _numColumn('Draft'),
          _numColumn('Open'),
          _numColumn('%'),
        ],
        rows: rows.asMap().entries.map((entry) {
          final row = entry.value;
          final breakdown = _breakdownOf(
            row.statusCounts,
            row.totalAssignment,
            row.totalTerkirim,
          );
          final target = _targetOf(row);
          final kodeSls = row.unitId.length >= 14
              ? row.unitId.substring(10, 14)
              : row.unitId;
          final kodeSubsls = row.unitId.length >= 16
              ? row.unitId.substring(14, 16)
              : '-';
          return DataRow(
            cells: [
              _noCell(entry.key + 1),
              DataCell(
                Text(
                  kodeSls,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F4C81),
                  ),
                ),
              ),
              DataCell(Text(kodeSubsls)),
              DataCell(
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 200),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.title,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (row.subtitle.isNotEmpty && row.subtitle != '-')
                        Text(
                          row.subtitle,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.blueGrey[400],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              _numCell(target, color: const Color(0xFF0F4C81)),
              _numCell(row.totalAssignment),
              _numCell(breakdown.submitted, color: const Color(0xFF1D8F5A)),
              _numCell(breakdown.draft, color: Colors.orange[800]),
              _numCell(breakdown.open, color: Colors.blueGrey[500]),
              _percentCell(breakdown.submitted, target),
            ],
          );
        }).toList()..add(
          DataRow(
            color: WidgetStateProperty.all(const Color(0xFFF5F8FD)),
            cells: [
              const DataCell(Text('')),
              _totalLabelCell('Total'),
              const DataCell(Text('')),
              DataCell(
                Text(
                  '${rows.length} SLS/Sub-SLS',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              ..._totalNumberCells(totals),
            ],
          ),
        ),
      ),
    );
  }

  /// Tabel tab "Jenis Bangunan": rincian kode_bang (submitted) per baris.
  Widget _buildKodeBangTable() {
    if (!_kodeBangLoaded) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final rows = [..._filteredRows];
    if (_sortColumnIndex != null) {
      _sortRows(rows, (r) => _bangunanSortValue(r, _sortColumnIndex!));
    } else if (!_isPetugasLevel) {
      rows.sort((a, b) => a.unitId.compareTo(b.unitId));
    }

    // Total per kode_bang untuk baris Total.
    final totals = <String, int>{};
    for (final row in rows) {
      _kodeBangForRow(row).forEach((code, n) {
        totals[code] = (totals[code] ?? 0) + n;
      });
    }
    final grandTotal = totals.values.fold<int>(0, (s, v) => s + v);

    return _fullWidthScroll(
      DataTable(
        showCheckboxColumn: false,
        horizontalMargin: 12,
        columnSpacing: 16,
        headingRowHeight: 48,
        dataRowMinHeight: 46,
        dataRowMaxHeight: 60,
        sortColumnIndex: _sortColumnIndex,
        sortAscending: _sortAscending,
        headingRowColor: WidgetStateProperty.all(const Color(0xFFF5F8FD)),
        columns: [
          _noColumn(),
          ..._identityColumns(),
          for (final code in _kodeBangOrder) _numColumn(_kodeBangColLabel(code)),
          _numColumn('Total'),
        ],
        rows: rows.asMap().entries.map((entry) {
          final row = entry.value;
          final kb = _kodeBangForRow(row);
          final rowTotal = kb.values.fold<int>(0, (s, v) => s + v);
          return DataRow(
            cells: [
              _noCell(entry.key + 1),
              ..._kodeBangIdentityCells(row),
              for (final code in _kodeBangOrder) _numCell(kb[code] ?? 0),
              _numCell(rowTotal, color: const Color(0xFF0F4C81)),
            ],
          );
        }).toList()..add(
          DataRow(
            color: WidgetStateProperty.all(const Color(0xFFF5F8FD)),
            cells: [
              const DataCell(Text('')),
              _totalLabelCell('Total'),
              if (!_isPetugasLevel) ...[
                const DataCell(Text('')),
                const DataCell(Text('')),
              ],
              for (final code in _kodeBangOrder) _numCell(totals[code] ?? 0),
              _numCell(grandTotal, color: const Color(0xFF0F4C81)),
            ],
          ),
        ),
      ),
    );
  }

  /// Jumlah kolom identitas (setelah kolom No) untuk tab Bangunan/Rekap.
  int get _idCount => _isPetugasLevel ? 1 : 3;

  /// Kolom identitas (sortable) untuk tab Bangunan/Rekap.
  List<DataColumn> _identityColumns() {
    if (_isPetugasLevel) {
      return [DataColumn(onSort: _onSort, label: const Text('Petugas'))];
    }
    return [
      DataColumn(onSort: _onSort, label: const Text('SLS')),
      DataColumn(onSort: _onSort, label: const Text('Sub')),
      DataColumn(onSort: _onSort, label: const Text('Nama SLS')),
    ];
  }

  /// Nilai sortir kolom identitas (indeks 1..idCount).
  Comparable<dynamic> _identitySortValue(FasihRekapRow row, int index) {
    if (_isPetugasLevel) return row.title.toLowerCase();
    switch (index) {
      case 1:
        return row.unitId; // SLS: unitId penuh agar sub tetap berkelompok.
      case 2:
        return row.unitId.length >= 16 ? row.unitId.substring(14, 16) : '';
      default:
        return row.title.toLowerCase(); // Nama SLS.
    }
  }

  /// Nilai sortir tab Bangunan: identitas, kolom kode_bang, lalu Total.
  Comparable<dynamic> _bangunanSortValue(FasihRekapRow row, int index) {
    final idc = _idCount;
    if (index <= idc) return _identitySortValue(row, index);
    final kb = _kodeBangForRow(row);
    final k = index - idc - 1;
    if (k >= 0 && k < _kodeBangOrder.length) return kb[_kodeBangOrder[k]] ?? 0;
    return kb.values.fold<int>(0, (s, v) => s + v); // Total.
  }

  /// Nilai sortir tab Rekap: identitas, 4 kategori, lalu Total.
  Comparable<dynamic> _rekapSortValue(FasihRekapRow row, int index) {
    final idc = _idCount;
    if (index <= idc) return _identitySortValue(row, index);
    final g = _rekapGroupsOf(_kodeBangForRow(row));
    final gi = index - idc - 1;
    if (gi >= 0 && gi < g.length) return g[gi];
    return g.fold<int>(0, (s, v) => s + v); // Total.
  }

  /// Sel identitas untuk tabel kode_bang sesuai level.
  List<DataCell> _kodeBangIdentityCells(FasihRekapRow row) {
    if (_isPetugasLevel) {
      return [
        DataCell(
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 190),
            child: Text(
              row.title,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ];
    }
    final kodeSls = row.unitId.length >= 14
        ? row.unitId.substring(10, 14)
        : row.unitId;
    final kodeSubsls = row.unitId.length >= 16
        ? row.unitId.substring(14, 16)
        : '-';
    return [
      DataCell(
        Text(
          kodeSls,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: Color(0xFF0F4C81),
          ),
        ),
      ),
      DataCell(Text(kodeSubsls)),
      DataCell(
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 190),
          child: Text(
            row.title,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ),
    ];
  }

  /// Kelompokkan distribusi kode_bang menjadi 5 kategori rekap:
  ///   Usaha = 1 (BKU); Keluarga = 2+3; Lainnya = 4..9;
  ///   Usaha TD = TD_USAHA; Keluarga TD = TD_KELUARGA.
  /// Urutan hasil: [usaha, keluarga, lainnya, usahaTd, keluargaTd].
  List<int> _rekapGroupsOf(Map<String, int> kb) {
    final usaha = kb['1'] ?? 0;
    final keluarga = (kb['2'] ?? 0) + (kb['3'] ?? 0);
    var lainnya = 0;
    for (final c in const ['4', '5', '6', '7', '8', '9']) {
      lainnya += kb[c] ?? 0;
    }
    final usahaTd = kb['TD_USAHA'] ?? 0;
    final keluargaTd = kb['TD_KELUARGA'] ?? 0;
    return [usaha, keluarga, lainnya, usahaTd, keluargaTd];
  }

  static const List<String> _rekapGroupLabels = [
    'Usaha',
    'Keluarga',
    'Lainnya',
    'Usaha TD',
    'Keluarga TD',
  ];

  Color _rekapGroupColor(int index) {
    switch (index) {
      case 0:
        return const Color(0xFF1D8F5A); // Usaha
      case 1:
        return const Color(0xFF2D77D0); // Keluarga
      case 2:
        return Colors.blueGrey[500]!; // Lainnya
      case 3:
        return Colors.orange[800]!; // Usaha TD
      default:
        return Colors.red[400]!; // Keluarga TD
    }
  }

  /// Tabel tab "Rekap": kode_bang dikelompokkan menjadi 4 kategori.
  Widget _buildRekapTable() {
    if (!_kodeBangLoaded) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final rows = [..._filteredRows];
    if (_sortColumnIndex != null) {
      _sortRows(rows, (r) => _rekapSortValue(r, _sortColumnIndex!));
    } else if (!_isPetugasLevel) {
      rows.sort((a, b) => a.unitId.compareTo(b.unitId));
    }

    final totals = List<int>.filled(_rekapGroupLabels.length, 0);
    for (final row in rows) {
      final g = _rekapGroupsOf(_kodeBangForRow(row));
      for (var i = 0; i < g.length; i++) {
        totals[i] += g[i];
      }
    }
    final grandTotal = totals.fold<int>(0, (s, v) => s + v);

    return _fullWidthScroll(
      DataTable(
        showCheckboxColumn: false,
        horizontalMargin: 12,
        columnSpacing: 18,
        headingRowHeight: 48,
        dataRowMinHeight: 46,
        dataRowMaxHeight: 60,
        sortColumnIndex: _sortColumnIndex,
        sortAscending: _sortAscending,
        headingRowColor: WidgetStateProperty.all(const Color(0xFFF5F8FD)),
        columns: [
          _noColumn(),
          ..._identityColumns(),
          for (final label in _rekapGroupLabels) _numColumn(label),
          _numColumn('Total'),
        ],
        rows: rows.asMap().entries.map((entry) {
          final row = entry.value;
          final g = _rekapGroupsOf(_kodeBangForRow(row));
          final rowTotal = g.fold<int>(0, (s, v) => s + v);
          return DataRow(
            cells: [
              _noCell(entry.key + 1),
              ..._kodeBangIdentityCells(row),
              for (var i = 0; i < g.length; i++)
                _numCell(g[i], color: _rekapGroupColor(i)),
              _numCell(rowTotal, color: const Color(0xFF0F4C81)),
            ],
          );
        }).toList()..add(
          DataRow(
            color: WidgetStateProperty.all(const Color(0xFFF5F8FD)),
            cells: [
              const DataCell(Text('')),
              _totalLabelCell('Total'),
              if (!_isPetugasLevel) ...[
                const DataCell(Text('')),
                const DataCell(Text('')),
              ],
              for (var i = 0; i < totals.length; i++)
                _numCell(totals[i], color: _rekapGroupColor(i)),
              _numCell(grandTotal, color: const Color(0xFF0F4C81)),
            ],
          ),
        ),
      ),
    );
  }

  /// Persentase capaian submitted terhadap target prelist.
  /// Jika target belum diisi (0), tampilkan '-'.
  DataCell _percentCell(int submitted, int target) {
    if (target <= 0) {
      return DataCell(
        Text('-', style: TextStyle(color: Colors.blueGrey[300])),
      );
    }
    final percent = submitted / target;
    return DataCell(
      Text(
        '${(percent * 100).toStringAsFixed(2)}%',
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: _progressColor(percent),
        ),
      ),
    );
  }

  /// Bungkus tabel agar minimal selebar layar (mengisi seluruh lebar),
  /// namun tetap bisa digeser horizontal jika isinya lebih lebar.
  Widget _fullWidthScroll(Widget table) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: constraints.maxWidth),
          child: table,
        ),
      ),
    );
  }

  DataColumn _numColumn(String label, {bool sortable = true}) {
    return DataColumn(
      numeric: true,
      onSort: sortable ? _onSort : null,
      label: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
      ),
    );
  }

  /// Urutkan salinan baris sesuai arah sort aktif.
  void _sortRows(
    List<FasihRekapRow> rows,
    Comparable<dynamic> Function(FasihRekapRow) selector,
  ) {
    rows.sort((a, b) {
      final cmp = Comparable.compare(selector(a), selector(b));
      return _sortAscending ? cmp : -cmp;
    });
  }

  /// Nilai sortir kolom tabel petugas (indeks kolom sesuai urutan header).
  Comparable<dynamic> _petugasSortValue(FasihRekapRow row, int index) {
    final breakdown = _breakdownOf(
      row.statusCounts,
      row.totalAssignment,
      row.totalTerkirim,
    );
    final target = _targetOf(row);
    // Indeks kolom memperhitungkan kolom "No" di posisi 0.
    switch (index) {
      case 2:
        return target;
      case 3:
        return row.totalAssignment;
      case 4:
        return breakdown.submitted;
      case 5:
        return breakdown.draft;
      case 6:
        return breakdown.open;
      case 7:
        // Target 0 tak punya persentase; taruh paling bawah saat menaik.
        return target > 0 ? breakdown.submitted / target : -1.0;
      default:
        return row.title.toLowerCase();
    }
  }

  /// Nilai sortir kolom tabel wilayah (indeks kolom sesuai urutan header).
  Comparable<dynamic> _wilayahSortValue(FasihRekapRow row, int index) {
    final breakdown = _breakdownOf(
      row.statusCounts,
      row.totalAssignment,
      row.totalTerkirim,
    );
    final target = _targetOf(row);
    // Indeks kolom memperhitungkan kolom "No" di posisi 0.
    switch (index) {
      case 2:
        return row.unitId.length >= 16 ? row.unitId.substring(14, 16) : '';
      case 3:
        return row.title.toLowerCase();
      case 4:
        return target;
      case 5:
        return row.totalAssignment;
      case 6:
        return breakdown.submitted;
      case 7:
        return breakdown.draft;
      case 8:
        return breakdown.open;
      case 9:
        return target > 0 ? breakdown.submitted / target : -1.0;
      default:
        // Kolom SLS: pakai unitId penuh agar sub-SLS tetap berkelompok.
        return row.unitId;
    }
  }

  DataCell _numCell(int value, {Color? color}) {
    return DataCell(
      Text(
        value.toString(),
        style: TextStyle(fontWeight: FontWeight.w600, color: color),
      ),
    );
  }

  /// Kolom "No": nomor urut tampilan, tidak bisa di-sort agar selalu 1..N
  /// dari atas ke bawah mengikuti urutan baris yang sedang tampil.
  DataColumn _noColumn() {
    return const DataColumn(
      label: Text(
        'No',
        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
      ),
    );
  }

  DataCell _noCell(int number) {
    return DataCell(
      Text(
        '$number',
        style: TextStyle(fontWeight: FontWeight.w600, color: Colors.blueGrey[400]),
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.inbox_rounded, size: 48, color: Colors.blueGrey[200]),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.blueGrey[500]),
            ),
          ],
        ),
      ),
    );
  }

  Color _progressColor(double percent) {
    if (percent >= 0.999) return const Color(0xFF1D8F5A);
    if (percent >= 0.6) return const Color(0xFF2D77D0);
    if (percent >= 0.3) return Colors.orange[700]!;
    return Colors.red[400]!;
  }
}

class _Tier {
  final String label;
  final String sub;
  final Color color;

  const _Tier({required this.label, required this.sub, required this.color});
}

class _TableTotals {
  final int target;
  final int assignment;
  final int submitted;
  final int draft;
  final int open;

  const _TableTotals({
    required this.target,
    required this.assignment,
    required this.submitted,
    required this.draft,
    required this.open,
  });
}

class _StatusBreakdown {
  final int open;
  final int draft;
  final int submitted;

  const _StatusBreakdown({
    required this.open,
    required this.draft,
    required this.submitted,
  });
}
