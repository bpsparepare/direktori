import 'package:flutter/material.dart';

import '../../data/services/fasih_rekap_service.dart';
import '../../data/services/groundcheck_supabase_service.dart';

/// Lembar Kerja: progres pendataan per petugas dengan detail per SLS/sub-SLS.
///
/// - admin    : daftar semua petugas -> detail wilayah (SLS/sub-SLS) petugas
/// - pengawas : daftar petugas binaan -> detail wilayah petugas
/// - pendata  : langsung melihat lembar kerja wilayah tugasnya sendiri
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

      final payload = await _fetchPayload(profile);
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

  void _openPetugas(FasihRekapRow petugas) {
    setState(() {
      _selectedPetugas = petugas;
      _searchController.clear();
    });
    _loadData();
  }

  void _backToPetugasList() {
    setState(() {
      _selectedPetugas = null;
      _searchController.clear();
    });
    _loadData();
  }

  Future<bool> _handlePop() async {
    if (_selectedPetugas != null && _role != 'pendata') {
      _backToPetugasList();
      return false;
    }
    return true;
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
        if (!didPop) _handlePop();
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
                      _buildSearchField(),
                      const SizedBox(height: 12),
                      if (_isPetugasLevel)
                        ..._buildPetugasList()
                      else
                        ..._buildWilayahList(),
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
    final percent = summary.totalAssignments == 0
        ? 0.0
        : breakdown.submitted / summary.totalAssignments;
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
                      '${summary.totalUnits} $unitLabel • '
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
  // Level 1: daftar petugas
  // ---------------------------------------------------------------------

  List<Widget> _buildPetugasList() {
    if (_payload.rows.isEmpty) {
      return [_buildEmptyState('Belum ada data petugas.')];
    }
    return [
      for (final row in _payload.rows) ...[
        _buildPetugasCard(row),
        const SizedBox(height: 10),
      ],
    ];
  }

  Widget _buildPetugasCard(FasihRekapRow row) {
    final breakdown = _breakdownOf(
      row.statusCounts,
      row.totalAssignment,
      row.totalTerkirim,
    );
    final percent = row.totalAssignment == 0
        ? 0.0
        : breakdown.submitted / row.totalAssignment;
    final initial = row.title.isEmpty ? '?' : row.title[0].toUpperCase();

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _openPetugas(row),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 21,
                    backgroundColor: _progressColor(
                      percent,
                    ).withValues(alpha: 0.15),
                    child: Text(
                      initial,
                      style: TextStyle(
                        color: _progressColor(percent),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row.title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (row.subtitle.isNotEmpty && row.subtitle != '-')
                          Text(
                            row.subtitle,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blueGrey[400],
                            ),
                          ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${(percent * 100).toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: _progressColor(percent),
                        ),
                      ),
                      Text(
                        '${breakdown.submitted}/${row.totalAssignment}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blueGrey[400],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.blueGrey[300],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: percent.clamp(0.0, 1.0),
                  minHeight: 6,
                  backgroundColor: const Color(0xFFE8EEF6),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    _progressColor(percent),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: _buildBreakdownChips(breakdown),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBreakdownChips(_StatusBreakdown breakdown) {
    Widget chip(String label, int value, Color color) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '$label: $value',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      );
    }

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        chip('Submitted', breakdown.submitted, const Color(0xFF1D8F5A)),
        chip('Draft', breakdown.draft, Colors.orange[800]!),
        chip('Open', breakdown.open, Colors.blueGrey[500]!),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // Level 2: detail per SLS / sub-SLS
  // ---------------------------------------------------------------------

  List<Widget> _buildWilayahList() {
    if (_payload.rows.isEmpty) {
      return [_buildEmptyState('Belum ada wilayah tugas untuk ditampilkan.')];
    }

    final groups = _groupBySls(_payload.rows);
    return [
      for (final group in groups) ...[
        _buildSlsCard(group),
        const SizedBox(height: 10),
      ],
    ];
  }

  /// Kelompokkan baris wilayah (id 16 digit) per SLS (14 digit pertama).
  List<_SlsGroup> _groupBySls(List<FasihRekapRow> rows) {
    final map = <String, _SlsGroup>{};
    for (final row in rows) {
      final unitId = row.unitId;
      final slsKey = unitId.length >= 16 ? unitId.substring(0, 14) : unitId;
      map
          .putIfAbsent(
            slsKey,
            () => _SlsGroup(idSls: slsKey, title: row.title, subtitle: row.subtitle),
          )
          .rows
          .add(row);
    }
    return map.values.toList();
  }

  Widget _buildSlsCard(_SlsGroup group) {
    final breakdown = _breakdownOf(
      group.mergedStatusCounts,
      group.totalAssignment,
      group.totalTerkirim,
    );
    final percent = group.totalAssignment == 0
        ? 0.0
        : breakdown.submitted / group.totalAssignment;
    final kodeSls = group.idSls.length >= 14
        ? group.idSls.substring(10, 14)
        : group.idSls;
    final hasMultipleSub = group.rows.length > 1;

    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF0F4C81).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'SLS $kodeSls',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F4C81),
                ),
              ),
            ),
            if (hasMultipleSub) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${group.rows.length} Sub-SLS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.orange[800],
                  ),
                ),
              ),
            ],
            const Spacer(),
            Text(
              '${(percent * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: _progressColor(percent),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          group.title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        if (group.subtitle.isNotEmpty && group.subtitle != '-')
          Text(
            group.subtitle,
            style: TextStyle(fontSize: 12, color: Colors.blueGrey[400]),
          ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: percent.clamp(0.0, 1.0),
                  minHeight: 6,
                  backgroundColor: const Color(0xFFE8EEF6),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    _progressColor(percent),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${breakdown.submitted}/${group.totalAssignment}',
              style: TextStyle(fontSize: 12, color: Colors.blueGrey[500]),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _buildBreakdownChips(breakdown),
      ],
    );

    if (!hasMultipleSub) {
      final row = group.rows.first;
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header,
            if (row.statusCounts.isNotEmpty) ...[
              const SizedBox(height: 10),
              _buildStatusChips(row.statusCounts),
            ],
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: header,
          children: [
            for (final row in group.rows) _buildSubSlsRow(row),
          ],
        ),
      ),
    );
  }

  Widget _buildSubSlsRow(FasihRekapRow row) {
    final breakdown = _breakdownOf(
      row.statusCounts,
      row.totalAssignment,
      row.totalTerkirim,
    );
    final percent = row.totalAssignment == 0
        ? 0.0
        : breakdown.submitted / row.totalAssignment;
    final kodeSubsls = row.unitId.length >= 16
        ? row.unitId.substring(14, 16)
        : '-';

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F9FD),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Sub-SLS $kodeSubsls',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.orange[800],
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '${breakdown.submitted}/${row.totalAssignment}',
                style: TextStyle(fontSize: 12, color: Colors.blueGrey[500]),
              ),
              const SizedBox(width: 8),
              Text(
                '${(percent * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: _progressColor(percent),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: percent.clamp(0.0, 1.0),
              minHeight: 5,
              backgroundColor: const Color(0xFFE8EEF6),
              valueColor: AlwaysStoppedAnimation<Color>(
                _progressColor(percent),
              ),
            ),
          ),
          if (row.statusCounts.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildStatusChips(row.statusCounts),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusChips(Map<String, int> statusCounts) {
    final entries = statusCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final entry in entries)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _statusColor(entry.key).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${entry.key}: ${entry.value}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _statusColor(entry.key),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildEmptyState(String message) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
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
    );
  }

  Color _progressColor(double percent) {
    if (percent >= 0.999) return const Color(0xFF1D8F5A);
    if (percent >= 0.6) return const Color(0xFF2D77D0);
    if (percent >= 0.3) return Colors.orange[700]!;
    return Colors.red[400]!;
  }

  Color _statusColor(String status) {
    final upper = status.toUpperCase();
    if (upper.contains('APPROV') || upper.contains('TERKIRIM')) {
      return const Color(0xFF1D8F5A);
    }
    if (upper.contains('SUBMIT')) return const Color(0xFF2D77D0);
    if (upper.contains('REJECT') || upper.contains('TOLAK')) {
      return Colors.red[600]!;
    }
    if (upper.contains('DRAFT')) return Colors.orange[800]!;
    if (upper.contains('OPEN')) return Colors.blueGrey[500]!;
    return const Color(0xFF6B4FBB);
  }
}

class _SlsGroup {
  final String idSls;
  final String title;
  final String subtitle;
  final List<FasihRekapRow> rows = [];

  _SlsGroup({required this.idSls, required this.title, required this.subtitle});

  int get totalAssignment =>
      rows.fold(0, (sum, row) => sum + row.totalAssignment);

  int get totalTerkirim => rows.fold(0, (sum, row) => sum + row.totalTerkirim);

  /// Gabungan rincian status seluruh sub-SLS dalam SLS ini.
  Map<String, int> get mergedStatusCounts {
    final merged = <String, int>{};
    for (final row in rows) {
      row.statusCounts.forEach((status, count) {
        merged[status] = (merged[status] ?? 0) + count;
      });
    }
    return merged;
  }
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
