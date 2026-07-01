import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models/anomali_item.dart';
import '../../data/services/anomali_service.dart';

class WilayahAnomaliPage extends StatefulWidget {
  const WilayahAnomaliPage({super.key});

  @override
  State<WilayahAnomaliPage> createState() => _WilayahAnomaliPageState();
}

class _WilayahAnomaliPageState extends State<WilayahAnomaliPage> {
  static const String _allStatus = 'Semua status';
  static const String _allKategori = 'Semua kategori';
  static const int _pageSize = 500;

  final AnomalyService _service = AnomalyService();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _offset = 0;
  String? _error;
  String _query = '';
  String _selectedStatus = _allStatus;
  String _selectedKategori = _allKategori;
  List<AnomalyItem> _items = [];

  // field_name -> {value -> label}
  Map<String, Map<String, String>> _fieldOptions = {};

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadFieldOptions();
    _loadData();
  }

  Future<void> _loadFieldOptions() async {
    try {
      final raw = await rootBundle
          .loadString('assets/json/anomali_field_options.json');
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final parsed = <String, Map<String, String>>{};
      for (final entry in json.entries) {
        final opts = (entry.value['options'] as List)
            .cast<Map<String, dynamic>>();
        parsed[entry.key] = {
          for (final o in opts)
            o['value'].toString(): o['label'].toString()
        };
      }
      if (mounted) setState(() => _fieldOptions = parsed);
    } catch (_) {}
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 300 &&
        !_isLoadingMore &&
        _hasMore) {
      _loadMore();
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _offset = 0;
      _hasMore = true;
      _items = [];
    });

    try {
      final items = await _service.fetchAnomalyWilayah(
        limit: _pageSize,
        offset: 0,
      );
      if (!mounted) return;
      setState(() {
        _items = items;
        _offset = items.length;
        _hasMore = items.length >= _pageSize;
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

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);

    try {
      final newItems = await _service.fetchAnomalyWilayah(
        limit: _pageSize,
        offset: _offset,
      );
      if (!mounted) return;
      setState(() {
        _items = [..._items, ...newItems];
        _offset += newItems.length;
        _hasMore = newItems.length >= _pageSize;
        _isLoadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _refreshData() => _loadData();

  List<String> get _statusOptions {
    final values = _items
        .map((item) => item.statusTindakLanjut)
        .where((v) => v.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return [_allStatus, ...values];
  }

  List<String> get _kategoriOptions {
    final values = _items
        .map((item) => item.kategori)
        .where((v) => v.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return [_allKategori, ...values];
  }

  List<AnomalyItem> get _filteredItems {
    final query = _query.trim().toLowerCase();
    final result = _items.where((item) {
      if (_selectedStatus != _allStatus &&
          item.statusTindakLanjut != _selectedStatus) {
        return false;
      }
      if (_selectedKategori != _allKategori &&
          item.kategori != _selectedKategori) {
        return false;
      }
      if (query.isEmpty) return true;

      final haystack = [
        item.namaSubjek,
        item.namaWilayah,
        item.kodeWilayah,
        item.kategori,
        item.deskripsi,
        item.assignmentId,
      ].join(' ').toLowerCase();

      return haystack.contains(query);
    }).toList();

    result.sort((a, b) => a.kodeWilayah.compareTo(b.kodeWilayah));
    return result;
  }

  int get _wilayahTerdampakCount => _items
      .map((item) => item.kodeWilayah)
      .where((v) => v.isNotEmpty)
      .toSet()
      .length;

  int get _sudahDitindakCount =>
      _items.where((item) => item.sudahDitindaklanjuti).length;

  @override
  Widget build(BuildContext context) {
    final items = _filteredItems;

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
                        controller: _scrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: [
                          SliverToBoxAdapter(child: _buildHeroSection()),
                          SliverToBoxAdapter(child: _buildSearchSection()),
                          SliverToBoxAdapter(
                            child: _buildSectionHeader(resultCount: items.length),
                          ),
                          if (items.isEmpty)
                            SliverFillRemaining(
                              hasScrollBody: false,
                              child: _buildEmptyState(),
                            )
                          else
                            SliverPadding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                              sliver: SliverList.separated(
                                itemCount: items.length,
                                itemBuilder: (context, index) =>
                                    _buildAnomaliTile(items[index], index),
                                separatorBuilder: (context, index) =>
                                    const SizedBox(height: 12),
                              ),
                            ),
                          SliverToBoxAdapter(
                            child: _buildPaginationFooter(),
                          ),
                        ],
                      ),
                    ),
        ),
      ),
    );
  }

  Widget _buildPaginationFooter() {
    if (_isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (!_hasMore && _items.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(0, 12, 0, 120),
        child: Center(
          child: Text(
            'Semua ${_items.length} anomali telah dimuat',
            style: TextStyle(color: Colors.blueGrey[400], fontSize: 13),
          ),
        ),
      );
    }
    return const SizedBox(height: 120);
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
          colors: [Color(0xFF7A0F42), Color(0xFFB31E63), Color(0xFFE56D8C)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFB31E63).withValues(alpha: 0.22),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.warning_amber_rounded, color: Colors.white),
              ),
              const SizedBox(width: 18),
              const Expanded(
                child: Text(
                  'Anomali Wilayah',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Pantau dan tindak lanjuti anomali pada seluruh wilayah tugas.',
            style: TextStyle(color: Colors.white, height: 1.45),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildHeroBadge(
                icon: Icons.warning_amber_rounded,
                label: '${_items.length}${_hasMore ? '+' : ''} anomali',
              ),
              _buildHeroBadge(
                icon: Icons.map_outlined,
                label: '$_wilayahTerdampakCount wilayah terdampak',
              ),
              _buildHeroBadge(
                icon: Icons.task_alt_rounded,
                label: '$_sudahDitindakCount ditindak',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeroBadge({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
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
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: 'Cari nama, wilayah, kategori, atau assignment',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isEmpty
                    ? IconButton(
                        onPressed: _refreshData,
                        icon: const Icon(Icons.refresh_rounded),
                      )
                    : IconButton(
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
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
          _buildFilterGroup(
            title: 'Status',
            options: _statusOptions,
            selectedValue: _selectedStatus,
            onSelected: (v) => setState(() => _selectedStatus = v),
          ),
          const SizedBox(height: 10),
          _buildFilterGroup(
            title: 'Kategori',
            options: _kategoriOptions,
            selectedValue: _selectedKategori,
            onSelected: (v) => setState(() => _selectedKategori = v),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterGroup({
    required String title,
    required List<String> options,
    required String selectedValue,
    required ValueChanged<String> onSelected,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Color(0xFF3D5066),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: options.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final option = options[index];
              final isSelected = option == selectedValue;
              return FilterChip(
                label: Text(_prettyOption(option)),
                selected: isSelected,
                onSelected: (_) => onSelected(option),
                showCheckmark: false,
                selectedColor: const Color(0xFFB31E63).withValues(alpha: 0.12),
                backgroundColor: Colors.white,
                side: BorderSide(
                  color: isSelected
                      ? const Color(0xFFB31E63)
                      : Colors.grey.withValues(alpha: 0.24),
                ),
                labelStyle: TextStyle(
                  color: isSelected
                      ? const Color(0xFF8B154A)
                      : const Color(0xFF526070),
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader({required int resultCount}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Daftar Anomali',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  '$resultCount hasil tampil',
                  style: TextStyle(color: Colors.blueGrey[600], fontSize: 13),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.withValues(alpha: 0.18)),
            ),
            child: Text(
              _selectedStatus == _allStatus
                  ? _prettyOption(_selectedKategori)
                  : _prettyOption(_selectedStatus),
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Color(0xFF8B154A),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnomaliTile(AnomalyItem item, int index) {
    final hasCatatan = item.catatanPetugas.isNotEmpty;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => _showAnomaliDetail(item),
        child: Ink(
          decoration: BoxDecoration(
            color: hasCatatan ? const Color(0xFFFFF3E0) : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: hasCatatan
                  ? const Color(0xFFFFB74D).withValues(alpha: 0.6)
                  : _statusColor(item.statusTindakLanjut).withValues(alpha: 0.2),
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
                      colors: [Color(0xFF7A0F42), Color(0xFFCF376B)],
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
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              item.subjekLabel,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF10243E),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          _buildStatusChip(item.statusTindakLanjut),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        item.wilayahLabel,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: Colors.blueGrey[700],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        item.deskripsi,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.45,
                          color: Colors.blueGrey[600],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildMiniBadge(
                            icon: Icons.category_outlined,
                            label: _prettyOption(item.kategori),
                          ),
                          _buildMiniBadge(
                            icon: Icons.warning_amber_outlined,
                            label: item.isFatal ? 'Fatal Error' : 'Warning',
                          ),
                          _buildMiniBadge(
                            icon: Icons.pin_outlined,
                            label: item.kodeWilayah.isEmpty
                                ? 'Kode -'
                                : item.kodeWilayah,
                          ),
                        ],
                      ),
                      if (item.diperiksaAt != null ||
                          item.catatanPetugas.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            item.diperiksaAt != null
                                ? 'Diperiksa ${_formatDateTime(item.diperiksaAt)} oleh ${item.diperiksaOleh.isEmpty ? '-' : item.diperiksaOleh}'
                                : 'Catatan: ${item.catatanPetugas}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blueGrey[500],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      if (hasCatatan)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            children: const [
                              Icon(
                                Icons.check_circle_rounded,
                                size: 14,
                                color: Color(0xFFE65100),
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Sudah ada catatan',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFFE65100),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEEF5),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.edit_note_rounded,
                    size: 20,
                    color: Color(0xFFB31E63),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
        ],
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        _prettyOption(status),
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
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
                Icons.search_off_rounded,
                size: 38,
                color: Color(0xFFB31E63),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Anomali tidak ditemukan',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'Coba ubah kata kunci pencarian atau filter status dan kategori.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.blueGrey[600], height: 1.5),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () {
                _searchController.clear();
                setState(() {
                  _query = '';
                  _selectedStatus = _allStatus;
                  _selectedKategori = _allKategori;
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
              'Gagal memuat anomali wilayah',
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
              onPressed: _loadData,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Coba Lagi'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAnomaliDetail(AnomalyItem item) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final noteController = TextEditingController(text: item.catatanPetugas);
    var selectedStatus = item.statusTindakLanjut.isEmpty
        ? 'belum_diperiksa'
        : item.statusTindakLanjut;
    var isSaving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: DraggableScrollableSheet(
                initialChildSize: 0.88,
                minChildSize: 0.55,
                maxChildSize: 0.95,
                expand: false,
                builder: (context, scrollController) {
                  return Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFFF7F9FC),
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(28),
                      ),
                    ),
                    child: Column(
                      children: [
                        Container(
                          margin: const EdgeInsets.only(top: 10),
                          width: 48,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        Expanded(
                          child: ListView(
                            controller: scrollController,
                            padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.subjekLabel,
                                          style: const TextStyle(
                                            fontSize: 22,
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFF10243E),
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          item.wilayahLabel,
                                          style: TextStyle(
                                            color: Colors.blueGrey[700],
                                            height: 1.4,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () =>
                                        Navigator.of(sheetContext).pop(),
                                    icon: const Icon(Icons.close_rounded),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _buildStatusChip(selectedStatus),
                                  _buildMiniBadge(
                                    icon: Icons.category_outlined,
                                    label: _prettyOption(item.kategori),
                                  ),
                                  _buildMiniBadge(
                                    icon: Icons.warning_amber_outlined,
                                    label: item.isFatal
                                        ? 'Fatal Error'
                                        : 'Warning',
                                  ),
                                ],
                              ),
                              const SizedBox(height: 18),
                              _buildDetailPanel(
                                icon: Icons.info_outline_rounded,
                                title: 'Keterangan Anomali',
                                content: item.deskripsi,
                              ),
                              if (item.detail.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                _buildDetailTable(item.detail),
                              ],
                              const SizedBox(height: 18),
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Tindak Lanjut',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF162F4D),
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    DropdownButtonFormField<String>(
                                      key: ValueKey(selectedStatus),
                                      initialValue: selectedStatus,
                                      decoration: const InputDecoration(
                                        labelText: 'Status tindak lanjut',
                                        border: OutlineInputBorder(),
                                      ),
                                      items: _statusOptions
                                          .where((v) => v != _allStatus)
                                          .map(
                                            (v) => DropdownMenuItem(
                                              value: v,
                                              child: Text(_prettyOption(v)),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: isSaving
                                          ? null
                                          : (v) {
                                              if (v == null) return;
                                              setSheetState(
                                                  () => selectedStatus = v);
                                            },
                                    ),
                                    const SizedBox(height: 14),
                                    TextField(
                                      controller: noteController,
                                      maxLines: 4,
                                      enabled: !isSaving,
                                      decoration: const InputDecoration(
                                        labelText: 'Catatan petugas',
                                        alignLabelWithHint: true,
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        onPressed: isSaving
                                            ? null
                                            : () async {
                                                setSheetState(
                                                    () => isSaving = true);
                                                try {
                                                  await _service
                                                      .upsertTindakLanjut(
                                                    assignmentId:
                                                        item.assignmentId,
                                                    kategori: item.kategori,
                                                    noAnomali: item.noAnomali,
                                                    statusTindakLanjut:
                                                        selectedStatus,
                                                    catatanPetugas:
                                                        noteController.text,
                                                  );
                                                  if (!mounted ||
                                                      !sheetContext.mounted) {
                                                    return;
                                                  }
                                                  Navigator.of(sheetContext)
                                                      .pop();
                                                  await _refreshData();
                                                  if (!mounted) return;
                                                  scaffoldMessenger
                                                      .showSnackBar(
                                                    const SnackBar(
                                                      content: Text(
                                                        'Status tindak lanjut berhasil diperbarui',
                                                      ),
                                                    ),
                                                  );
                                                } catch (e) {
                                                  setSheetState(
                                                      () => isSaving = false);
                                                  scaffoldMessenger
                                                      .showSnackBar(
                                                    SnackBar(
                                                      content: Text(
                                                          'Gagal menyimpan: $e'),
                                                      backgroundColor:
                                                          Colors.red,
                                                    ),
                                                  );
                                                }
                                              },
                                        icon: isSaving
                                            ? const SizedBox(
                                                width: 18,
                                                height: 18,
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: Colors.white,
                                                ),
                                              )
                                            : const Icon(Icons.save_outlined),
                                        label: Text(
                                            isSaving ? 'Menyimpan...' : 'Simpan'),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );

    noteController.dispose();
  }

  static const Map<String, String> _fieldLabels = {
    'jns_lantai': 'Jenis Lantai',
    'jns_dinding': 'Jenis Dinding',
    'jns_atap': 'Jenis Atap',
    'jumlah_lahan': 'Jumlah Lahan',
    'jumlah_rumah': 'Jumlah Rumah',
    'jumlah_anggota': 'Jumlah Anggota Keluarga',
    'jumlah_anak': 'Jumlah Anak',
    'luas_lantai': 'Luas Lantai (m²)',
    'sumber_air': 'Sumber Air',
    'fasilitas_bab': 'Fasilitas BAB',
    'bahan_bakar': 'Bahan Bakar Memasak',
    'penerangan': 'Sumber Penerangan',
    'status_lahan': 'Status Lahan',
    'status_bangunan': 'Status Bangunan',
    'pengeluaran': 'Pengeluaran (Rp)',
    'pendapatan': 'Pendapatan (Rp)',
    'badan_usaha': 'Badan Usaha',
    'omzet': 'Omzet (Rp)',
    'jumlah_pekerja': 'Jumlah Pekerja',
    'no_usaha': 'Nomor Usaha',
    'nama_usaha': 'Nama Usaha',
    'kode_wilayah': 'Kode Wilayah',
    'nilai': 'Nilai',
    'batas_bawah': 'Batas Bawah',
    'batas_atas': 'Batas Atas',
    'selisih': 'Selisih',
    'expected': 'Nilai Wajar',
    'actual': 'Nilai Aktual',
    'count': 'Jumlah',
    'pct': 'Persentase (%)',
  };

  String _labelFor(String key) =>
      _fieldLabels[key] ??
      key.split('_').map((w) => '${w[0].toUpperCase()}${w.substring(1)}').join(' ');

  Widget _buildDetailTable(Map<String, dynamic> detail) {
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
            children: const [
              Icon(Icons.notes_rounded, size: 18, color: Color(0xFFB31E63)),
              SizedBox(width: 8),
              Text(
                'Detail Anomali',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF162F4D),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...detail.entries.map((e) {
                final rawValue = e.value?.toString() ?? '';
                final mapped = _fieldOptions[e.key]?[rawValue];
                final displayValue = mapped != null
                    ? mapped.replaceFirst(RegExp(r'^\d+[\.\w]*\s*'), '')
                    : rawValue.isEmpty ? '-' : rawValue;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 4,
                        child: Text(
                          _labelFor(e.key),
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.blueGrey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 5,
                        child: Text(
                          displayValue,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF162F4D),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
        ],
      ),
    );
  }

  Widget _buildDetailPanel({
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
              Icon(icon, size: 18, color: const Color(0xFFB31E63)),
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

  Color _statusColor(String status) {
    switch (status) {
      case 'dikonfirmasi_valid':
        return const Color(0xFF0F9D58);
      case 'dikonfirmasi_salah_entri':
        return const Color(0xFFD97706);
      case 'sudah_diperbaiki':
        return const Color(0xFF1F6FEB);
      case 'belum_diperiksa':
      default:
        return const Color(0xFFB31E63);
    }
  }

  String _prettyOption(String value) {
    if (value.isEmpty) return '-';
    if (value == _allStatus || value == _allKategori) return value;
    return value.split('_').map(_capitalize).join(' ');
  }

  String _capitalize(String value) {
    if (value.isEmpty) return value;
    return '${value[0].toUpperCase()}${value.substring(1)}';
  }

  String _formatDateTime(DateTime? value) {
    if (value == null) return '-';
    final local = value.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day/$month/${local.year} $hour:$minute';
  }
}
