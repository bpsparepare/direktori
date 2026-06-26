import 'package:flutter/material.dart';

import '../../data/services/fasih_daily_service.dart';
import '../../data/services/groundcheck_supabase_service.dart';

class FasihDailyPage extends StatefulWidget {
  const FasihDailyPage({super.key});

  @override
  State<FasihDailyPage> createState() => _FasihDailyPageState();
}

class _FasihDailyPageState extends State<FasihDailyPage> {
  final GroundcheckSupabaseService _profileService =
      GroundcheckSupabaseService();
  final FasihDailyService _dailyService = FasihDailyService();

  bool _isLoading = true;
  String? _error;
  Se2026UserProfile? _profile;
  DailyContributionPayload _payload = DailyContributionPayload.empty();
  DateTime _targetDate = DateTime.now();

  DailyContributionRow? _selectedPengawas;
  DailyContributionRow? _selectedPetugas;

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
      if (profile == null) {
        throw Exception('Profil petugas SE2026 tidak ditemukan.');
      }

      final payload = await _dailyService.fetchDailyContribution(
        targetDate: _targetDate,
        pengawasId: _selectedPengawas?.unitId,
        petugasId: _selectedPetugas?.unitId,
      );

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

  String get _role => _profile?.role ?? '';

  bool get _isToday {
    final now = DateTime.now();
    return _targetDate.year == now.year &&
        _targetDate.month == now.month &&
        _targetDate.day == now.day;
  }

  bool get _canGoForward => !_isToday;

  bool get _canGoBack =>
      (_role == 'pengawas' && _selectedPetugas != null) ||
      (_role == 'admin' &&
          (_selectedPengawas != null || _selectedPetugas != null));

  bool get _canDrill =>
      (_role == 'pengawas' && _selectedPetugas == null) ||
      (_role == 'admin' && _selectedPetugas == null);

  bool _canOpenRow(DailyContributionRow row) {
    if (!_canDrill) return false;
    return _role == 'pengawas' || _role == 'admin';
  }

  void _prevDay() {
    setState(() {
      _targetDate = _targetDate.subtract(const Duration(days: 1));
      _selectedPengawas = null;
      _selectedPetugas = null;
    });
    _loadData();
  }

  void _nextDay() {
    if (!_canGoForward) return;
    setState(() {
      _targetDate = _targetDate.add(const Duration(days: 1));
      _selectedPengawas = null;
      _selectedPetugas = null;
    });
    _loadData();
  }

  void _goToday() {
    if (_isToday) return;
    setState(() {
      _targetDate = DateTime.now();
      _selectedPengawas = null;
      _selectedPetugas = null;
    });
    _loadData();
  }

  void _handleRowTap(DailyContributionRow row) {
    if (!_canOpenRow(row)) return;
    setState(() {
      if (_role == 'pengawas') {
        _selectedPetugas = row;
      } else if (_role == 'admin' && _selectedPengawas == null) {
        _selectedPengawas = row;
      } else if (_role == 'admin') {
        _selectedPetugas = row;
      }
    });
    _loadData();
  }

  void _handleBack() {
    setState(() {
      if (_role == 'pengawas') {
        _selectedPetugas = null;
      } else if (_role == 'admin' && _selectedPetugas != null) {
        _selectedPetugas = null;
      } else if (_role == 'admin') {
        _selectedPengawas = null;
      }
    });
    _loadData();
  }

  String get _pageTitle {
    switch (_role) {
      case 'pendata':
        return 'Kontribusi Harian Saya';
      case 'pengawas':
        return _selectedPetugas == null
            ? 'Kontribusi Petugas Hari Ini'
            : 'Detail Wilayah Petugas';
      case 'admin':
        if (_selectedPetugas != null) return 'Detail Wilayah Petugas';
        if (_selectedPengawas != null) return 'Kontribusi Petugas';
        return 'Kontribusi Harian';
      default:
        return 'Kontribusi Harian';
    }
  }

  Color _unitColor(int todayCount) =>
      todayCount >= 11 ? const Color(0xFF10B981) : const Color(0xFFEF4444);

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
              ? _buildErrorState()
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                    children: [
                      _buildHeroSection(),
                      if (_canGoBack) ...[
                        const SizedBox(height: 12),
                        _buildBreadcrumb(),
                      ],
                      const SizedBox(height: 16),
                      _buildUnitList(),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildHeroSection() {
    final summary = _payload.summary;
    final deltaPositive = summary.totalDelta >= 0;
    final deltaColor =
        deltaPositive ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    final deltaIcon = deltaPositive ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded;
    final roleLabel = (_profile?.role ?? '-').toUpperCase();

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
                  Icons.today_rounded,
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
                        color: Colors.white.withValues(alpha: 0.85),
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
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${summary.totalToday}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 48,
                        fontWeight: FontWeight.w800,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'didata hari ini',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(deltaIcon, color: deltaColor, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          '${deltaPositive ? '+' : ''}${summary.totalDelta} dari kemarin (${summary.totalYesterday})',
                          style: TextStyle(
                            color: deltaColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${summary.activeUnits} unit aktif',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildDateNav(),
        ],
      ),
    );
  }

  Widget _buildDateNav() {
    final label = _isToday
        ? 'Hari ini'
        : '${_targetDate.day.toString().padLeft(2, '0')} '
              '${_monthName(_targetDate.month)} '
              '${_targetDate.year}';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: _prevDay,
            icon: const Icon(
              Icons.chevron_left_rounded,
              color: Colors.white,
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: _isToday ? null : _goToday,
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
            onPressed: _canGoForward ? _nextDay : null,
            icon: Icon(
              Icons.chevron_right_rounded,
              color: _canGoForward
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBreadcrumb() {
    final crumbs = <String>[];
    if (_role == 'admin') crumbs.add('Pengawas');
    if (_role == 'pengawas') crumbs.add('Petugas');
    if (_selectedPengawas != null) crumbs.add(_selectedPengawas!.title);
    if (_selectedPetugas != null) crumbs.add(_selectedPetugas!.title);

    return Row(
      children: [
        if (_canGoBack)
          TextButton.icon(
            onPressed: _handleBack,
            icon: const Icon(Icons.arrow_back_rounded),
            label: const Text('Kembali'),
          ),
        if (crumbs.isNotEmpty)
          Expanded(
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: crumbs
                  .map(
                    (c) => Chip(
                      label: Text(c),
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

  Widget _buildUnitList() {
    if (_payload.rows.isEmpty) {
      return _buildEmptyHint(
        'Tidak ada aktivitas pada ${_isToday ? 'hari ini' : 'tanggal ini'} maupun kemarin.',
      );
    }

    return Column(
      children: _payload.rows.map((row) => _buildUnitCard(row)).toList(),
    );
  }

  Widget _buildUnitCard(DailyContributionRow row) {
    final color = _unitColor(row.todayCount);
    final canOpen = _canOpenRow(row);
    final deltaPositive = row.delta >= 0;
    final deltaColor = row.delta > 0
        ? const Color(0xFF10B981)
        : row.delta < 0
        ? const Color(0xFFEF4444)
        : Colors.grey;

    return GestureDetector(
      onTap: canOpen ? () => _handleRowTap(row) : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 6,
              height: 100,
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  bottomLeft: Radius.circular(20),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
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
                                row.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                              if (row.subtitle.isNotEmpty)
                                Text(
                                  row.subtitle,
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (canOpen)
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: Colors.grey,
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _buildStatBox(
                          label: 'Hari ini',
                          value: '${row.todayCount}',
                          valueColor: color,
                        ),
                        const SizedBox(width: 12),
                        _buildStatBox(
                          label: 'Kemarin',
                          value: '${row.yesterdayCount}',
                          valueColor: Colors.grey[700]!,
                        ),
                        const SizedBox(width: 12),
                        _buildStatBox(
                          label: 'Delta',
                          value:
                              '${deltaPositive && row.delta != 0 ? '+' : ''}${row.delta}',
                          valueColor: deltaColor,
                          icon: row.delta > 0
                              ? Icons.arrow_upward_rounded
                              : row.delta < 0
                              ? Icons.arrow_downward_rounded
                              : null,
                        ),
                      ],
                    ),
                    if (row.statusCountsToday.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: row.statusCountsToday.entries.take(4).map(
                          (e) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '${e.key}: ${e.value}',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF475569),
                              ),
                            ),
                          ),
                        ).toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatBox({
    required String label,
    required String value,
    required Color valueColor,
    IconData? icon,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(color: Colors.grey[500], fontSize: 11),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 13, color: valueColor),
                  const SizedBox(width: 2),
                ],
                Text(
                  value,
                  style: TextStyle(
                    color: valueColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyHint(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.blueGrey.withValues(alpha: 0.12)),
      ),
      child: Column(
        children: [
          Icon(Icons.inbox_rounded, size: 40, color: Colors.grey[400]),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[600], fontSize: 13),
          ),
        ],
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
            const Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: Colors.red,
            ),
            const SizedBox(height: 12),
            const Text(
              'Gagal memuat data harian',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? 'Terjadi kesalahan tidak dikenal.',
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

  String _monthName(int month) {
    const names = [
      '',
      'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
      'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
    ];
    return names[month];
  }
}
