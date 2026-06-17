import 'package:flutter/material.dart';
import '../../data/services/kbli_sheets_service.dart';

class KbliPage extends StatefulWidget {
  const KbliPage({super.key});

  @override
  State<KbliPage> createState() => _KbliPageState();
}

class _KbliPageState extends State<KbliPage> {
  final KbliSheetsService _service = KbliSheetsService();
  final TextEditingController _searchController = TextEditingController();
  static const List<String> _monthNames = <String>[
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

  bool _isLoading = true;
  String? _error;
  String? _statusMessage;
  DateTime? _lastUpdatedAt;
  String _query = '';
  String _selectedCategory = _allCategory;
  List<PanduanKbliEntry> _entries = [];

  static const String _allCategory = 'Semua';

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
      _statusMessage = null;
    });

    try {
      final cachedEntries = await _service.loadCachedEntries();
      final cachedUpdatedAt = await _service.loadCacheUpdatedAt();
      if (!mounted) return;

      if (cachedEntries.isNotEmpty) {
        setState(() {
          _entries = cachedEntries;
          _isLoading = false;
          _lastUpdatedAt = cachedUpdatedAt;
          _statusMessage = 'Menampilkan data KBLI dari cache lokal.';
        });
        return;
      }

      final entries = await _service.refreshEntries();
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _isLoading = false;
        _lastUpdatedAt = DateTime.now();
        _statusMessage = 'Data KBLI diperbarui dari Google Sheets.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _refreshData() async {
    final hadEntries = _entries.isNotEmpty;

    if (!hadEntries) {
      setState(() {
        _isLoading = true;
        _error = null;
        _statusMessage = null;
      });
    } else {
      setState(() {
        _error = null;
      });
    }

    try {
      final entries = await _service.refreshEntries();
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _isLoading = false;
        _lastUpdatedAt = DateTime.now();
        _statusMessage = 'Data KBLI diperbarui dari Google Sheets.';
      });
    } catch (e) {
      if (!mounted) return;

      if (hadEntries) {
        setState(() {
          _isLoading = false;
          _statusMessage =
              'Refresh gagal. Menampilkan data KBLI terakhir dari cache lokal.';
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Refresh KBLI gagal: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  List<String> get _categories {
    final values =
        _entries
            .map((item) => item.kategori)
            .where((item) => item.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return [_allCategory, ...values];
  }

  int get _jenisUsahaCount {
    return _entries.map((item) => item.jenisUsaha).toSet().length;
  }

  List<_KbliGroupData> get _filteredGroups {
    final query = _query.trim().toLowerCase();
    final grouped = <String, List<PanduanKbliEntry>>{};

    for (final entry in _entries) {
      if (_selectedCategory != _allCategory &&
          entry.kategori != _selectedCategory) {
        continue;
      }

      final haystack = [
        entry.jenisUsaha,
        entry.kategori,
        entry.kbli2025,
        entry.keteranganKbli,
        entry.aktivitas,
        entry.input,
        entry.proses,
        entry.output,
      ].join(' ').toLowerCase();

      if (query.isNotEmpty && !haystack.contains(query)) {
        continue;
      }

      grouped.putIfAbsent(entry.jenisUsaha, () => []).add(entry);
    }

    final results =
        grouped.entries
            .map(
              (entry) => _KbliGroupData(
                title: entry.key,
                items: entry.value
                  ..sort((a, b) {
                    final categoryCompare = a.kategori.compareTo(b.kategori);
                    if (categoryCompare != 0) return categoryCompare;
                    return a.kbli2025.compareTo(b.kbli2025);
                  }),
              ),
            )
            .toList()
          ..sort((a, b) => a.title.compareTo(b.title));

    return results;
  }

  int get _visibleReferenceCount {
    return _filteredGroups.fold<int>(0, (sum, item) => sum + item.items.length);
  }

  @override
  Widget build(BuildContext context) {
    final groups = _filteredGroups;

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
                  onRefresh: _refreshData,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(child: _buildHeroSection()),
                      SliverToBoxAdapter(child: _buildSearchSection()),
                      SliverToBoxAdapter(
                        child: _buildSectionHeader(
                          resultCount: groups.length,
                          referenceCount: _visibleReferenceCount,
                        ),
                      ),
                      if (groups.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: _buildEmptyState(),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                          sliver: SliverList.separated(
                            itemCount: groups.length,
                            itemBuilder: (context, index) =>
                                _buildKbliTile(groups[index], index),
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 12),
                          ),
                        ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildHeroSection() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 14),
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.apartment_rounded, color: Colors.white),
          ),
          const SizedBox(width: 18),
          const Text(
            'Panduan KBLI',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (value) {
                setState(() {
                  _query = value;
                });
              },
              decoration: InputDecoration(
                hintText: 'Cari jenis usaha, KBLI, atau kata kunci aktivitas',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isEmpty
                    ? IconButton(
                        onPressed: _refreshData,
                        icon: const Icon(Icons.refresh_rounded),
                      )
                    : IconButton(
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _query = '';
                          });
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 18,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _categories.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final category = _categories[index];
                final isSelected = category == _selectedCategory;
                return FilterChip(
                  label: Text(category),
                  selected: isSelected,
                  onSelected: (_) {
                    setState(() {
                      _selectedCategory = category;
                    });
                  },
                  showCheckmark: false,
                  selectedColor: const Color(
                    0xFF2D77D0,
                  ).withValues(alpha: 0.14),
                  backgroundColor: Colors.white,
                  side: BorderSide(
                    color: isSelected
                        ? const Color(0xFF2D77D0)
                        : Colors.grey.withValues(alpha: 0.24),
                  ),
                  labelStyle: TextStyle(
                    color: isSelected
                        ? const Color(0xFF144A8B)
                        : const Color(0xFF526070),
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader({
    required int resultCount,
    required int referenceCount,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.withValues(alpha: 0.18)),
            ),
            child: Text(
              _selectedCategory == _allCategory
                  ? 'Semua kategori'
                  : 'Kategori $_selectedCategory',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Color(0xFF144A8B),
              ),
            ),
          ),
          if (_lastUpdatedAt != null) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Terakhir diperbarui: ${_formatUpdatedAt(_lastUpdatedAt!)}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.blueGrey[500],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatUpdatedAt(DateTime value) {
    final local = value.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = _monthNames[local.month - 1];
    final year = local.year;
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day $month $year $hour:$minute';
  }

  Widget _buildKbliTile(_KbliGroupData group, int index) {
    final preview = _buildPreviewText(group);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => _showKbliDetail(group),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: const Color(0xFF2D77D0).withValues(alpha: 0.08),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF103C76), Color(0xFF2F83DB)],
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF10243E),
                        ),
                      ),
                      if (preview.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          preview,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.blueGrey[700],
                            height: 1.4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF5FF),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 16,
                    color: Color(0xFF2D77D0),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _buildPreviewText(_KbliGroupData group) {
    final previews = group.items
        .map((item) {
          if (item.keteranganKbli.isNotEmpty) return item.keteranganKbli;
          if (item.aktivitas.isNotEmpty) return item.aktivitas;
          if (item.proses.isNotEmpty) return item.proses;
          if (item.output.isNotEmpty) return item.output;
          return '';
        })
        .where((item) => item.isNotEmpty)
        .toList();

    if (previews.isEmpty) {
      return 'Pilih untuk melihat detail aktivitas, input, proses, dan output.';
    }

    return previews.first;
  }

  Widget _buildMiniBadge({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F9FD),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: const Color(0xFF3D6B9D)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF3D5066),
              ),
            ),
          ),
          if (_statusMessage != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _statusMessage!,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.blueGrey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 78,
              height: 78,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
              ),
              child: const Icon(
                Icons.manage_search_rounded,
                size: 38,
                color: Color(0xFF2D77D0),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Data tidak ditemukan',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'Coba ganti kata kunci pencarian atau ubah filter kategori.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.blueGrey[600], height: 1.5),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () {
                _searchController.clear();
                setState(() {
                  _query = '';
                  _selectedCategory = _allCategory;
                });
              },
              child: const Text('Reset Filter'),
            ),
          ],
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
            const Icon(Icons.cloud_off_rounded, size: 52, color: Colors.red),
            const SizedBox(height: 16),
            const Text(
              'Gagal memuat data KBLI',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? 'Terjadi kesalahan',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.blueGrey[600], height: 1.5),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _refreshData,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Coba Lagi'),
            ),
          ],
        ),
      ),
    );
  }

  void _showKbliDetail(_KbliGroupData group) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final size = MediaQuery.of(dialogContext).size;
        final maxWidth = size.width > 760 ? 720.0 : size.width - 24;

        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 24,
          ),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxWidth,
              maxHeight: size.height * 0.82,
            ),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(22, 22, 12, 20),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF143A70), Color(0xFF2D77D0)],
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              group.title,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${group.items.length} referensi detail tersedia',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.88),
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: const Icon(Icons.close_rounded),
                        color: Colors.white,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SelectionArea(
                    child: ListView.separated(
                      padding: const EdgeInsets.all(18),
                      itemCount: group.items.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 14),
                      itemBuilder: (context, index) {
                        final item = group.items[index];
                        return _buildDetailPanel(item, index);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailPanel(PanduanKbliEntry item, int index) {
    final isKategoriC = _isKategoriC(item.kategori);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAFF),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFF2D77D0).withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFF2D77D0).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    color: Color(0xFF144A8B),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildDialogTag(
                          icon: Icons.confirmation_number_outlined,
                          label: item.kbli2025.isEmpty
                              ? 'KBLI belum diisi'
                              : 'KBLI ${item.kbli2025}',
                        ),
                        if (item.kategori.isNotEmpty)
                          _buildDialogTag(
                            icon: Icons.category_outlined,
                            label: 'Kategori ${item.kategori}',
                          ),
                        _buildDialogTag(
                          icon: isKategoriC
                              ? Icons.account_tree_outlined
                              : Icons.inventory_2_outlined,
                          label: isKategoriC
                              ? 'Tampil input, proses, output'
                              : 'Tampil output kegiatan',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (item.keteranganKbli.isNotEmpty) ...[
            _buildDetailSection(
              icon: Icons.info_outline_rounded,
              title: 'Keterangan KBLI',
              content: item.keteranganKbli,
            ),
            const SizedBox(height: 12),
          ],
          _buildDecisionFlow(item),
          const SizedBox(height: 12),
          if (isKategoriC) ...[
            _buildDetailSection(
              icon: Icons.input_rounded,
              title: 'Input Kegiatan',
              content: item.input,
            ),
            const SizedBox(height: 12),
            _buildDetailSection(
              icon: Icons.settings_suggest_outlined,
              title: 'Proses Kegiatan',
              content: item.proses,
            ),
            const SizedBox(height: 12),
          ],
          _buildDetailSection(
            icon: Icons.inventory_2_outlined,
            title: 'Output Kegiatan',
            content: item.output,
          ),
        ],
      ),
    );
  }

  Widget _buildDialogTag({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: const Color(0xFF2D77D0)),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A365B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDecisionFlow(PanduanKbliEntry item) {
    final steps = <Widget>[];
    String? stopMessage;

    if (!_hasValue(item.produksi)) {
      stopMessage = 'Alur berhenti karena data produksi belum tersedia.';
      return _buildDecisionFlowCard(steps: steps, stopMessage: stopMessage);
    }

    final isLayanan = _isPositive(item.layananMakanMinum);
    final isPenjualan = _isPositive(item.penjualan);

    steps.add(
      _buildDecisionStep(
        number: 1,
        question: 'Apakah usaha ini produksi?',
        answer: _yesNoText(item.produksi),
        active: _isPositive(item.produksi),
      ),
    );

    if (!_hasValue(item.layananMakanMinum)) {
      stopMessage =
          'Alur berhenti karena data layanan makan/minum belum tersedia.';
      return _buildDecisionFlowCard(steps: steps, stopMessage: stopMessage);
    }

    steps.add(
      _buildDecisionStep(
        number: 2,
        question: 'Apakah ada layanan makan/minum?',
        answer: _yesNoText(item.layananMakanMinum),
        active: isLayanan,
      ),
    );

    if (!isLayanan && !_hasValue(item.penjualan)) {
      stopMessage = 'Alur berhenti karena data penjualan belum tersedia.';
      return _buildDecisionFlowCard(steps: steps, stopMessage: stopMessage);
    }

    if (!isLayanan) {
      steps.add(
        _buildDecisionStep(
          number: 3,
          question: 'Apakah melakukan penjualan?',
          answer: _yesNoText(item.penjualan),
          active: isPenjualan,
        ),
      );
    }

    if (!isLayanan && !isPenjualan && !_hasValue(item.aktivitas)) {
      stopMessage = 'Alur berhenti karena data aktivitas belum tersedia.';
      return _buildDecisionFlowCard(steps: steps, stopMessage: stopMessage);
    }

    if (!isLayanan && !isPenjualan) {
      steps.add(
        _buildDecisionStep(
          number: 4,
          question: 'Aktivitas utamanya masuk jasa atau pertanian?',
          answer: item.aktivitas,
          active: true,
          isFreeText: true,
        ),
      );
    }

    return _buildDecisionFlowCard(steps: steps, stopMessage: stopMessage);
  }

  Widget _buildDecisionFlowCard({
    required List<Widget> steps,
    String? stopMessage,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Alur Pertanyaan',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: Color(0xFF162F4D),
            ),
          ),
          if (steps.isNotEmpty) ...[
            const SizedBox(height: 10),
            ..._withSpacing(steps, spacing: 10),
          ],
          if (stopMessage != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E8),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color(0xFFE8C56A).withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.pause_circle_outline_rounded,
                    size: 18,
                    color: Color(0xFF9A6B00),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      stopMessage,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.45,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF8A6200),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDecisionStep({
    required int number,
    required String question,
    required String answer,
    required bool active,
    bool isFreeText = false,
  }) {
    final color = active ? const Color(0xFF1D8F5A) : const Color(0xFF8A94A6);
    final icon = isFreeText
        ? Icons.alt_route_rounded
        : active
        ? Icons.check_circle_rounded
        : Icons.remove_circle_outline;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Text(
              '$number',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  question,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A365B),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 16, color: color),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        answer,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: color,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailSection({
    required IconData icon,
    required String title,
    required String content,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: const Color(0xFF2D77D0)),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF162F4D),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            content.isEmpty ? '-' : content,
            style: TextStyle(
              fontSize: 14,
              height: 1.55,
              color: Colors.blueGrey[700],
            ),
          ),
        ],
      ),
    );
  }

  bool _isPositive(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized == 'y' ||
        normalized == 'ya' ||
        normalized == '1' ||
        normalized == 'true' ||
        normalized == 'v' ||
        normalized == 'yes';
  }

  String _yesNoText(String value) {
    return _isPositive(value) ? 'Ya' : 'Tidak';
  }

  bool _isKategoriC(String value) {
    return value.trim().toUpperCase().startsWith('C');
  }

  bool _hasValue(String value) {
    return value.trim().isNotEmpty;
  }

  List<Widget> _withSpacing(List<Widget> children, {double spacing = 0}) {
    final items = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        items.add(SizedBox(height: spacing));
      }
      items.add(children[i]);
    }
    return items;
  }
}

class _KbliGroupData {
  final String title;
  final List<PanduanKbliEntry> items;

  const _KbliGroupData({required this.title, required this.items});
}
