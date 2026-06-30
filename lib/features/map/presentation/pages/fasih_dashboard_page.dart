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
  final Map<String, int> statusCounts;
  final int todayCount;
  final int yesterdayCount;
  final int delta;
  final Map<String, int> statusCountsToday;

  const UnifiedRekapRow({
    required this.unitId,
    required this.title,
    required this.subtitle,
    required this.totalAssignment,
    required this.statusCounts,
    required this.todayCount,
    required this.yesterdayCount,
    required this.delta,
    required this.statusCountsToday,
  });
}

List<UnifiedRekapRow> _mergeRows(
  List<FasihRekapRow> rekap,
  List<DailyContributionRow> daily,
) {
  final dailyMap = {for (final d in daily) d.unitId: d};
  return rekap.map((r) {
    final d = dailyMap[r.unitId];
    return UnifiedRekapRow(
      unitId: r.unitId,
      title: r.title,
      subtitle: r.subtitle,
      totalAssignment: r.totalAssignment,
      statusCounts: r.statusCounts,
      todayCount: d?.todayCount ?? 0,
      yesterdayCount: d?.yesterdayCount ?? 0,
      delta: d?.delta ?? 0,
      statusCountsToday: d?.statusCountsToday ?? {},
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

enum _SortField { kumulatif, delta }

enum _SortDir { asc, desc }

enum _AdminViewMode { byPengawas, allPetugas }

enum _ViewMode { card, table, chart }

// ── Page ─────────────────────────────────────────────────────────────────────

class FasihDashboardPage extends StatefulWidget {
  const FasihDashboardPage({super.key});

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
  int _totalDeltaToday = 0;
  int _activeUnitsToday = 0;
  String _level = '';

  DateTime _targetDate = DateTime.now();
  _SortField _sortField = _SortField.delta;
  _SortDir _sortDir = _SortDir.desc;
  _AdminViewMode _adminViewMode = _AdminViewMode.byPengawas;
  _ViewMode _viewMode = _ViewMode.card;
  double _textScale = 1.0;
  String? _tableSortKey;
  bool _tableSortAsc = true;

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

      // admin mode "Semua Petugas": abaikan drill pengawas untuk query
      final effectivePengawasId =
          (role == 'admin' &&
              _adminViewMode == _AdminViewMode.allPetugas &&
              _selectedPetugas == null)
          ? null
          : pengawasId;

      final isAllPetugas =
          role == 'admin' &&
          _adminViewMode == _AdminViewMode.allPetugas &&
          _selectedPetugas == null;

      final results = await Future.wait([
        _fetchRekap(role, effectivePengawasId, petugasId),
        _dailyService.fetchDailyContribution(
          targetDate: _targetDate,
          pengawasId: effectivePengawasId,
          petugasId: petugasId,
          allPetugas: isAllPetugas,
        ),
      ]);

      final rekapPayload = results[0] as FasihRekapPayload;
      final dailyPayload = results[1] as DailyContributionPayload;

      final merged = _mergeRows(rekapPayload.rows, dailyPayload.rows);

      if (!mounted) return;
      setState(() {
        _profile = profile;
        _level = dailyPayload.level.isNotEmpty
            ? dailyPayload.level
            : _inferLevel(role, effectivePengawasId, petugasId);
        _rows = merged;
        _totalAssignmentAll = rekapPayload.summary.totalAssignments;
        _totalDeltaToday = dailyPayload.summary.totalDelta;
        _activeUnitsToday = merged.where((r) => r.delta > 0).length;
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
    String role,
    String? pengawasId,
    String? petugasId,
  ) {
    switch (role) {
      case 'pendata':
        return _rekapService.fetchPendataWilayah(
          sortBy: 'title',
          sortDir: 'asc',
        );
      case 'pengawas':
        if (petugasId != null) {
          return _rekapService.fetchPengawasWilayahPetugas(
            petugasId: petugasId,
            sortBy: 'title',
            sortDir: 'asc',
          );
        }
        return _rekapService.fetchPengawasPetugas(
          sortBy: 'total_assignment',
          sortDir: 'desc',
        );
      case 'admin':
        if (petugasId != null) {
          return _rekapService.fetchAdminWilayahByPetugas(
            petugasId: petugasId,
            sortBy: 'title',
            sortDir: 'asc',
          );
        }
        if (pengawasId != null) {
          return _rekapService.fetchAdminPetugasByPengawas(
            pengawasId: pengawasId,
            sortBy: 'total_assignment',
            sortDir: 'desc',
          );
        }
        if (_adminViewMode == _AdminViewMode.allPetugas) {
          return _rekapService.fetchAdminPetugas(
            sortBy: 'total_assignment',
            sortDir: 'desc',
          );
        }
        return _rekapService.fetchAdminPengawas(
          sortBy: 'total_assignment',
          sortDir: 'desc',
        );
      default:
        return Future.value(FasihRekapPayload.empty());
    }
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

  List<UnifiedRekapRow> get _sortedRows {
    final sorted = List<UnifiedRekapRow>.from(_rows);
    sorted.sort((a, b) {
      final va = _sortField == _SortField.kumulatif
          ? a.totalAssignment
          : a.delta;
      final vb = _sortField == _SortField.kumulatif
          ? b.totalAssignment
          : b.delta;
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
        case 'delta':
          return a.delta.compareTo(b.delta) * asc;
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

  void _handleRowTap(UnifiedRekapRow row) {
    if (!_canDrill) return;
    setState(() {
      if (_role == 'pengawas') {
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
          Row(
            children: [
              _buildHeroStat(
                label: 'Total Kumulatif',
                value: '$_totalAssignmentAll',
                icon: Icons.assignment_rounded,
              ),
              const SizedBox(width: 12),
              _buildHeroStat(
                label: 'Progress Hari Ini',
                value: '+$_totalDeltaToday',
                icon: Icons.trending_up_rounded,
                highlight: true,
              ),
              const SizedBox(width: 12),
              _buildHeroStat(
                label: 'Aktif Hari Ini',
                value: '$_activeUnitsToday',
                icon: Icons.groups_rounded,
              ),
            ],
          ),
          if (_aggregatedStatusCumul.isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildStatusBreakdown(),
          ],
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
    bool highlight = false,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: highlight
              ? Colors.white.withValues(alpha: 0.22)
              : Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: highlight
              ? Border.all(color: Colors.white.withValues(alpha: 0.4))
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Colors.white70, size: 16),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                color: Colors.white,
                fontSize: highlight ? 22 : 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75),
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBreakdown() {
    final cumul = _aggregatedStatusCumul;
    final today = _aggregatedStatusToday;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Text(
          //   'KUMULATIF',
          //   style: TextStyle(
          //     color: Colors.white.withValues(alpha: 0.55),
          //     fontSize: 9,
          //     fontWeight: FontWeight.w700,
          //     letterSpacing: 0.8,
          //   ),
          // ),
          const SizedBox(height: 5),
          Wrap(
            spacing: 5,
            runSpacing: 4,
            children: cumul.entries
                .map((e) => _statusPill(e.key, '${e.value}'))
                .toList(),
          ),
          // if (today.isNotEmpty) ...[
          //   const SizedBox(height: 8),
          //   Container(height: 0.5, color: Colors.white.withValues(alpha: 0.15)),
          //   const SizedBox(height: 6),
          //   Text(
          //     'HARI INI',
          //     style: TextStyle(
          //       color: Colors.white.withValues(alpha: 0.55),
          //       fontSize: 9,
          //       fontWeight: FontWeight.w700,
          //       letterSpacing: 0.8,
          //     ),
          //   ),
          //   const SizedBox(height: 5),
          //   Wrap(
          //     spacing: 5,
          //     runSpacing: 4,
          //     children: today.entries
          //         .map((e) => _statusPill(e.key, '+${e.value}', isToday: true))
          //         .toList(),
          //   ),
          // ],
        ],
      ),
    );
  }

  Widget _statusPill(String label, String value, {bool isToday = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: isToday
            ? Colors.white.withValues(alpha: 0.20)
            : Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: isToday
            ? Border.all(color: Colors.white.withValues(alpha: 0.30))
            : null,
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$label ',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.70),
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
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
    if (_role == 'admin') crumbs.add('Pengawas');
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
          Row(
            children: [
              const Text(
                'Tampilkan:',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(width: 8),
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
            ],
          ),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            const Text(
              'Berdasarkan:',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(width: 8),
            _buildToggleChip(
              label: 'Kumulatif',
              selected: _sortField == _SortField.kumulatif,
              onTap: () => setState(() => _sortField = _SortField.kumulatif),
            ),
            const SizedBox(width: 6),
            _buildToggleChip(
              label: 'Hari Ini',
              selected: _sortField == _SortField.delta,
              onTap: () => setState(() => _sortField = _SortField.delta),
            ),
            const Spacer(),
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
    final color = _accentColor(row.delta);
    final canOpen = _canDrill;
    final deltaPositive = row.delta > 0;
    final isSortKumulatif = _sortField == _SortField.kumulatif;
    final badgeValue = isSortKumulatif
        ? '${row.totalAssignment}'
        : (deltaPositive ? '+${row.delta}' : '${row.delta}');
    final badgeColor = isSortKumulatif
        ? const Color(0xFF2D77D0)
        : (deltaPositive ? const Color(0xFF10B981) : Colors.grey[400]!);
    final deltaLabel = deltaPositive ? '+${row.delta}' : '${row.delta}';

    return GestureDetector(
      onTap: canOpen ? () => _handleRowTap(row) : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
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
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 5,
                decoration: BoxDecoration(
                  color: color,
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
                              row.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                              maxLines: 1,
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
                              Icons.chevron_right_rounded,
                              color: Colors.grey[400],
                              size: 18,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 5),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Wrap(
                              spacing: 4,
                              runSpacing: 3,
                              children: row.statusCounts.entries
                                  .take(5)
                                  .map(
                                    (e) => Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF1F5F9),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        '${e.key}: ${e.value}',
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF64748B),
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isSortKumulatif
                                ? '$deltaLabel hari ini  ·  ${row.yesterdayCount} kmrn'
                                : '${row.totalAssignment} kum  ·  ${row.yesterdayCount} kmrn',
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 11,
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
    final int numCols = 3 + statusKeys.length;
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
                  _sortableTh('Hr Ini', 'delta', numW, headerStyle),
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
    final canOpen = _canDrill;
    final delta = row.delta;
    final deltaStr = delta > 0 ? '+$delta' : '$delta';

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
                    child: Text(
                      row.title,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
    const double rowH = 36.0;
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
            onTap: _canDrill ? () => _handleRowTap(rows[i]) : null,
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
                      child: Text(
                        rows[i].title,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
                _sortableTh('Hr Ini', 'delta', numW, headerStyle),
                _sortableTh('Kmrn', 'kmrn', numW, headerStyle),
                for (final k in statusKeys)
                  _sortableTh(k, k, numW, headerStyle),
              ],
            ),
          ),
          for (int i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, color: divColor),
            GestureDetector(
              onTap: _canDrill ? () => _handleRowTap(rows[i]) : null,
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
    final isCumul = _sortField == _SortField.kumulatif;
    final values = rows
        .map((r) => isCumul ? r.totalAssignment : r.delta)
        .toList();
    final maxVal = values.fold(0, (prev, v) => v > prev ? v : prev);

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
            isCumul ? 'Kumulatif' : 'Hari Ini',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 10),
          for (int i = 0; i < rows.length; i++) ...[
            _buildBarRow(rows[i], values[i], maxVal),
            if (i < rows.length - 1) const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }

  Widget _buildBarRow(UnifiedRekapRow row, int val, int maxVal) {
    final color = _accentColor(row.delta);
    final canOpen = _canDrill;
    final fraction = (maxVal == 0 || val <= 0)
        ? 0.0
        : (val / maxVal).clamp(0.0, 1.0);

    return GestureDetector(
      onTap: canOpen ? () => _handleRowTap(row) : null,
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              row.title,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
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
          SizedBox(
            width: 30,
            child: Text(
              '$val',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
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
