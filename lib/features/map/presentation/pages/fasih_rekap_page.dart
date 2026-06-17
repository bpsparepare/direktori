import 'package:flutter/material.dart';

import '../../data/services/fasih_rekap_service.dart';
import '../../data/services/groundcheck_supabase_service.dart';

class FasihRekapPage extends StatefulWidget {
  const FasihRekapPage({super.key});

  @override
  State<FasihRekapPage> createState() => _FasihRekapPageState();
}

class _FasihRekapPageState extends State<FasihRekapPage> {
  static const String _allPeriodsValue = '__all_periods__';

  final GroundcheckSupabaseService _profileService =
      GroundcheckSupabaseService();
  final FasihRekapService _rekapService = FasihRekapService();
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  String? _error;
  Se2026UserProfile? _profile;
  FasihRekapPayload _payload = FasihRekapPayload.empty();
  FasihRekapPayload? _adminPetugasTopPayload;
  FasihRekapPayload? _adminPetugasBottomPayload;
  String _selectedPeriodId = _allPeriodsValue;
  String _sortBy = 'title';
  String _sortDir = 'asc';
  FasihRekapRow? _selectedPengawas;
  FasihRekapRow? _selectedPetugas;
  int _adminStatsTabIndex = 0;

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
      final shouldLoadAdminStats =
          profile.role == 'admin' &&
          _selectedPengawas == null &&
          _selectedPetugas == null;
      final surveyPeriodId = _selectedPeriodId == _allPeriodsValue
          ? null
          : _selectedPeriodId;
      FasihRekapPayload? adminPetugasTop;
      FasihRekapPayload? adminPetugasBottom;
      if (shouldLoadAdminStats) {
        try {
          final results = await Future.wait([
            _rekapService.fetchAdminPetugas(
              surveyPeriodId: surveyPeriodId,
              search: _searchController.text,
              limit: 10,
              sortBy: 'total_assignment',
              sortDir: 'desc',
            ),
            _rekapService.fetchAdminPetugas(
              surveyPeriodId: surveyPeriodId,
              search: _searchController.text,
              limit: 10,
              sortBy: 'total_assignment',
              sortDir: 'asc',
            ),
          ]);
          adminPetugasTop = results[0];
          adminPetugasBottom = results[1];
        } catch (_) {
          adminPetugasTop = null;
          adminPetugasBottom = null;
        }
      }
      if (!mounted) return;

      setState(() {
        _profile = profile;
        _payload = payload;
        _adminPetugasTopPayload = adminPetugasTop;
        _adminPetugasBottomPayload = adminPetugasBottom;
        if (!shouldLoadAdminStats) {
          _adminStatsTabIndex = 0;
        }
        _selectedPeriodId = _normalizeSelectedPeriod(
          _selectedPeriodId,
          payload.periods,
        );
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
    final surveyPeriodId = _selectedPeriodId == _allPeriodsValue
        ? null
        : _selectedPeriodId;

    switch (profile.role) {
      case 'pendata':
        return _rekapService.fetchPendataWilayah(
          surveyPeriodId: surveyPeriodId,
          search: _searchController.text,
          limit: 250,
          sortBy: _sortBy,
          sortDir: _sortDir,
        );
      case 'pengawas':
        if (_selectedPetugas != null) {
          return _rekapService.fetchPengawasWilayahPetugas(
            petugasId: _selectedPetugas!.unitId,
            surveyPeriodId: surveyPeriodId,
            search: _searchController.text,
            limit: 250,
            sortBy: _sortBy,
            sortDir: _sortDir,
          );
        }
        return _rekapService.fetchPengawasPetugas(
          surveyPeriodId: surveyPeriodId,
          search: _searchController.text,
          limit: 150,
          sortBy: _sortBy,
          sortDir: _sortDir,
        );
      case 'admin':
        if (_selectedPetugas != null) {
          return _rekapService.fetchAdminWilayahByPetugas(
            petugasId: _selectedPetugas!.unitId,
            surveyPeriodId: surveyPeriodId,
            search: _searchController.text,
            limit: 300,
            sortBy: _sortBy,
            sortDir: _sortDir,
          );
        }
        if (_selectedPengawas != null) {
          return _rekapService.fetchAdminPetugasByPengawas(
            pengawasId: _selectedPengawas!.unitId,
            surveyPeriodId: surveyPeriodId,
            search: _searchController.text,
            limit: 200,
            sortBy: _sortBy,
            sortDir: _sortDir,
          );
        }
        return _rekapService.fetchAdminPengawas(
          surveyPeriodId: surveyPeriodId,
          search: _searchController.text,
          limit: 120,
          sortBy: _sortBy,
          sortDir: _sortDir,
        );
      default:
        return Future.value(FasihRekapPayload.empty());
    }
  }

  String _normalizeSelectedPeriod(
    String current,
    List<FasihSurveyPeriodOption> periods,
  ) {
    if (current == _allPeriodsValue) return current;
    final exists = periods.any((item) => item.surveyPeriodId == current);
    return exists ? current : _allPeriodsValue;
  }

  String get _role => _profile?.role ?? '';

  bool get _canGoBack =>
      (_role == 'pengawas' && _selectedPetugas != null) ||
      (_role == 'admin' &&
          (_selectedPengawas != null || _selectedPetugas != null));

  bool get _canDrill =>
      (_role == 'pengawas' && _selectedPetugas == null) ||
      (_role == 'admin' && _selectedPetugas == null);

  String get _pageTitle {
    switch (_role) {
      case 'pendata':
        return 'Rekap FASIH Wilayah Tugas';
      case 'pengawas':
        return _selectedPetugas == null
            ? 'Rekap FASIH Per Petugas'
            : 'Detail Wilayah Petugas';
      case 'admin':
        if (_selectedPetugas != null) {
          return 'Detail Wilayah Petugas';
        }
        if (_selectedPengawas != null) {
          return 'Rekap Petugas Pengawas';
        }
        return 'Rekap FASIH Per Pengawas';
      default:
        return 'Rekap FASIH';
    }
  }

  String get _scopeDescription {
    switch (_role) {
      case 'pendata':
        return 'Semua wilayah tugas Anda tetap tampil, termasuk yang belum punya data FASIH.';
      case 'pengawas':
        return _selectedPetugas == null
            ? 'Ringkasan dimulai per petugas valid di wilayah pengawasan Anda.'
            : 'Detail wilayah menampilkan seluruh wilayah tugas petugas terpilih beserta hitungan per alias status.';
      case 'admin':
        if (_selectedPetugas != null) {
          return 'Anda sedang melihat level wilayah tugas petugas terpilih.';
        }
        if (_selectedPengawas != null) {
          return 'Anda sedang melihat daftar petugas valid di bawah pengawas terpilih.';
        }
        return 'Ringkasan dimulai dari level pengawas, lalu turun ke petugas dan wilayah.';
      default:
        return 'Menampilkan rekap sesuai hak akses Anda.';
    }
  }

  List<DropdownMenuItem<String>> get _periodItems {
    final items = <DropdownMenuItem<String>>[
      const DropdownMenuItem<String>(
        value: _allPeriodsValue,
        child: Text('Semua Periode'),
      ),
    ];

    for (final period in _payload.periods) {
      final label = period.isActive ? '${period.name} (aktif)' : period.name;
      items.add(
        DropdownMenuItem<String>(
          value: period.surveyPeriodId,
          child: Text(label),
        ),
      );
    }

    return items;
  }

  List<String> get _aliasColumns =>
      _payload.statusAliases.map((item) => item.alias).toList();

  List<_SortOption> get _sortOptions {
    final titleLabel =
        _payload.meta.level == 'wilayah_by_petugas' ||
            _payload.meta.level == 'pendata_wilayah'
        ? 'Nama Wilayah'
        : 'Nama';
    return [
      _SortOption(label: '$titleLabel A-Z', sortBy: 'title', sortDir: 'asc'),
      _SortOption(label: '$titleLabel Z-A', sortBy: 'title', sortDir: 'desc'),
      const _SortOption(
        label: 'Total Tertinggi',
        sortBy: 'total_assignment',
        sortDir: 'desc',
      ),
      const _SortOption(
        label: 'Total Terendah',
        sortBy: 'total_assignment',
        sortDir: 'asc',
      ),
    ];
  }

  String get _selectedSortValue => '$_sortBy:$_sortDir';

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
                      if (_canGoBack || _selectedPengawas != null) ...[
                        const SizedBox(height: 16),
                        _buildBreadcrumbSection(),
                      ],
                      // const SizedBox(height: 16),
                      // _buildFilterSection(),
                      // const SizedBox(height: 16),
                      // _buildSummarySection(),
                      _buildAliasSection(),
                      _buildChartSection(),
                      const SizedBox(height: 16),
                      _buildTableSection(),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildHeroSection() {
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
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.bar_chart_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _pageTitle,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Role akses: $roleLabel',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // const SizedBox(height: 16),
          // Text(
          //   _scopeDescription,
          //   style: TextStyle(
          //     color: Colors.white.withValues(alpha: 0.95),
          //     fontSize: 14,
          //     height: 1.45,
          //   ),
          // ),
        ],
      ),
    );
  }

  Widget _buildBreadcrumbSection() {
    final crumbs = <String>[];
    if (_role == 'admin') {
      crumbs.add('Pengawas');
    } else if (_role == 'pengawas') {
      crumbs.add('Petugas');
    }
    if (_selectedPengawas != null) {
      crumbs.add(_selectedPengawas!.title);
    }
    if (_selectedPetugas != null) {
      crumbs.add(_selectedPetugas!.title);
    }

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
                    (item) => Chip(
                      label: Text(item),
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

  Widget _buildFilterSection() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Filter Rekap',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 760;
                final children = [
                  _buildPeriodDropdown(),
                  _buildSortDropdown(),
                  _buildSearchField(),
                ];

                if (compact) {
                  return Column(
                    children: [
                      for (int i = 0; i < children.length; i++) ...[
                        children[i],
                        if (i != children.length - 1)
                          const SizedBox(height: 12),
                      ],
                      const SizedBox(height: 12),
                      _buildActionButtons(compact: true),
                    ],
                  );
                }

                return Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: children[0]),
                        const SizedBox(width: 12),
                        Expanded(child: children[1]),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(flex: 2, child: children[2]),
                        const SizedBox(width: 12),
                        _buildActionButtons(compact: false),
                      ],
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodDropdown() {
    return DropdownButtonFormField<String>(
      key: ValueKey<String>('period:$_selectedPeriodId'),
      initialValue: _selectedPeriodId,
      decoration: const InputDecoration(
        labelText: 'Periode Survei',
        border: OutlineInputBorder(),
      ),
      items: _periodItems,
      onChanged: (value) {
        if (value == null) return;
        setState(() {
          _selectedPeriodId = value;
        });
        _loadData();
      },
    );
  }

  Widget _buildSortDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _selectedSortValue,
      decoration: const InputDecoration(
        labelText: 'Urutkan',
        border: OutlineInputBorder(),
      ),
      items: _sortOptions
          .map(
            (item) => DropdownMenuItem<String>(
              value: item.value,
              child: Text(item.label),
            ),
          )
          .toList(),
      onChanged: (value) {
        if (value == null) return;
        final parts = value.split(':');
        if (parts.length != 2) return;
        setState(() {
          _sortBy = parts[0];
          _sortDir = parts[1];
        });
        _loadData();
      },
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      decoration: InputDecoration(
        labelText: 'Cari nama atau detail',
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: IconButton(
          tooltip: 'Bersihkan pencarian',
          icon: const Icon(Icons.close_rounded),
          onPressed: () {
            _searchController.clear();
            _loadData();
          },
        ),
      ),
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => _loadData(),
    );
  }

  Widget _buildActionButtons({required bool compact}) {
    if (compact) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _loadData,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Terapkan'),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        OutlinedButton.icon(
          onPressed: () {
            _searchController.clear();
            setState(() {
              _selectedPeriodId = _allPeriodsValue;
              _sortBy = _role == 'pendata' ? 'title' : 'total_assignment';
              _sortDir = _role == 'pendata' ? 'asc' : 'desc';
            });
            _loadData();
          },
          icon: const Icon(Icons.filter_alt_off_rounded),
          label: const Text('Reset'),
        ),
        const SizedBox(width: 10),
        ElevatedButton.icon(
          onPressed: _loadData,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Terapkan'),
        ),
      ],
    );
  }

  Widget _buildSummarySection() {
    final topAliases = _payload.statusAliases.take(2).toList();
    final cards = <_SummaryCardData>[
      _SummaryCardData(
        label:
            _payload.meta.level == 'wilayah_by_petugas' ||
                _payload.meta.level == 'pendata_wilayah'
            ? 'Total Wilayah'
            : _payload.meta.level == 'admin_pengawas'
            ? 'Total Pengawas'
            : 'Total Petugas',
        value: _payload.summary.totalUnits.toString(),
        icon: Icons.groups_rounded,
        color: const Color(0xFF2D77D0),
      ),
      _SummaryCardData(
        label: 'Total Assignment',
        value: _payload.summary.totalAssignments.toString(),
        icon: Icons.assignment_turned_in_rounded,
        color: const Color(0xFF10B981),
      ),
      for (final alias in topAliases)
        _SummaryCardData(
          label: alias.alias,
          value: alias.total.toString(),
          icon: Icons.flag_circle_rounded,
          color: const Color(0xFFF59E0B),
        ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: cards.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.35,
      ),
      itemBuilder: (context, index) {
        final item = cards[index];
        return _buildSummaryCard(item);
      },
    );
  }

  Widget _buildSummaryCard(_SummaryCardData data) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: data.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(data.icon, color: data.color),
          ),
          const Spacer(),
          Text(
            data.value,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            data.label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.grey[700],
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAliasSection() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Rekap Per Status',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            if (_payload.statusAliases.isEmpty)
              _buildEmptyHint('Belum ada alias status pada scope ini.')
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _payload.statusAliases
                      .map(
                        (item) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF7ED),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(
                                  0xFFF97316,
                                ).withValues(alpha: 0.18),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 140,
                                  ),
                                  child: Text(
                                    _compactLabel(item.alias, maxLength: 18),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF7C2D12),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF97316),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    item.total.toString(),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildChartSection() {
    final showAdminTabs =
        _role == 'admin' &&
        _payload.meta.level == 'admin_pengawas' &&
        _selectedPengawas == null &&
        _selectedPetugas == null &&
        _adminPetugasTopPayload != null &&
        _adminPetugasBottomPayload != null;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showAdminTabs)
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Statistik',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _openAdminStatsDialog,
                    child: const Text('More'),
                  ),
                ],
              )
            else
              Text(
                _payload.meta.level == 'admin_pengawas'
                    ? 'Top Pengawas'
                    : _payload.meta.level == 'wilayah_by_petugas' ||
                          _payload.meta.level == 'pendata_wilayah'
                    ? 'Top Wilayah'
                    : 'Top Petugas',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            const SizedBox(height: 8),
            if (showAdminTabs)
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Top Pengawas'),
                    selected: _adminStatsTabIndex == 0,
                    onSelected: (selected) {
                      if (!selected) return;
                      setState(() {
                        _adminStatsTabIndex = 0;
                      });
                    },
                  ),
                  ChoiceChip(
                    label: const Text('Top Petugas'),
                    selected: _adminStatsTabIndex == 1,
                    onSelected: (selected) {
                      if (!selected) return;
                      setState(() {
                        _adminStatsTabIndex = 1;
                      });
                    },
                  ),
                ],
              ),
            if (showAdminTabs) const SizedBox(height: 8),
            Text(
              'Grafik batang disusun vertikal per peringkat agar lebih hemat tempat.',
              style: TextStyle(color: Colors.grey[700], fontSize: 13),
            ),
            const SizedBox(height: 12),
            _buildChartContent(
              showAdminTabs && _adminStatsTabIndex == 1
                  ? _adminPetugasTopPayload!.chart
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChartContent([List<FasihRekapChartItem>? items]) {
    final chartItems = items ?? _payload.chart;
    if (chartItems.isEmpty) {
      return _buildEmptyHint('Belum ada data chart untuk scope ini.');
    }

    final maxValue = chartItems
        .map((item) => item.totalAssignment)
        .fold<int>(
          0,
          (previous, current) => previous > current ? previous : current,
        );

    return Column(
      children: List.generate(chartItems.length, (index) {
        final item = chartItems[index];
        final ratio = maxValue == 0 ? 0.0 : item.totalAssignment / maxValue;

        return Padding(
          padding: EdgeInsets.only(
            bottom: index == chartItems.length - 1 ? 0 : 12,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: const Color(0xFFE0ECFF),
                  borderRadius: BorderRadius.circular(999),
                ),
                alignment: Alignment.center,
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1D4ED8),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _compactLabel(item.label, maxLength: 28),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          item.totalAssignment.toString(),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F4C81),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: ratio.clamp(0.0, 1.0),
                        minHeight: 10,
                        backgroundColor: const Color(0xFFE5EEF9),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFF1D4ED8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  String _compactLabel(String value, {int maxLength = 24}) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= maxLength) return normalized;
    return '${normalized.substring(0, maxLength - 1)}...';
  }

  void _openAdminStatsDialog() {
    final isRootAdmin =
        _role == 'admin' &&
        _payload.meta.level == 'admin_pengawas' &&
        _selectedPengawas == null &&
        _selectedPetugas == null;
    if (!isRootAdmin) return;
    if (_adminStatsTabIndex == 0) {
      _openAdminPengawasTableDialog();
      return;
    }
    _openAdminPetugasTableDialog();
  }

  void _openAdminPengawasTableDialog() {
    final surveyPeriodId = _selectedPeriodId == _allPeriodsValue
        ? null
        : _selectedPeriodId;

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 960,
              maxHeight: MediaQuery.of(dialogContext).size.height * 0.86,
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: FutureBuilder<FasihRekapPayload>(
                future: _rekapService.fetchAdminPengawas(
                  surveyPeriodId: surveyPeriodId,
                  search: _searchController.text,
                  limit: 200,
                  sortBy: 'total_assignment',
                  sortDir: 'desc',
                ),
                builder: (context, snapshot) {
                  final child = switch (snapshot.connectionState) {
                    ConnectionState.waiting || ConnectionState.active =>
                      const Center(child: CircularProgressIndicator()),
                    _ when snapshot.hasError => Center(
                      child: Text(
                        snapshot.error.toString(),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    _ => _buildTableDialogBody(
                      title: 'Top Pengawas',
                      rows: snapshot.data?.rows ?? const [],
                      aliases: (snapshot.data?.statusAliases ?? const [])
                          .map((item) => item.alias)
                          .toList(),
                      enableDrill: true,
                      onClose: () => Navigator.of(dialogContext).pop(),
                      onRowTap: (row) {
                        Navigator.of(dialogContext).pop();
                        _handleRowTap(row);
                      },
                    ),
                  };

                  return child;
                },
              ),
            ),
          ),
        );
      },
    );
  }

  void _openAdminPetugasTableDialog() {
    final topPayload = _adminPetugasTopPayload;
    final bottomPayload = _adminPetugasBottomPayload;
    if (topPayload == null || bottomPayload == null) return;

    final aliases = topPayload.statusAliases.map((item) => item.alias).toList();

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 960,
              maxHeight: MediaQuery.of(dialogContext).size.height * 0.86,
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Petugas (Top 10 & Bottom 10)',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView(
                      children: [
                        const Text(
                          'Top 10',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 10),
                        _buildRekapDataTable(
                          rows: topPayload.rows,
                          aliases: aliases,
                          enableDrill: false,
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'Bottom 10',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 10),
                        _buildRekapDataTable(
                          rows: bottomPayload.rows,
                          aliases: aliases,
                          enableDrill: false,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTableDialogBody({
    required String title,
    required List<FasihRekapRow> rows,
    required List<String> aliases,
    required bool enableDrill,
    required VoidCallback onClose,
    void Function(FasihRekapRow row)? onRowTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              onPressed: onClose,
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView(
            children: [
              _buildRekapDataTable(
                rows: rows,
                aliases: aliases,
                enableDrill: enableDrill,
                onRowTap: onRowTap,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRekapDataTable({
    required List<FasihRekapRow> rows,
    required List<String> aliases,
    required bool enableDrill,
    void Function(FasihRekapRow row)? onRowTap,
  }) {
    if (rows.isEmpty) {
      return _buildEmptyHint('Belum ada baris rekap pada scope ini.');
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        showCheckboxColumn: false,
        horizontalMargin: 12,
        columnSpacing: 20,
        headingRowHeight: 52,
        dataRowMinHeight: 46,
        dataRowMaxHeight: 54,
        headingRowColor: WidgetStateProperty.all(const Color(0xFFF5F8FD)),
        columns: [
          const DataColumn(label: Text('Unit')),
          const DataColumn(label: Text('Total')),
          for (final alias in aliases)
            DataColumn(label: _buildTableHeaderLabel(alias)),
        ],
        rows: rows.map((row) {
          final canOpen = enableDrill && _canOpenRow(row);
          return DataRow(
            onSelectChanged: canOpen
                ? (_) {
                    if (onRowTap != null) {
                      onRowTap(row);
                    } else {
                      _handleRowTap(row);
                    }
                  }
                : null,
            cells: [
              DataCell(
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        row.title,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (canOpen) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.chevron_right_rounded, size: 18),
                    ],
                  ],
                ),
              ),
              DataCell(Text(row.totalAssignment.toString())),
              for (final alias in aliases)
                DataCell(Text((row.statusCounts[alias] ?? 0).toString())),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTableSection() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tabel Rekap ${_tableSectionLabel()}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Kolom alias status dibentuk otomatis dari hasil scope aktif.',
              style: TextStyle(color: Colors.grey[700], fontSize: 13),
            ),
            const SizedBox(height: 16),
            _buildTableContent(),
          ],
        ),
      ),
    );
  }

  Widget _buildTableContent() {
    if (_payload.rows.isEmpty) {
      return _buildEmptyHint('Belum ada baris rekap pada scope ini.');
    }

    final aliases = _aliasColumns;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        showCheckboxColumn: false,
        horizontalMargin: 12,
        columnSpacing: 20,
        headingRowHeight: 52,
        dataRowMinHeight: 46,
        dataRowMaxHeight: 54,
        headingRowColor: WidgetStateProperty.all(const Color(0xFFF5F8FD)),
        columns: [
          const DataColumn(label: Text('Unit')),
          const DataColumn(label: Text('Total')),
          for (final alias in aliases)
            DataColumn(label: _buildTableHeaderLabel(alias)),
        ],
        rows: _payload.rows.map((row) {
          final canOpen = _canOpenRow(row);
          return DataRow(
            onSelectChanged: canOpen ? (_) => _handleRowTap(row) : null,
            cells: [
              DataCell(
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        row.title,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (canOpen) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.chevron_right_rounded, size: 18),
                    ],
                  ],
                ),
              ),
              DataCell(Text(row.totalAssignment.toString())),
              for (final alias in aliases)
                DataCell(Text((row.statusCounts[alias] ?? 0).toString())),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTableHeaderLabel(String label) {
    return SizedBox(
      width: 68,
      child: Text(
        label,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
      ),
    );
  }

  String _tableSectionLabel() {
    switch (_payload.meta.level) {
      case 'admin_pengawas':
        return 'Pengawas';
      case 'pengawas_petugas':
      case 'petugas_by_pengawas':
        return 'Petugas';
      case 'wilayah_by_petugas':
      case 'pendata_wilayah':
        return 'Wilayah';
      default:
        return '';
    }
  }

  bool _canOpenRow(FasihRekapRow row) {
    if (!_canDrill) return false;
    if (_role == 'pengawas') {
      return _selectedPetugas == null;
    }
    if (_role == 'admin') {
      return _selectedPetugas == null;
    }
    return false;
  }

  void _handleRowTap(FasihRekapRow row) {
    if (!_canOpenRow(row)) return;

    setState(() {
      if (_role == 'pengawas') {
        _selectedPetugas = row;
        _sortBy = 'title';
        _sortDir = 'asc';
      } else if (_role == 'admin' && _selectedPengawas == null) {
        _selectedPengawas = row;
        _sortBy = 'total_assignment';
        _sortDir = 'desc';
      } else if (_role == 'admin') {
        _selectedPetugas = row;
        _sortBy = 'title';
        _sortDir = 'asc';
      }
    });
    _loadData();
  }

  void _handleBack() {
    setState(() {
      if (_role == 'pengawas') {
        _selectedPetugas = null;
        _sortBy = 'total_assignment';
        _sortDir = 'desc';
      } else if (_role == 'admin' && _selectedPetugas != null) {
        _selectedPetugas = null;
        _sortBy = 'total_assignment';
        _sortDir = 'desc';
      } else if (_role == 'admin') {
        _selectedPengawas = null;
        _sortBy = 'total_assignment';
        _sortDir = 'desc';
      }
    });
    _loadData();
  }

  Widget _buildEmptyHint(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.blueGrey.withValues(alpha: 0.12)),
      ),
      child: Text(
        message,
        style: TextStyle(color: Colors.grey[700], fontSize: 13),
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
              'Gagal memuat rekap FASIH',
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
}

class _SummaryCardData {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryCardData({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
}

class _SortOption {
  final String label;
  final String sortBy;
  final String sortDir;

  const _SortOption({
    required this.label,
    required this.sortBy,
    required this.sortDir,
  });

  String get value => '$sortBy:$sortDir';
}
