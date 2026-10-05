import 'dart:math' show max;
import 'package:flutter/material.dart';

import '../../data/services/fasih_rekap_service.dart';
import '../../data/services/fasih_daily_service.dart';
import '../../data/services/groundcheck_supabase_service.dart';

// ── Merged model ──────────────────────────────────────────────────────────────

class UnifiedRekapRow {
  final String unitId;
  final String title;
  final String subtitle;
  final int totalAssignment;

  /// Jumlah final (semua status kecuali OPEN & DRAFT).
  final int totalTerkirim;
  final Map<String, int> statusCounts;
  final int todayCount;
  final int yesterdayCount;
  final int delta;
  final Map<String, int> statusCountsToday;

  /// Progress 7 hari terakhir (kumulatif hari acuan − kumulatif 7 hari lalu).
  final int weeklyDelta;

  /// Kumulatif "terkirim" pada 7 hari lalu (baseline mingguan).
  final int weekAgoCount;

  /// Pecahan kenaikan per status dalam 7 hari terakhir.
  final Map<String, int> statusCountsWeek;

  const UnifiedRekapRow({
    required this.unitId,
    required this.title,
    required this.subtitle,
    required this.totalAssignment,
    required this.totalTerkirim,
    required this.statusCounts,
    required this.todayCount,
    required this.yesterdayCount,
    required this.delta,
    required this.statusCountsToday,
    this.weeklyDelta = 0,
    this.weekAgoCount = 0,
    this.statusCountsWeek = const {},
  });
}

class _StatusDetailSection {
  final String title;
  final String total;
  final Map<String, int> statuses;
  final Color accent;

  const _StatusDetailSection({
    required this.title,
    required this.total,
    required this.statuses,
    required this.accent,
  });
}

List<UnifiedRekapRow> _mergeRows(
  List<FasihRekapRow> rekap,
  List<DailyContributionRow> daily,
  List<DailyContributionRow> weekly,
) {
  final dailyMap = {for (final d in daily) d.unitId: d};
  final weeklyMap = {for (final w in weekly) w.unitId: w};
  return rekap.map((r) {
    final d = dailyMap[r.unitId];
    final w = weeklyMap[r.unitId];
    return UnifiedRekapRow(
      unitId: r.unitId,
      title: r.title,
      subtitle: r.subtitle,
      totalAssignment: r.totalAssignment,
      totalTerkirim: r.totalTerkirim,
      statusCounts: r.statusCounts,
      todayCount: d?.todayCount ?? 0,
      yesterdayCount: d?.yesterdayCount ?? 0,
      delta: d?.delta ?? 0,
      statusCountsToday: d?.statusCountsToday ?? {},
      weeklyDelta: w?.delta ?? 0,
      weekAgoCount: w?.yesterdayCount ?? 0,
      statusCountsWeek: w?.statusCountsToday ?? {},
    );
  }).toList();
}

// ── Threshold warna per level ─────────────────────────────────────────────────

int _deltaThreshold(String level) {
  switch (level) {
    case 'admin_pengawas':
      return 77;
    case 'pengawas_petugas':
    case 'admin_petugas':
      return 11;
    default:
      return 1;
  }
}

// ── Sort options ──────────────────────────────────────────────────────────────

enum _SortField { kumulatif, delta, week }

enum _SortDir { asc, desc }

enum _AdminViewMode { byPengawas, allPetugas, openPengawas, submitting }

enum _ViewMode { card, table, chart }

// ── Page ─────────────────────────────────────────────────────────────────────

class FasihDashboardPage extends StatefulWidget {
  /// Dipanggil saat baris SLS (level wilayah) ditekan, untuk membuka SLS
  /// tersebut di peta beserta progres kegiatannya.
  /// [slsUnitId] = kode wilayah 16 digit (= idsubsls polygon), [slsLabel]
  /// judul untuk notifikasi.
  final void Function(String slsUnitId, String slsLabel)? onOpenSlsOnMap;

  const FasihDashboardPage({super.key, this.onOpenSlsOnMap});

  @override
  State<FasihDashboardPage> createState() => _FasihDashboardPageState();
}

class _FasihDashboardPageState extends State<FasihDashboardPage> {
  final GroundcheckSupabaseService _profileService =
      GroundcheckSupabaseService();
  final FasihRekapService _rekapService = FasihRekapService();
  final FasihDailyService _dailyService = FasihDailyService();

  bool _isLoading = true;
  String? _error;
  Se2026UserProfile? _profile;

  List<UnifiedRekapRow> _rows = [];
  int _totalAssignmentAll = 0;
  int _totalTerkirimAll = 0;
  int _totalOpenAll = 0;
  int _totalDeltaToday = 0;
  int _activeUnitsToday = 0;
  int _totalDeltaWeek = 0;
  int _activeUnitsWeek = 0;
  String _level = '';

  DateTime _targetDate = DateTime.now();
  _SortField _sortField = _SortField.delta;
  _SortDir _sortDir = _SortDir.desc;
  _AdminViewMode _adminViewMode = _AdminViewMode.byPengawas;
  _ViewMode _viewMode = _ViewMode.card;
  double _textScale = 1.0;
  String? _tableSortKey;
  bool _tableSortAsc = true;
  bool _openSortByName = false;
  bool _openSortAsc = false;
  String _submitSortKey = 'sisa';
  bool _submitSortAsc = false;
  bool _submitByPetugas = false;

  UnifiedRekapRow? _selectedPengawas;
  UnifiedRekapRow? _selectedPetugas;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final profile =
          _profile ?? await _profileService.fetchCurrentSe2026Profile();
      if (profile == null) throw Exception('Profil SE2026 tidak ditemukan.');

      final role = profile.role;
      final pengawasId = _selectedPengawas?.unitId;
      final petugasId = _selectedPetugas?.unitId;

      // Mode daftar petugas: "Semua Petugas", atau tab Submitting yang sedang
      // dipasang ke tampilan per petugas.
      final isAllPetugas =
          role == 'admin' &&
          _selectedPetugas == null &&
          (_adminViewMode == _AdminViewMode.allPetugas ||
              (_adminViewMode == _AdminViewMode.submitting &&
                  _submitByPetugas));

      // Mode daftar petugas: abaikan drill pengawas untuk query.
      final effectivePengawasId = isAllPetugas ? null : pengawasId;

      final results = await Future.wait([
        _fetchRekap(effectivePengawasId, petugasId, isAllPetugas),
        _dailyService.fetchDailyContribution(
          targetDate: _targetDate,
          pengawasId: effectivePengawasId,
          petugasId: petugasId,
          allPetugas: isAllPetugas,
          progressMode: _progressModeParam,
        ),
        _dailyService.fetchDailyContribution(
          targetDate: _targetDate,
          pengawasId: effectivePengawasId,
          petugasId: petugasId,
          allPetugas: isAllPetugas,
          progressMode: _progressModeParam,
          baselineDays: 7,
        ),
      ]);

      final rekapPayload = results[0] as FasihRekapPayload;
      final dailyPayload = results[1] as DailyContributionPayload;
      final weeklyPayload = results[2] as DailyContributionPayload;

      final merged = _mergeRows(
        rekapPayload.rows,
        dailyPayload.rows,
        weeklyPayload.rows,
      );

      if (!mounted) return;
      setState(() {
        _profile = profile;
        _level = dailyPayload.level.isNotEmpty
            ? dailyPayload.level
            : _inferLevel(role, effectivePengawasId, petugasId);
        _rows = merged;
        _totalAssignmentAll = rekapPayload.summary.totalAssignments;
        _totalTerkirimAll = rekapPayload.summary.totalTerkirim;
        _totalOpenAll = rekapPayload.summary.totalOpen;
        _totalDeltaToday = dailyPayload.summary.totalDelta;
        _activeUnitsToday = merged.where((r) => r.delta > 0).length;
        _totalDeltaWeek = weeklyPayload.summary.totalDelta;
        _activeUnitsWeek = merged.where((r) => r.weeklyDelta > 0).length;
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

  Future<FasihRekapPayload> _fetchRekap(
    String? pengawasId,
    String? petugasId,
    bool allPetugas,
  ) {
    // RPC gabungan: role & pemilihan level ditentukan server-side dari auth.uid().
    // targetDate agar kumulatif mengikuti tanggal terpilih (bukan snapshot terbaru).
    return _rekapService.fetchRekap(
      pengawasId: pengawasId,
      petugasId: petugasId,
      allPetugas: allPetugas,
      targetDate: _isToday ? null : _targetDate,
      // Ambil sebanyak mungkin (server cap 500) agar rincian status yang
      // dijumlah di klien tidak terpotong paging & cocok dengan total server.
      limit: 500,
    );
  }

  String _inferLevel(String role, String? pengawasId, String? petugasId) {
    if (role == 'pendata') return 'pendata_wilayah';
    if (role == 'pengawas') {
      return petugasId != null ? 'pengawas_wilayah' : 'pengawas_petugas';
    }
    if (role == 'admin') {
      if (petugasId != null) return 'admin_wilayah';
      if (pengawasId != null) return 'admin_petugas';
      return 'admin_pengawas';
    }
    return '';
  }

  Map<String, int> get _aggregatedStatusCumul {
    final out = <String, int>{};
    for (final row in _rows) {
      for (final e in row.statusCounts.entries) {
        out[e.key] = (out[e.key] ?? 0) + e.value;
      }
    }
    final sorted = out.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Map.fromEntries(sorted);
  }

  Map<String, int> get _aggregatedStatusToday {
    final out = <String, int>{};
    for (final row in _rows) {
      for (final e in row.statusCountsToday.entries) {
        out[e.key] = (out[e.key] ?? 0) + e.value;
      }
    }
    final sorted = out.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Map.fromEntries(sorted);
  }

  Map<String, int> get _aggregatedStatusWeek {
    final out = <String, int>{};
    for (final row in _rows) {
      for (final e in row.statusCountsWeek.entries) {
        out[e.key] = (out[e.key] ?? 0) + e.value;
      }
    }
    final sorted = out.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Map.fromEntries(sorted);
  }

  /// Nilai sort/progress baris sesuai field terpilih.
  int _sortValue(UnifiedRekapRow row) {
    switch (_sortField) {
      case _SortField.kumulatif:
        return row.totalTerkirim;
      case _SortField.delta:
        return row.delta;
      case _SortField.week:
        return row.weeklyDelta;
    }
  }

  List<UnifiedRekapRow> get _sortedRows {
    final sorted = List<UnifiedRekapRow>.from(_rows);
    sorted.sort((a, b) {
      final va = _sortValue(a);
      final vb = _sortValue(b);
      return _sortDir == _SortDir.desc ? vb.compareTo(va) : va.compareTo(vb);
    });
    return sorted;
  }

  List<UnifiedRekapRow> get _tableSortedRows {
    final key = _tableSortKey;
    if (key == null) return _sortedRows;
    final list = List<UnifiedRekapRow>.from(_sortedRows);
    final asc = _tableSortAsc ? 1 : -1;
    list.sort((a, b) {
      switch (key) {
        case 'title':
          return a.title.compareTo(b.title) * asc;
        case 'kumul':
          return a.totalAssignment.compareTo(b.totalAssignment) * asc;
        case 'terkirim':
          return a.totalTerkirim.compareTo(b.totalTerkirim) * asc;
        case 'delta':
          return a.delta.compareTo(b.delta) * asc;
        case 'week':
          return a.weeklyDelta.compareTo(b.weeklyDelta) * asc;
        case 'kmrn':
          return a.yesterdayCount.compareTo(b.yesterdayCount) * asc;
        default:
          final av = a.statusCounts[key] ?? 0;
          final bv = b.statusCounts[key] ?? 0;
          return av.compareTo(bv) * asc;
      }
    });
    return list;
  }

  void _onTableHeaderTap(String key) {
    setState(() {
      if (_tableSortKey == key) {
        _tableSortAsc = !_tableSortAsc;
      } else {
        _tableSortKey = key;
        _tableSortAsc = true;
      }
    });
  }

  // Returns a tappable header cell with sort indicator.
  Widget _sortableTh(
    String label,
    String key,
    double w,
    TextStyle style, {
    bool leftAlign = false,
  }) {
    final active = _tableSortKey == key;
    final activeColor = const Color(0xFF0F4C81);
    return GestureDetector(
      onTap: () => _onTableHeaderTap(key),
      child: SizedBox(
        width: w,
        child: Row(
          mainAxisAlignment: leftAlign
              ? MainAxisAlignment.start
              : MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                label,
                textAlign: leftAlign ? TextAlign.left : TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: active ? style.copyWith(color: activeColor) : style,
              ),
            ),
            if (active) ...[
              const SizedBox(width: 2),
              Icon(
                _tableSortAsc
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
                size: 10,
                color: activeColor,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String get _role => _profile?.role ?? '';

  /// True saat baris merepresentasikan wilayah/SLS (mis. drill ke wilayah
  /// kerja petugas), bukan agregat pengawas/petugas.
  bool get _isWilayahLevel => _level.endsWith('_wilayah');

  /// Sub-SLS = 2 digit terakhir dari kode wilayah 16 digit
  /// (kode_desa10 + sls4 + subsls2). Null jika kode tidak lengkap.
  String? _subSls(String unitId) {
    if (unitId.length >= 16) return unitId.substring(unitId.length - 2);
    return null;
  }

  /// Judul baris untuk tampilan. Pada level wilayah, nama SLS ditambah
  /// keterangan sub-SLS agar SLS dengan nama sama tetap dapat dibedakan.
  String _displayTitle(UnifiedRekapRow row) {
    if (!_isWilayahLevel) return row.title;
    final sub = _subSls(row.unitId);
    return sub != null ? '${row.title} · Sub $sub' : row.title;
  }

  bool _hasSubtitle(UnifiedRekapRow row) {
    final s = row.subtitle.trim();
    return s.isNotEmpty && s != '-';
  }

  String get _progressModeParam {
    if (_role != 'admin' ||
        _selectedPengawas != null ||
        _selectedPetugas != null) {
      return 'petugas';
    }
    if (_adminViewMode == _AdminViewMode.allPetugas) return 'petugas';
    if (_adminViewMode == _AdminViewMode.submitting && _submitByPetugas) {
      return 'petugas';
    }
    return 'pengawas';
  }

  /// Mode ringkas "Open per Pengawas": hanya kolom nama + jumlah OPEN.
  bool get _isOpenPengawasView =>
      _role == 'admin' &&
      _selectedPengawas == null &&
      _selectedPetugas == null &&
      _adminViewMode == _AdminViewMode.openPengawas;

  int _openCount(UnifiedRekapRow row) => row.statusCounts['OPEN'] ?? 0;

  /// Mode "Submitting": progres + rincian status yang masih harus dikirim,
  /// lengkap dengan perkiraan hari & tanggal selesai.
  bool get _isSubmittingView =>
      _role == 'admin' &&
      _adminViewMode == _AdminViewMode.submitting &&
      _selectedPetugas == null;

  /// Submitting di level teratas (belum drill ke petugas satu pengawas).
  bool get _isSubmittingRoot => _isSubmittingView && _selectedPengawas == null;

  /// True untuk mode tabel ringkas (Open / Submitting) yang punya kontrol
  /// sendiri, sehingga baris sort & pilihan tampilan disembunyikan.
  bool get _isSimpleTableView => _isOpenPengawasView || _isSubmittingView;

  int _statusOf(UnifiedRekapRow row, String key) => row.statusCounts[key] ?? 0;

  /// Sisa yang belum disetujui pengawas: DRAFT Awal + REJECTED Pengawas +
  /// DRAFT Revisi.
  int _sisaSubmit(UnifiedRekapRow row) =>
      _statusOf(row, 'DRAFT Awal') +
      _statusOf(row, 'REJECTED Pengawas') +
      _statusOf(row, 'DRAFT Revisi');

  /// Rata-rata harian dari progres 7 hari terakhir.
  double _avgDaily(UnifiedRekapRow row) => row.weeklyDelta / 7.0;

  /// Perkiraan sisa hari kerja; null bila rata-rata harian belum positif.
  int? _daysLeft(int sisa, double avgDaily) {
    if (sisa <= 0) return 0;
    if (avgDaily <= 0) return null;
    return (sisa / avgDaily).ceil();
  }

  String _estimateLabel(int? days) {
    if (days == null) return '-';
    if (days == 0) return 'Selesai';
    final d = _targetDate.add(Duration(days: days));
    return '${d.day} ${_monthName(d.month)}';
  }

  double _submitSortValue(UnifiedRekapRow row) {
    switch (_submitSortKey) {
      case 'delta':
        return row.delta.toDouble();
      case 'week':
        return row.weeklyDelta.toDouble();
      case 'approved':
        return _statusOf(row, 'APPROVED Pengawas').toDouble();
      case 'awal':
        return _statusOf(row, 'DRAFT Awal').toDouble();
      case 'reject':
        return _statusOf(row, 'REJECTED Pengawas').toDouble();
      case 'revisi':
        return _statusOf(row, 'DRAFT Revisi').toDouble();
      case 'avg':
        return _avgDaily(row);
      case 'days':
        // Tanpa estimasi (rata-rata 0) diletakkan paling akhir.
        return (_daysLeft(_sisaSubmit(row), _avgDaily(row)) ?? 99999)
            .toDouble();
      case 'days_today':
        return (_daysLeft(_sisaSubmit(row), row.delta.toDouble()) ?? 99999)
            .toDouble();
      default:
        return _sisaSubmit(row).toDouble();
    }
  }

  List<UnifiedRekapRow> get _submittingSortedRows {
    final list = List<UnifiedRekapRow>.from(_rows);
    final asc = _submitSortAsc ? 1 : -1;
    list.sort((a, b) {
      if (_submitSortKey == 'title') {
        return a.title.compareTo(b.title) * asc;
      }
      final cmp = _submitSortValue(a).compareTo(_submitSortValue(b)) * asc;
      return cmp != 0 ? cmp : a.title.compareTo(b.title);
    });
    return list;
  }

  List<UnifiedRekapRow> get _openSortedRows {
    final list = List<UnifiedRekapRow>.from(_rows);
    final asc = _openSortAsc ? 1 : -1;
    list.sort((a, b) {
      if (_openSortByName) return a.title.compareTo(b.title) * asc;
      final cmp = _openCount(a).compareTo(_openCount(b)) * asc;
      return cmp != 0 ? cmp : a.title.compareTo(b.title);
    });
    return list;
  }

  String _formatSigned(int value) => value > 0 ? '+$value' : '$value';

  bool get _isToday {
    final now = DateTime.now();
    return _targetDate.year == now.year &&
        _targetDate.month == now.month &&
        _targetDate.day == now.day;
  }

  bool get _canGoBack =>
      (_role == 'pengawas' && _selectedPetugas != null) ||
      (_role == 'admin' &&
          (_selectedPengawas != null || _selectedPetugas != null));

  bool get _canDrill =>
      (_role == 'pengawas' && _selectedPetugas == null) ||
      (_role == 'admin' && _selectedPetugas == null);

  /// Baris level wilayah (SLS) dapat dibuka di peta bila callback tersedia.
  bool get _canOpenSlsOnMap => _isWilayahLevel && widget.onOpenSlsOnMap != null;

  /// Baris bisa ditekan bila bisa di-drill ATAU bisa dibuka di peta.
  bool get _canTapRow => _canDrill || _canOpenSlsOnMap;

  void _handleRowTap(UnifiedRekapRow row) {
    // Level wilayah = leaf: buka di peta untuk lihat progres langsung.
    if (_canOpenSlsOnMap) {
      widget.onOpenSlsOnMap!(row.unitId, _displayTitle(row));
      return;
    }
    if (!_canDrill) return;
    setState(() {
      if (_role == 'pengawas') {
        _selectedPetugas = row;
      } else if (_role == 'admin' &&
          (_adminViewMode == _AdminViewMode.allPetugas ||
              (_adminViewMode == _AdminViewMode.submitting &&
                  _submitByPetugas))) {
        // Mode "Semua Petugas": baris = petugas, langsung ke wilayah kerjanya
        // tanpa singgah ke level pengawas.
        _selectedPetugas = row;
      } else if (_role == 'admin' && _selectedPengawas == null) {
        _selectedPengawas = row;
      } else if (_role == 'admin') {
        _selectedPetugas = row;
      }
      _sortField = _SortField.delta;
      _sortDir = _SortDir.desc;
    });
    _loadData();
  }

  void _handleBack() {
    setState(() {
      if (_role == 'pengawas') {
        _selectedPetugas = null;
      } else if (_role == 'admin' && _selectedPetugas != null) {
        _selectedPetugas = null;
      } else {
        _selectedPengawas = null;
      }
      _sortField = _SortField.delta;
      _sortDir = _SortDir.desc;
    });
    _loadData();
  }

  void _prevDay() {
    setState(() {
      _targetDate = _targetDate.subtract(const Duration(days: 1));
    });
    _loadData();
  }

  void _nextDay() {
    if (_isToday) return;
    setState(() {
      _targetDate = _targetDate.add(const Duration(days: 1));
    });
    _loadData();
  }

  String get _pageTitle {
    switch (_role) {
      case 'pendata':
        return 'Dashboard Wilayah Saya';
      case 'pengawas':
        return _selectedPetugas == null
            ? 'Dashboard Petugas'
            : 'Detail ${_selectedPetugas!.title}';
      case 'admin':
        if (_selectedPetugas != null) {
          return 'Detail ${_selectedPetugas!.title}';
        }
        if (_selectedPengawas != null) {
          return 'Petugas — ${_selectedPengawas!.title}';
        }
        return 'Dashboard FASIH';
      default:
        return 'Dashboard';
    }
  }

  Color _accentColor(int delta) {
    final threshold = _deltaThreshold(_level);
    return delta >= threshold
        ? const Color(0xFF10B981)
        : const Color(0xFFEF4444);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF3F6FB),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? _buildError()
              : MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(_textScale)),
                  child: RefreshIndicator(
                    onRefresh: _loadData,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                      children: [
                        _buildHero(),
                        if (_canGoBack) ...[
                          const SizedBox(height: 12),
                          _buildBreadcrumb(),
                        ],
                        const SizedBox(height: 12),
                        _buildControls(),
                        const SizedBox(height: 12),
                        if (_rows.isEmpty)
                          _buildEmpty()
                        else if (_isOpenPengawasView)
                          _buildOpenPengawasTable(_openSortedRows)
                        else if (_isSubmittingView)
                          _buildSubmittingTable(_submittingSortedRows)
                        else if (_viewMode == _ViewMode.table)
                          _buildTableView(_tableSortedRows)
                        else if (_viewMode == _ViewMode.chart)
                          _buildChartView(_sortedRows)
                        else
                          ..._sortedRows.map(_buildCard),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  // ── Hero ────────────────────────────────────────────────────────────────────

  Widget _buildHero() {
    final roleLabel = _role.toUpperCase();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F4C81), Color(0xFF2D77D0), Color(0xFF7AB6FF)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2D77D0).withValues(alpha: 0.25),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.dashboard_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _pageTitle,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Role: $roleLabel',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              // 5 tile: memenuhi lebar saat cukup, menggulir horizontal saat sempit.
              const gap = 8.0;
              const count = 6;
              final tileW = max(
                120.0,
                (constraints.maxWidth - gap * (count - 1)) / count,
              );
              final tiles = <Widget>[
                _buildHeroStat(
                  width: tileW,
                  // Total penuh termasuk OPEN (= SUM kolom `total` snapshot),
                  // agar cocok dengan rincian di bawah yang menyertakan OPEN.
                  label: 'Total Kumulatif',
                  value: '${_totalAssignmentAll + _totalOpenAll}',
                  icon: Icons.assignment_rounded,
                  onTap: () => _showStatusDetail(
                    title: 'Detail Kumulatif',
                    totalLabel: 'Total Kumulatif',
                    totalValue: _totalAssignmentAll + _totalOpenAll,
                    statuses: _aggregatedStatusCumul,
                  ),
                ),
                _buildHeroStat(
                  width: tileW,
                  label: 'Terkirim (final)',
                  value: '$_totalTerkirimAll',
                  icon: Icons.task_alt_rounded,
                ),
                _buildHeroStat(
                  width: tileW,
                  label: 'Progress Hari Ini',
                  value: _formatSigned(_totalDeltaToday),
                  icon: Icons.trending_up_rounded,
                  highlight: true,
                  onTap: () => _showStatusDetail(
                    title: 'Detail Hari Ini',
                    totalLabel: 'Progress Hari Ini',
                    totalValue: _totalDeltaToday,
                    statuses: _aggregatedStatusToday,
                    isToday: true,
                  ),
                ),
                _buildHeroStat(
                  width: tileW,
                  label: 'Aktif Hari Ini',
                  value: '$_activeUnitsToday',
                  icon: Icons.groups_rounded,
                ),
                _buildHeroStat(
                  width: tileW,
                  label: 'Progress 7 Hari',
                  value: _formatSigned(_totalDeltaWeek),
                  icon: Icons.date_range_rounded,
                  highlight: true,
                  onTap: () => _showStatusDetail(
                    title: 'Detail 7 Hari Terakhir',
                    totalLabel: 'Progress 7 Hari',
                    totalValue: _totalDeltaWeek,
                    statuses: _aggregatedStatusWeek,
                    isToday: true,
                  ),
                ),
                _buildHeroStat(
                  width: tileW,
                  label: 'Aktif 7 Hari',
                  value: '$_activeUnitsWeek',
                  icon: Icons.groups_rounded,
                ),
              ];
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (int i = 0; i < tiles.length; i++) ...[
                      if (i > 0) const SizedBox(width: gap),
                      tiles[i],
                    ],
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          _buildDateNav(),
        ],
      ),
    );
  }

  Widget _buildHeroStat({
    required String label,
    required String value,
    required IconData icon,
    double? width,
    bool highlight = false,
    VoidCallback? onTap,
  }) {
    return SizedBox(
      width: width,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: highlight
                ? Colors.white.withValues(alpha: 0.22)
                : Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: onTap != null
                  ? Colors.white.withValues(alpha: 0.40)
                  : Colors.white.withValues(alpha: highlight ? 0.40 : 0.0),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: Colors.white70, size: 16),
                  if (onTap != null) ...[
                    const Spacer(),
                    Icon(
                      Icons.info_outline_rounded,
                      color: Colors.white.withValues(alpha: 0.7),
                      size: 13,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  maxLines: 1,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: highlight ? 22 : 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.75),
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showStatusDetail({
    required String title,
    required String totalLabel,
    required int totalValue,
    required Map<String, int> statuses,
    bool isToday = false,
  }) {
    final d = _targetDate;
    final dateLabel = _isToday
        ? 'Hari ini'
        : '${d.day.toString().padLeft(2, '0')} ${_monthName(d.month)} ${d.year}';
    final accent = isToday ? const Color(0xFF10B981) : const Color(0xFF2D77D0);
    final totalText = isToday ? _formatSigned(totalValue) : '$totalValue';

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        isToday
                            ? Icons.trending_up_rounded
                            : Icons.assignment_rounded,
                        color: accent,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          Text(
                            dateLabel,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blueGrey[500],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        totalText,
                        style: TextStyle(
                          color: accent,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  totalLabel,
                  style: TextStyle(
                    color: Colors.blueGrey[600],
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                if (statuses.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Text(
                      'Belum ada detail status.',
                      style: TextStyle(
                        color: Colors.blueGrey[500],
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 360),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: statuses.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final entry = statuses.entries.elementAt(index);
                        return _buildStatusDetailRow(entry, accent);
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showRowStatusDetail(UnifiedRekapRow row) {
    final d = _targetDate;
    final dateLabel = _isToday
        ? 'Hari ini'
        : '${d.day.toString().padLeft(2, '0')} ${_monthName(d.month)} ${d.year}';
    final todayAccent = const Color(0xFF10B981);
    final weekAccent = const Color(0xFF0E7490);
    final cumulAccent = const Color(0xFF2D77D0);
    final todaySection = _StatusDetailSection(
      title: 'Hari Ini',
      total: _formatSigned(row.delta),
      statuses: row.statusCountsToday,
      accent: todayAccent,
    );
    final weekSection = _StatusDetailSection(
      title: '7 Hari Terakhir',
      total: _formatSigned(row.weeklyDelta),
      statuses: row.statusCountsWeek,
      accent: weekAccent,
    );
    final cumulSection = _StatusDetailSection(
      title: 'Kumulatif',
      total: '${row.totalAssignment}',
      statuses: row.statusCounts,
      accent: cumulAccent,
    );
    // Section yang relevan dgn sort aktif ditaruh paling atas.
    final sections = switch (_sortField) {
      _SortField.delta => [todaySection, weekSection, cumulSection],
      _SortField.week => [weekSection, todaySection, cumulSection],
      _SortField.kumulatif => [cumulSection, todaySection, weekSection],
    };

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.58,
            minChildSize: 0.32,
            maxChildSize: 0.88,
            builder: (context, scrollController) {
              return ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 20),
                children: [
                  Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFF0F4C81,
                          ).withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.fact_check_rounded,
                          color: Color(0xFF0F4C81),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _displayTitle(row),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            if (_isWilayahLevel && _hasSubtitle(row))
                              Text(
                                row.subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.blueGrey[500],
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            Text(
                              dateLabel,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blueGrey[500],
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  for (final section in sections) ...[
                    _buildStatusDetailSection(section),
                    const SizedBox(height: 12),
                  ],
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildStatusDetailSection(_StatusDetailSection section) {
    final entries = section.statuses.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: section.accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: section.accent.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  section.title,
                  style: TextStyle(
                    color: section.accent,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: section.accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  section.total,
                  style: TextStyle(
                    color: section.accent,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (entries.isEmpty)
            Text(
              'Belum ada detail status.',
              style: TextStyle(
                color: Colors.blueGrey[500],
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            )
          else
            ...entries.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _buildStatusDetailRow(entry, section.accent),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusDetailRow(MapEntry<String, int> entry, Color accent) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              entry.key,
              style: const TextStyle(
                color: Color(0xFF334155),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            '${entry.value}',
            style: TextStyle(
              color: accent,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateNav() {
    final d = _targetDate;
    final label = _isToday
        ? 'Hari ini'
        : '${d.day.toString().padLeft(2, '0')} ${_monthName(d.month)} ${d.year}';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: _prevDay,
            icon: const Icon(Icons.chevron_left_rounded, color: Colors.white),
          ),
          Expanded(
            child: GestureDetector(
              onTap: _isToday
                  ? null
                  : () {
                      setState(() => _targetDate = DateTime.now());
                      _loadData();
                    },
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: _isToday ? null : _nextDay,
            icon: Icon(
              Icons.chevron_right_rounded,
              color: _isToday
                  ? Colors.white.withValues(alpha: 0.3)
                  : Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  // ── Breadcrumb ───────────────────────────────────────────────────────────────

  Widget _buildBreadcrumb() {
    final crumbs = <String>[];
    if (_role == 'admin') {
      crumbs.add(switch (_adminViewMode) {
        _AdminViewMode.allPetugas => 'Petugas',
        _AdminViewMode.openPengawas => 'Open Pengawas',
        _AdminViewMode.submitting =>
          _submitByPetugas ? 'Submitting Petugas' : 'Submitting Pengawas',
        _AdminViewMode.byPengawas => 'Pengawas',
      });
    }
    if (_role == 'pengawas') crumbs.add('Petugas');
    if (_selectedPengawas != null) crumbs.add(_selectedPengawas!.title);
    if (_selectedPetugas != null) crumbs.add(_selectedPetugas!.title);

    return Row(
      children: [
        TextButton.icon(
          onPressed: _handleBack,
          icon: const Icon(Icons.arrow_back_rounded),
          label: const Text('Kembali'),
        ),
        if (crumbs.isNotEmpty)
          Expanded(
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 6,
              children: crumbs
                  .map(
                    (c) => Chip(
                      label: Text(c, style: const TextStyle(fontSize: 12)),
                      backgroundColor: Colors.white,
                      side: BorderSide(
                        color: Colors.blueGrey.withValues(alpha: 0.2),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
      ],
    );
  }

  // ── Controls (sort) ──────────────────────────────────────────────────────────

  Widget _buildControls() {
    final showAdminToggle =
        _role == 'admin' &&
        _selectedPengawas == null &&
        _selectedPetugas == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showAdminToggle) ...[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildToggleChip(
                  label: 'Per Pengawas',
                  selected: _adminViewMode == _AdminViewMode.byPengawas,
                  onTap: () {
                    if (_adminViewMode == _AdminViewMode.byPengawas) return;
                    setState(() => _adminViewMode = _AdminViewMode.byPengawas);
                    _loadData();
                  },
                ),
                const SizedBox(width: 6),
                _buildToggleChip(
                  label: 'Semua Petugas',
                  selected: _adminViewMode == _AdminViewMode.allPetugas,
                  onTap: () {
                    if (_adminViewMode == _AdminViewMode.allPetugas) return;
                    setState(() => _adminViewMode = _AdminViewMode.allPetugas);
                    _loadData();
                  },
                ),
                const SizedBox(width: 6),
                _buildToggleChip(
                  label: 'Submitting',
                  selected: _adminViewMode == _AdminViewMode.submitting,
                  onTap: () {
                    if (_adminViewMode == _AdminViewMode.submitting) return;
                    setState(() {
                      _adminViewMode = _AdminViewMode.submitting;
                      _submitSortKey = 'sisa';
                      _submitSortAsc = false;
                    });
                    _loadData();
                  },
                ),
                const SizedBox(width: 6),
                _buildToggleChip(
                  label: 'Open Pengawas',
                  selected: _adminViewMode == _AdminViewMode.openPengawas,
                  onTap: () {
                    if (_adminViewMode == _AdminViewMode.openPengawas) return;
                    setState(() {
                      _adminViewMode = _AdminViewMode.openPengawas;
                      _openSortByName = false;
                      _openSortAsc = false;
                    });
                    _loadData();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (_isSimpleTableView)
          Row(
            children: [
              if (_isSubmittingRoot)
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildToggleChip(
                          label: 'Per Pengawas',
                          selected: !_submitByPetugas,
                          onTap: () {
                            if (!_submitByPetugas) return;
                            setState(() => _submitByPetugas = false);
                            _loadData();
                          },
                        ),
                        const SizedBox(width: 6),
                        _buildToggleChip(
                          label: 'Per Petugas',
                          selected: _submitByPetugas,
                          onTap: () {
                            if (_submitByPetugas) return;
                            setState(() => _submitByPetugas = true);
                            _loadData();
                          },
                        ),
                      ],
                    ),
                  ),
                )
              else
                const Spacer(),
              const SizedBox(width: 6),
              _buildTextScaleToggle(),
            ],
          )
        else
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildToggleChip(
                        label: 'Terkirim',
                        selected: _sortField == _SortField.kumulatif,
                        onTap: () =>
                            setState(() => _sortField = _SortField.kumulatif),
                      ),
                      const SizedBox(width: 6),
                      _buildToggleChip(
                        label: 'Hari Ini',
                        selected: _sortField == _SortField.delta,
                        onTap: () =>
                            setState(() => _sortField = _SortField.delta),
                      ),
                      const SizedBox(width: 6),
                      _buildToggleChip(
                        label: '7 Hari',
                        selected: _sortField == _SortField.week,
                        onTap: () =>
                            setState(() => _sortField = _SortField.week),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              _buildTextScaleToggle(),
              const SizedBox(width: 6),
              _buildSortToggle(),
              const SizedBox(width: 6),
              _buildViewModeToggle(),
            ],
          ),
      ],
    );
  }

  Widget _buildToggleChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF0F4C81) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? const Color(0xFF0F4C81)
                : Colors.blueGrey.withValues(alpha: 0.3),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : Colors.grey[700],
          ),
        ),
      ),
    );
  }

  // ── Card ─────────────────────────────────────────────────────────────────────

  Widget _buildCard(UnifiedRekapRow row) {
    final canOpen = _canTapRow;
    final isSortKumulatif = _sortField == _SortField.kumulatif;
    final isSortWeek = _sortField == _SortField.week;
    // Nilai progres yang jadi acuan badge & warna target (harian / mingguan).
    final progressVal = isSortWeek ? row.weeklyDelta : row.delta;
    final progressPositive = progressVal > 0;
    // Target mingguan = target harian × 7.
    final cardTarget =
        (_progressModeParam == 'pengawas' ? 77 : 11) * (isSortWeek ? 7 : 1);
    final targetReached = progressVal >= cardTarget;
    final showTargetColor = !isSortKumulatif;
    final statusColor = targetReached
        ? const Color(0xFF10B981)
        : const Color(0xFFEF4444);
    final badgeValue = isSortKumulatif
        ? '${row.totalTerkirim}'
        : (progressPositive ? '+$progressVal' : '$progressVal');
    final badgeColor = isSortKumulatif ? const Color(0xFF2D77D0) : statusColor;
    final todayLabel = row.delta > 0 ? '+${row.delta}' : '${row.delta}';
    final weekLabel = row.weeklyDelta > 0
        ? '+${row.weeklyDelta}'
        : '${row.weeklyDelta}';
    final isPengawasMode = _progressModeParam == 'pengawas';
    final cardColor = showTargetColor
        ? targetReached
              ? isPengawasMode
                    ? const Color(0xFFEFF6FF)
                    : const Color(0xFFF0FDF4)
              : const Color(0xFFFEF2F2)
        : Colors.white;
    final cardBorderColor = showTargetColor
        ? targetReached
              ? isPengawasMode
                    ? const Color(0xFFBFDBFE)
                    : const Color(0xFFBBF7D0)
              : const Color(0xFFFECACA)
        : const Color(0xFFE2E8F0);

    return GestureDetector(
      onTap: canOpen ? () => _handleRowTap(row) : null,
      onLongPress: () => _showRowStatusDetail(row),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cardBorderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 5,
                decoration: BoxDecoration(
                  color: showTargetColor
                      ? statusColor
                      : const Color(0xFFCBD5E1),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    bottomLeft: Radius.circular(16),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _displayTitle(row),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: badgeColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: badgeColor.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Text(
                              badgeValue,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: badgeColor,
                              ),
                            ),
                          ),
                          if (canOpen) ...[
                            const SizedBox(width: 4),
                            Icon(
                              _canOpenSlsOnMap
                                  ? Icons.map_rounded
                                  : Icons.chevron_right_rounded,
                              color: _canOpenSlsOnMap
                                  ? const Color(0xFF0F4C81)
                                  : Colors.grey[400],
                              size: _canOpenSlsOnMap ? 17 : 18,
                            ),
                          ],
                        ],
                      ),
                      if (_isWilayahLevel && _hasSubtitle(row)) ...[
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Icon(
                              Icons.location_on_rounded,
                              color: Colors.blueGrey[400],
                              size: 12,
                            ),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                row.subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.blueGrey[500],
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          if (showTargetColor) ...[
                            Icon(
                              targetReached
                                  ? Icons.check_circle_rounded
                                  : Icons.info_rounded,
                              color: statusColor,
                              size: 13,
                            ),
                            const SizedBox(width: 4),
                          ],
                          Expanded(
                            child: Text(
                              isSortKumulatif
                                  ? '$todayLabel hari ini  ·  $weekLabel 7 hari'
                                  : isSortWeek
                                  ? '${row.totalTerkirim} terkirim  ·  $todayLabel hari ini'
                                  : '${row.totalTerkirim} terkirim  ·  $weekLabel 7 hari',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Sort + View toggles ───────────────────────────────────────────────────────

  static const List<double> _textScaleSteps = [
    1.0,
    1.2,
    1.5,
    1.8,
    2.2,
    2.6,
    3.0,
  ];

  void _cycleTextScale() {
    final idx = _textScaleSteps.indexOf(_textScale);
    setState(() {
      _textScale = _textScaleSteps[(idx + 1) % _textScaleSteps.length];
    });
  }

  Widget _buildTextScaleToggle() {
    final active = _textScale > 1.0;
    return GestureDetector(
      onTap: _cycleTextScale,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFF0F4C81).withValues(alpha: 0.08)
              : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active
                ? const Color(0xFF0F4C81).withValues(alpha: 0.4)
                : Colors.blueGrey.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.format_size_rounded,
              size: 12,
              color: active ? const Color(0xFF0F4C81) : Colors.blueGrey[500],
            ),
            const SizedBox(width: 4),
            Text(
              _textScale <= 1.0
                  ? 'A'
                  : _textScale <= 1.2
                  ? 'A+'
                  : _textScale <= 1.5
                  ? 'A++'
                  : _textScale <= 1.8
                  ? 'A+++'
                  : _textScale <= 2.2
                  ? '2×'
                  : _textScale <= 2.6
                  ? '2.5×'
                  : '3×',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: active ? const Color(0xFF0F4C81) : Colors.blueGrey[500],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSortToggle() {
    final isAsc = _sortDir == _SortDir.asc;
    return GestureDetector(
      onTap: () =>
          setState(() => _sortDir = isAsc ? _SortDir.desc : _SortDir.asc),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.blueGrey.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isAsc ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
              size: 12,
              color: const Color(0xFF0F4C81),
            ),
            const SizedBox(width: 4),
            Text(
              isAsc ? 'A-Z' : 'Z-A',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F4C81),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildViewModeToggle() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.blueGrey.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _viewModeBtn(Icons.view_agenda_rounded, _ViewMode.card),
          _viewModeBtn(Icons.table_rows_rounded, _ViewMode.table),
          _viewModeBtn(Icons.bar_chart_rounded, _ViewMode.chart),
        ],
      ),
    );
  }

  Widget _viewModeBtn(IconData icon, _ViewMode mode) {
    final sel = _viewMode == mode;
    return GestureDetector(
      onTap: () => setState(() => _viewMode = mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        decoration: BoxDecoration(
          color: sel ? const Color(0xFF0F4C81) : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Icon(
          icon,
          size: 14,
          color: sel ? Colors.white : Colors.blueGrey[400],
        ),
      ),
    );
  }

  // ── Table view ────────────────────────────────────────────────────────────────

  // ── Tabel Submitting ────────────────────────────────────────────────────────
  // Progres harian/mingguan + rincian status yang masih harus dikirim, dengan
  // dua dasar perkiraan selesai: rata-rata 7 hari dan capaian hari ini.
  // Baris dapat di-expand untuk melihat seluruh angka tanpa geser samping.

  Widget _buildSubmittingTable(List<UnifiedRekapRow> rows) {
    const double hPad = 24.0;
    // Lebar minimum tiap kolom (ikut skala teks). Saat layar lebih lebar dari
    // total minimum, sisa ruang dibagi proporsional agar tabel penuh selebar
    // area; saat lebih sempit, tabel bisa digeser mendatar.
    final double minNameW = 150.0 * _textScale;
    final double minNumW = 58.0 * _textScale;
    final double minEstW = 78.0 * _textScale;

    const headerStyle = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: Color(0xFF64748B),
    );
    const activeColor = Color(0xFF0F4C81);
    const numStyle = TextStyle(fontSize: 11, fontWeight: FontWeight.w600);

    int sumOf(int Function(UnifiedRekapRow) pick) =>
        rows.fold<int>(0, (acc, r) => acc + pick(r));

    final tDelta = sumOf((r) => r.delta);
    final tWeek = sumOf((r) => r.weeklyDelta);
    final tApproved = sumOf((r) => _statusOf(r, 'APPROVED Pengawas'));
    final tAwal = sumOf((r) => _statusOf(r, 'DRAFT Awal'));
    final tReject = sumOf((r) => _statusOf(r, 'REJECTED Pengawas'));
    final tRevisi = sumOf((r) => _statusOf(r, 'DRAFT Revisi'));
    final tSisa = tAwal + tReject + tRevisi;
    final tAvg = tWeek / 7.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final double minTotal = hPad + minNameW + minNumW * 10 + minEstW * 2;
        final double tableW = max(constraints.maxWidth, minTotal);
        // Bobot kolom: nama paling lebar, kolom tanggal sedikit lebih lebar
        // dari kolom angka biasa.
        const double nameUnits = 150.0 / 58.0;
        const double estUnits = 78.0 / 58.0;
        final double unit = (tableW - hPad) / (nameUnits + 10 + estUnits * 2);
        final double nameW = unit * nameUnits;
        final double numW = unit;
        final double estW = unit * estUnits;

        Widget th(
          String label,
          String key,
          double w, {
          bool leftAlign = false,
        }) {
          final active = _submitSortKey == key;
          return GestureDetector(
            onTap: () => setState(() {
              if (_submitSortKey == key) {
                _submitSortAsc = !_submitSortAsc;
              } else {
                _submitSortKey = key;
                _submitSortAsc =
                    key == 'title' || key == 'days' || key == 'days_today';
              }
            }),
            child: SizedBox(
              width: w,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: leftAlign
                    ? Alignment.centerLeft
                    : Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      softWrap: false,
                      style: active
                          ? headerStyle.copyWith(color: activeColor)
                          : headerStyle,
                    ),
                    if (active) ...[
                      const SizedBox(width: 2),
                      Icon(
                        _submitSortAsc
                            ? Icons.arrow_upward_rounded
                            : Icons.arrow_downward_rounded,
                        size: 10,
                        color: activeColor,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }

        Widget td(double w, String text, {TextStyle? style}) {
          return SizedBox(
            width: w,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                text,
                maxLines: 1,
                softWrap: false,
                style: style ?? numStyle,
              ),
            ),
          );
        }

        Widget dataRow({
          required Widget name,
          required int delta,
          required int week,
          required int approved,
          required int awal,
          required int reject,
          required int revisi,
          required int sisa,
          required double avgWeek,
          required double avgToday,
          Color? background,
          bool bold = false,
        }) {
          final base = bold
              ? numStyle.copyWith(fontWeight: FontWeight.w800)
              : numStyle;
          final daysWeek = _daysLeft(sisa, avgWeek);
          final daysToday = _daysLeft(sisa, avgToday);
          return Container(
            color: background,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              children: [
                SizedBox(width: nameW, child: name),
                td(
                  numW,
                  _formatSigned(delta),
                  style: base.copyWith(
                    color: delta > 0
                        ? const Color(0xFF10B981)
                        : Colors.grey[400],
                  ),
                ),
                td(
                  numW,
                  _formatSigned(week),
                  style: base.copyWith(
                    color: week > 0
                        ? const Color(0xFF0E7490)
                        : Colors.grey[400],
                  ),
                ),
                td(
                  numW,
                  '$approved',
                  style: base.copyWith(color: const Color(0xFF059669)),
                ),
                td(numW, '$awal', style: base),
                td(numW, '$reject', style: base),
                td(numW, '$revisi', style: base),
                td(
                  numW,
                  '$sisa',
                  style: base.copyWith(
                    fontWeight: FontWeight.w800,
                    color: sisa > 0
                        ? const Color(0xFFEF4444)
                        : Colors.grey[400],
                  ),
                ),
                td(
                  numW,
                  avgWeek > 0 ? avgWeek.toStringAsFixed(1) : '0',
                  style: base.copyWith(color: Colors.blueGrey[600]),
                ),
                td(
                  numW,
                  daysWeek == null ? '-' : '$daysWeek',
                  style: base.copyWith(
                    fontWeight: FontWeight.w800,
                    color: daysWeek == null
                        ? Colors.grey[400]
                        : const Color(0xFFB45309),
                  ),
                ),
                td(
                  estW,
                  _estimateLabel(daysWeek),
                  style: base.copyWith(color: const Color(0xFF0F4C81)),
                ),
                td(
                  numW,
                  daysToday == null ? '-' : '$daysToday',
                  style: base.copyWith(
                    fontWeight: FontWeight.w800,
                    color: daysToday == null
                        ? Colors.grey[400]
                        : const Color(0xFF7C3AED),
                  ),
                ),
                td(
                  estW,
                  _estimateLabel(daysToday),
                  style: base.copyWith(color: const Color(0xFF6D28D9)),
                ),
              ],
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: tableW,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          color: const Color(0xFFF1F5F9),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              th('Nama', 'title', nameW, leftAlign: true),
                              th('Hari Ini', 'delta', numW),
                              th('7 Hari', 'week', numW),
                              th('Approved', 'approved', numW),
                              th('Draft Awal', 'awal', numW),
                              th('Rejected', 'reject', numW),
                              th('Draft Revisi', 'revisi', numW),
                              th('Total Sisa', 'sisa', numW),
                              th('Rata²/Hari', 'avg', numW),
                              th('Sisa Hari (7h)', 'days', numW),
                              SizedBox(
                                width: estW,
                                child: const FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerRight,
                                  child: Text(
                                    'Selesai (7h)',
                                    maxLines: 1,
                                    softWrap: false,
                                    style: headerStyle,
                                  ),
                                ),
                              ),
                              th('Sisa Hari (Hr Ini)', 'days_today', numW),
                              SizedBox(
                                width: estW,
                                child: const FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerRight,
                                  child: Text(
                                    'Selesai (Hr Ini)',
                                    maxLines: 1,
                                    softWrap: false,
                                    style: headerStyle,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        for (int i = 0; i < rows.length; i++) ...[
                          if (i > 0)
                            Divider(
                              height: 1,
                              color: Colors.blueGrey.withValues(alpha: 0.08),
                            ),
                          _buildSubmittingRow(rows[i], dataRow: dataRow),
                        ],
                        Divider(
                          height: 1,
                          color: Colors.blueGrey.withValues(alpha: 0.15),
                        ),
                        dataRow(
                          background: const Color(0xFFF8FAFC),
                          bold: true,
                          name: const Text(
                            'TOTAL',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF475569),
                            ),
                          ),
                          delta: tDelta,
                          week: tWeek,
                          approved: tApproved,
                          awal: tAwal,
                          reject: tReject,
                          revisi: tRevisi,
                          sisa: tSisa,
                          avgWeek: tAvg,
                          avgToday: tDelta.toDouble(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Ketuk baris pengawas untuk melihat daftar petugasnya. '
              'Total Sisa = Draft Awal + Rejected + Draft Revisi. '
              'Rata²/Hari = progres 7 hari ÷ 7; kolom "(7h)" memakai angka itu, '
              'kolom "(Hr Ini)" memakai capaian hari ini sebagai laju harian. '
              'Sisa Hari = Total Sisa ÷ laju, dibulatkan ke atas, dihitung dari '
              '${_targetDate.day} ${_monthName(_targetDate.month)} '
              '${_targetDate.year}. Tanda "-" berarti lajunya belum positif '
              'sehingga belum bisa diperkirakan.',
              style: TextStyle(
                fontSize: 10.5,
                height: 1.4,
                color: Colors.blueGrey[400],
              ),
            ),
          ],
        );
      },
    );
  }

  /// Satu baris tabel Submitting. Baris pengawas dapat ditekan untuk melihat
  /// daftar petugas di bawahnya.
  Widget _buildSubmittingRow(
    UnifiedRekapRow row, {
    required Widget Function({
      required Widget name,
      required int delta,
      required int week,
      required int approved,
      required int awal,
      required int reject,
      required int revisi,
      required int sisa,
      required double avgWeek,
      required double avgToday,
      Color? background,
      bool bold,
    })
    dataRow,
  }) {
    final sisa = _sisaSubmit(row);
    final canOpen = _canDrill;

    final content = dataRow(
      name: Row(
        children: [
          Expanded(
            child: Text(
              row.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          if (canOpen)
            Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: Colors.blueGrey[300],
            ),
        ],
      ),
      delta: row.delta,
      week: row.weeklyDelta,
      approved: _statusOf(row, 'APPROVED Pengawas'),
      awal: _statusOf(row, 'DRAFT Awal'),
      reject: _statusOf(row, 'REJECTED Pengawas'),
      revisi: _statusOf(row, 'DRAFT Revisi'),
      sisa: sisa,
      avgWeek: _avgDaily(row),
      avgToday: row.delta.toDouble(),
    );

    if (!canOpen) return content;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _handleRowTap(row),
      child: content,
    );
  }

  // ── Tabel ringkas: Open per Pengawas ────────────────────────────────────────
  // Hanya dua kolom (nama pengawas + jumlah OPEN), tanpa drill-down. Lebar
  // kolom nama dibatasi agar angka Open tetap berdekatan dengan namanya.

  Widget _buildOpenPengawasTable(List<UnifiedRekapRow> rows) {
    const headerStyle = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: Color(0xFF64748B),
    );
    const activeColor = Color(0xFF0F4C81);
    const double hPad = 24.0; // 12 kiri + 12 kanan
    const double gap = 8.0;
    final totalOpen = rows.fold<int>(0, (sum, r) => sum + _openCount(r));
    // Lebar kolom angka mengikuti jumlah digit terbesar & skala teks aktif,
    // supaya angka tidak terpotong/turun baris saat tulisan diperbesar.
    final digits = totalOpen.toString().length.clamp(2, 6);
    final double numW = (14.0 + 9.5 * digits) * _textScale;

    Widget header(String label, bool byName, {bool leftAlign = false}) {
      final active = _openSortByName == byName;
      return GestureDetector(
        onTap: () => setState(() {
          if (_openSortByName == byName) {
            _openSortAsc = !_openSortAsc;
          } else {
            _openSortByName = byName;
            _openSortAsc = byName;
          }
        }),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: leftAlign ? Alignment.centerLeft : Alignment.centerRight,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: leftAlign
                ? MainAxisAlignment.start
                : MainAxisAlignment.end,
            children: [
              Text(
                label,
                style: active
                    ? headerStyle.copyWith(color: activeColor)
                    : headerStyle,
              ),
              if (active) ...[
                const SizedBox(width: 2),
                Icon(
                  _openSortAsc
                      ? Icons.arrow_upward_rounded
                      : Icons.arrow_downward_rounded,
                  size: 10,
                  color: activeColor,
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final available = constraints.maxWidth - hPad - gap - numW;
            final nameW = available <= 140.0
                ? available
                : (constraints.maxWidth * 0.55).clamp(140.0, available);

            Widget line({
              required Widget name,
              required Widget value,
              Color? background,
            }) {
              return Container(
                color: background,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    SizedBox(width: nameW, child: name),
                    const SizedBox(width: gap),
                    SizedBox(width: numW, child: value),
                  ],
                ),
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  color: const Color(0xFFF1F5F9),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: nameW,
                        child: header('Nama Pengawas', true, leftAlign: true),
                      ),
                      const SizedBox(width: gap),
                      SizedBox(width: numW, child: header('Open', false)),
                    ],
                  ),
                ),
                for (int i = 0; i < rows.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      color: Colors.blueGrey.withValues(alpha: 0.08),
                    ),
                  line(
                    name: Text(
                      rows[i].title,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    value: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        '${_openCount(rows[i])}',
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: _openCount(rows[i]) > 0
                              ? const Color(0xFFEF4444)
                              : Colors.grey[400],
                        ),
                      ),
                    ),
                  ),
                ],
                line(
                  background: const Color(0xFFF8FAFC),
                  name: const Text(
                    'Total Open',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF475569),
                    ),
                  ),
                  value: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      '$totalOpen',
                      maxLines: 1,
                      softWrap: false,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F4C81),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildTableView(List<UnifiedRekapRow> rows) {
    // Collect all status keys sorted by aggregate total desc
    final keyTotals = <String, int>{};
    for (final r in rows) {
      for (final e in r.statusCounts.entries) {
        keyTotals[e.key] = (keyTotals[e.key] ?? 0) + e.value;
      }
    }
    final statusKeys =
        (keyTotals.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
            .map((e) => e.key)
            .toList();

    final decoration = BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 8,
          offset: const Offset(0, 3),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // ≥560 wide = desktop: fixed-width columns + status cols + horiz scroll
        // <560 wide = mobile : Expanded columns, base cols only, no horiz scroll
        final isDesktop = constraints.maxWidth >= 560;

        return Container(
          decoration: decoration,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: isDesktop
                ? _buildDesktopTable(rows, statusKeys, constraints.maxWidth)
                : _buildMobileTable(rows, statusKeys),
          ),
        );
      },
    );
  }

  // Desktop: columns fill full width proportionally; horizontal scroll only
  // when many status cols push content beyond availableWidth.
  // Subtitle/email intentionally omitted.
  Widget _buildDesktopTable(
    List<UnifiedRekapRow> rows,
    List<String> statusKeys,
    double availableWidth,
  ) {
    // Proportional widths: name = 3 units, each num col = 1 unit.
    const double hPad = 24.0; // 12px left + 12px right padding
    const double minNumW = 52.0;
    const double minNameW = 110.0;
    final int numCols = 5 + statusKeys.length;
    final double minTotal = minNameW + numCols * minNumW + hPad;
    final double tableWidth = max(availableWidth, minTotal);
    final double unit = (tableWidth - hPad) / (3 + numCols);
    final double nameW = unit * 3;
    final double numW = unit;

    const headerStyle = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: Color(0xFF64748B),
    );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: tableWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              color: const Color(0xFFF1F5F9),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  _sortableTh(
                    'Nama',
                    'title',
                    nameW,
                    headerStyle,
                    leftAlign: true,
                  ),
                  _sortableTh('Kumul', 'kumul', numW, headerStyle),
                  _sortableTh('Submitted', 'terkirim', numW, headerStyle),
                  _sortableTh('Hr Ini', 'delta', numW, headerStyle),
                  _sortableTh('7 Hari', 'week', numW, headerStyle),
                  _sortableTh('Kmrn', 'kmrn', numW, headerStyle),
                  for (final k in statusKeys)
                    _sortableTh(k, k, numW, headerStyle),
                ],
              ),
            ),
            for (int i = 0; i < rows.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  color: Colors.blueGrey.withValues(alpha: 0.08),
                ),
              _buildDesktopTableRow(rows[i], statusKeys, nameW, numW),
            ],
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopTableRow(
    UnifiedRekapRow row,
    List<String> statusKeys,
    double nameW,
    double numW,
  ) {
    final color = _accentColor(row.delta);
    final canOpen = _canTapRow;
    final delta = row.delta;
    final deltaStr = delta > 0 ? '+$delta' : '$delta';
    final weekDelta = row.weeklyDelta;

    return GestureDetector(
      onTap: canOpen ? () => _handleRowTap(row) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(
          children: [
            SizedBox(
              width: nameW,
              child: Row(
                children: [
                  Container(
                    width: 3,
                    height: 26,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _displayTitle(row),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (_isWilayahLevel && _hasSubtitle(row))
                          Text(
                            row.subtitle,
                            style: TextStyle(
                              fontSize: 9.5,
                              color: Colors.blueGrey[400],
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: numW,
              child: Text(
                '${row.totalAssignment}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2D77D0),
                ),
              ),
            ),
            SizedBox(
              width: numW,
              child: Text(
                '${row.totalTerkirim}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF059669),
                ),
              ),
            ),
            SizedBox(
              width: numW,
              child: Text(
                deltaStr,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: delta > 0 ? const Color(0xFF10B981) : Colors.grey[400],
                ),
              ),
            ),
            SizedBox(
              width: numW,
              child: Text(
                weekDelta > 0 ? '+$weekDelta' : '$weekDelta',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: weekDelta > 0
                      ? const Color(0xFF0E7490)
                      : Colors.grey[400],
                ),
              ),
            ),
            SizedBox(
              width: numW,
              child: Text(
                '${row.yesterdayCount}',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
            ),
            for (final k in statusKeys)
              SizedBox(
                width: numW,
                child: Text(
                  '${row.statusCounts[k] ?? 0}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Mobile: sticky Nama column (fixed left) + scrollable numeric/status cols.
  // Fixed row heights keep both sides aligned without IntrinsicHeight.
  Widget _buildMobileTable(
    List<UnifiedRekapRow> rows,
    List<String> statusKeys,
  ) {
    const double nameW = 100.0;
    const double numW = 54.0;
    const double headerH = 40.0;
    // Baris wilayah butuh 2 baris teks (SLS + kelurahan) → lebih tinggi.
    final double rowH = _isWilayahLevel ? 48.0 : 36.0;
    final divColor = Colors.blueGrey.withValues(alpha: 0.08);
    const headerStyle = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: Color(0xFF64748B),
    );

    // ── Sticky left: Nama ────────────────────────────────────────────────────
    final nameColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: headerH,
          color: const Color(0xFFF1F5F9),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.centerLeft,
          child: _sortableTh(
            'Nama',
            'title',
            nameW - 16,
            headerStyle,
            leftAlign: true,
          ),
        ),
        for (int i = 0; i < rows.length; i++) ...[
          if (i > 0) Divider(height: 1, color: divColor),
          GestureDetector(
            onTap: _canTapRow ? () => _handleRowTap(rows[i]) : null,
            child: SizedBox(
              width: nameW,
              height: rowH,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    Container(
                      width: 3,
                      height: 20,
                      decoration: BoxDecoration(
                        color: _accentColor(rows[i].delta),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _displayTitle(rows[i]),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (_isWilayahLevel && _hasSubtitle(rows[i]))
                            Text(
                              rows[i].subtitle,
                              style: TextStyle(
                                fontSize: 9,
                                color: Colors.blueGrey[400],
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 4),
      ],
    );

    // ── Scrollable right: numeric + status cols ───────────────────────────────
    final numColumns = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: headerH,
            color: const Color(0xFFF1F5F9),
            child: Row(
              children: [
                _sortableTh('Kumul', 'kumul', numW, headerStyle),
                _sortableTh('Submitted', 'terkirim', numW, headerStyle),
                _sortableTh('Hr Ini', 'delta', numW, headerStyle),
                _sortableTh('7 Hari', 'week', numW, headerStyle),
                _sortableTh('Kmrn', 'kmrn', numW, headerStyle),
                for (final k in statusKeys)
                  _sortableTh(k, k, numW, headerStyle),
              ],
            ),
          ),
          for (int i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, color: divColor),
            GestureDetector(
              onTap: _canTapRow ? () => _handleRowTap(rows[i]) : null,
              child: SizedBox(
                height: rowH,
                child: Row(
                  children: [
                    _tableNumCell(
                      '${rows[i].totalAssignment}',
                      numW,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF2D77D0),
                      ),
                    ),
                    _tableNumCell(
                      '${rows[i].totalTerkirim}',
                      numW,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF059669),
                      ),
                    ),
                    _tableNumCell(
                      rows[i].delta > 0
                          ? '+${rows[i].delta}'
                          : '${rows[i].delta}',
                      numW,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: rows[i].delta > 0
                            ? const Color(0xFF10B981)
                            : Colors.grey[400],
                      ),
                    ),
                    _tableNumCell(
                      rows[i].weeklyDelta > 0
                          ? '+${rows[i].weeklyDelta}'
                          : '${rows[i].weeklyDelta}',
                      numW,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: rows[i].weeklyDelta > 0
                            ? const Color(0xFF0E7490)
                            : Colors.grey[400],
                      ),
                    ),
                    _tableNumCell(
                      '${rows[i].yesterdayCount}',
                      numW,
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                    for (final k in statusKeys)
                      _tableNumCell(
                        '${rows[i].statusCounts[k] ?? 0}',
                        numW,
                        style: const TextStyle(fontSize: 11),
                      ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 4),
        ],
      ),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Sticky column with subtle right divider
        Container(
          decoration: BoxDecoration(
            border: Border(
              right: BorderSide(
                color: Colors.blueGrey.withValues(alpha: 0.18),
                width: 1,
              ),
            ),
          ),
          child: nameColumn,
        ),
        Expanded(child: numColumns),
      ],
    );
  }

  Widget _tableNumCell(String text, double w, {required TextStyle style}) =>
      SizedBox(
        width: w,
        child: Text(text, textAlign: TextAlign.center, style: style),
      );

  // ── Chart view ────────────────────────────────────────────────────────────────

  Widget _buildChartView(List<UnifiedRekapRow> rows) {
    final values = rows.map((r) => _sortValue(r)).toList();
    final maxVal = values.fold(0, (prev, v) => v > prev ? v : prev);
    final chartLabel = switch (_sortField) {
      _SortField.kumulatif => 'Terkirim',
      _SortField.delta => 'Hari Ini',
      _SortField.week => '7 Hari Terakhir',
    };

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            chartLabel,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 10),
          for (int i = 0; i < rows.length; i++) ...[
            _buildBarRow(rows[i], values[i], maxVal),
            if (i < rows.length - 1) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  Widget _buildBarRow(UnifiedRekapRow row, int val, int maxVal) {
    final color = _accentColor(row.delta);
    final canOpen = _canTapRow;
    final fraction = (maxVal == 0 || val <= 0)
        ? 0.0
        : (val / maxVal).clamp(0.0, 1.0);

    final showWilayah = _isWilayahLevel && _hasSubtitle(row);
    return GestureDetector(
      onTap: canOpen ? () => _handleRowTap(row) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label baris penuh: ikut melebar saat teks diperbesar.
          Text(
            _displayTitle(row),
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (showWilayah)
            Text(
              row.subtitle,
              style: TextStyle(
                fontSize: 9.5,
                color: Colors.blueGrey[400],
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Container(
                      height: 14,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: fraction,
                      child: Container(
                        height: 14,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$val',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Empty / Error ─────────────────────────────────────────────────────────────

  Widget _buildEmpty() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Icon(Icons.inbox_rounded, size: 40, color: Colors.grey[400]),
          const SizedBox(height: 10),
          Text(
            'Belum ada data untuk scope ini.',
            style: TextStyle(color: Colors.grey[600], fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: Colors.red,
            ),
            const SizedBox(height: 12),
            const Text(
              'Gagal memuat dashboard',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? 'Terjadi kesalahan.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[700]),
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Coba Lagi'),
            ),
          ],
        ),
      ),
    );
  }

  String _monthName(int m) {
    const n = [
      '',
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
    return n[m];
  }
}
