import 'package:flutter/material.dart';

import '../../data/services/fasih_rekap_service.dart';
import '../../data/services/groundcheck_supabase_service.dart';

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
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  String? _error;
  Se2026UserProfile? _profile;
  FasihRekapPayload _payload = FasihRekapPayload.empty();
  FasihRekapRow? _selectedPetugas;

  /// Target prelist per wilayah (key: id wilayah 16 digit) dan
  /// agregatnya per petugas (key: id petugas/ppl_id).
  Map<String, int> _prelistByWilayah = {};
  Map<String, int> _prelistByPetugas = {};
  bool _prelistLoaded = false;

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
      if (!_prelistLoaded) {
        await _loadPrelistTargets(profile);
      }
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
    for (final record in records) {
      if (record.id.isNotEmpty) {
        byWilayah[record.id] = (byWilayah[record.id] ?? 0) + record.prelist;
      }
      if (record.pplId.isNotEmpty) {
        byPetugas[record.pplId] =
            (byPetugas[record.pplId] ?? 0) + record.prelist;
      }
    }
    _prelistByWilayah = byWilayah;
    _prelistByPetugas = byPetugas;
    _prelistLoaded = true;
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

  /// Ambang capaian rendah (di bawah 40%).
  static const double _lowThreshold = 0.40;

  /// Distribusi baris berdasarkan capaian submitted terhadap target.
  _AchievementDistribution get _distribution {
    int below = 0;
    int atLeast = 0;
    int noTarget = 0;
    for (final row in _payload.rows) {
      final target = _targetOf(row);
      if (target <= 0) {
        noTarget++;
        continue;
      }
      final breakdown = _breakdownOf(
        row.statusCounts,
        row.totalAssignment,
        row.totalTerkirim,
      );
      final percent = breakdown.submitted / target;
      if (percent < _lowThreshold) {
        below++;
      } else {
        atLeast++;
      }
    }
    return _AchievementDistribution(
      below: below,
      atLeast: atLeast,
      noTarget: noTarget,
    );
  }

  void _openPetugas(FasihRekapRow petugas) {
    setState(() {
      _selectedPetugas = petugas;
      _searchController.clear();
      _resetSort();
    });
    _loadData();
  }

  void _backToPetugasList() {
    setState(() {
      _selectedPetugas = null;
      _searchController.clear();
      _resetSort();
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
    final dist = _distribution;
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
            'Capaian = submitted dibanding target prelist.',
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildDistributionTile(
                  label: 'Di bawah 40%',
                  value: dist.below,
                  color: Colors.red[400]!,
                  icon: Icons.trending_down_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildDistributionTile(
                  label: '40% ke atas',
                  value: dist.atLeast,
                  color: const Color(0xFF1D8F5A),
                  icon: Icons.trending_up_rounded,
                ),
              ),
            ],
          ),
          if (dist.noTarget > 0) ...[
            const SizedBox(height: 10),
            Text(
              '${dist.noTarget} $unitLabel belum punya target prelist '
              '(tidak dihitung).',
              style: TextStyle(color: Colors.blueGrey[400], fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDistributionTile({
    required String label,
    required int value,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$value',
                  style: TextStyle(
                    color: color,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.blueGrey[600],
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
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
          Text(
            _isPetugasLevel ? 'Tabel Per Petugas' : 'Tabel Per SLS/Sub-SLS',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            _isPetugasLevel
                ? 'Ketuk baris petugas untuk detail per SLS/sub-SLS. '
                      '% = submitted dibanding target prelist.'
                : 'Target = prelist wilayah. % = submitted dibanding target. '
                      'Submitted = semua status selain OPEN dan DRAFT.',
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
          const SizedBox(height: 12),
          if (_payload.rows.isEmpty)
            _buildEmptyState(
              _isPetugasLevel
                  ? 'Belum ada data petugas.'
                  : 'Belum ada wilayah tugas untuk ditampilkan.',
            )
          else if (_isPetugasLevel)
            _buildPetugasTable()
          else
            _buildWilayahTable(),
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
    final totals = _totalsOf(_payload.rows);
    final rows = [..._payload.rows];
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
          DataColumn(onSort: _onSort, label: const Text('Petugas')),
          _numColumn('Target'),
          _numColumn('Total'),
          _numColumn('Submitted'),
          _numColumn('Draft'),
          _numColumn('Open'),
          _numColumn('%'),
        ],
        rows: rows.map((row) {
          final breakdown = _breakdownOf(
            row.statusCounts,
            row.totalAssignment,
            row.totalTerkirim,
          );
          final target = _targetOf(row);
          return DataRow(
            onSelectChanged: (_) => _openPetugas(row),
            cells: [
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
              _totalLabelCell('Total (${_payload.rows.length} petugas)'),
              ..._totalNumberCells(totals),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWilayahTable() {
    final rows = [..._payload.rows];
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
        rows: rows.map((row) {
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
        '${(percent * 100).toStringAsFixed(0)}%',
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

  DataColumn _numColumn(String label) {
    return DataColumn(
      numeric: true,
      onSort: _onSort,
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
    switch (index) {
      case 1:
        return target;
      case 2:
        return row.totalAssignment;
      case 3:
        return breakdown.submitted;
      case 4:
        return breakdown.draft;
      case 5:
        return breakdown.open;
      case 6:
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
    switch (index) {
      case 1:
        return row.unitId.length >= 16 ? row.unitId.substring(14, 16) : '';
      case 2:
        return row.title.toLowerCase();
      case 3:
        return target;
      case 4:
        return row.totalAssignment;
      case 5:
        return breakdown.submitted;
      case 6:
        return breakdown.draft;
      case 7:
        return breakdown.open;
      case 8:
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

class _AchievementDistribution {
  final int below;
  final int atLeast;
  final int noTarget;

  const _AchievementDistribution({
    required this.below,
    required this.atLeast,
    required this.noTarget,
  });
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
