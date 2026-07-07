import 'package:flutter/material.dart';

import '../../data/models/anomali_gabungan_item.dart';
import '../../data/models/keterangan_pusat_item.dart';
import '../../data/services/anomali_service.dart';

class AnomaliPage extends StatefulWidget {
  const AnomaliPage({super.key});

  @override
  State<AnomaliPage> createState() => _AnomaliPageState();
}

class _AnomaliPageState extends State<AnomaliPage> {
  static const String _allSumber = 'Semua sumber';
  static const String _sumberWilayah = 'Wilayah';
  static const String _sumberPusat = 'Pusat';
  static const String _allStatus = 'Semua status';
  static const String _allKategoriBesar = 'Semua kategori';
  static const String _allKategoriRincian = 'Semua rincian';
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
  String _selectedSumber = _allSumber;
  String _selectedStatus = _allStatus;
  String _selectedKategoriBesar = _allKategoriBesar;
  String _selectedKategoriRincian = _allKategoriRincian;
  List<AnomaliGabunganItem> _items = [];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadData();
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
      final items = await _service.fetchAnomaliGabungan(
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
      final newItems = await _service.fetchAnomaliGabungan(
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
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _refreshData() => _loadData();

  List<String> get _statusOptions {
    final values = _items
        .map((item) => item.statusEfektif)
        .where((v) => v.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return [_allStatus, ...values];
  }

  List<String> get _kategoriBesarOptions {
    final values = _items
        .map((item) => item.kategoriBesar)
        .where((v) => v.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return [_allKategoriBesar, ...values];
  }

  /// Opsi rincian dibatasi oleh kategori besar yang sedang dipilih, supaya
  /// tidak nyampur kode KP4/UP1 (pusat) dengan ANOM-001 (wilayah) sekaligus.
  List<String> get _kategoriRincianOptions {
    final values = _items
        .where((item) =>
            _selectedKategoriBesar == _allKategoriBesar ||
            item.kategoriBesar == _selectedKategoriBesar)
        .map((item) => item.kategoriKode)
        .where((v) => v.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return [_allKategoriRincian, ...values];
  }

  List<AnomaliGabunganItem> get _filteredItems {
    final query = _query.trim().toLowerCase();
    final result = _items.where((item) {
      if (_selectedSumber == _sumberWilayah && !item.isWilayah) return false;
      if (_selectedSumber == _sumberPusat && !item.isPusatBaru) return false;
      if (_selectedStatus != _allStatus &&
          item.statusEfektif != _selectedStatus) {
        return false;
      }
      if (_selectedKategoriBesar != _allKategoriBesar &&
          item.kategoriBesar != _selectedKategoriBesar) {
        return false;
      }
      if (_selectedKategoriRincian != _allKategoriRincian &&
          item.kategoriKode != _selectedKategoriRincian) {
        return false;
      }
      if (query.isEmpty) return true;

      final haystack = [
        item.subjek,
        item.namaWilayah,
        item.kodeWilayah,
        item.kategoriBesar,
        item.kategoriKode,
        item.kategoriLabel,
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
                                    const SizedBox(height: 8),
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
          colors: [Color(0xFF4A1550), Color(0xFF8B1D5E), Color(0xFF1F6FEB)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8B1D5E).withValues(alpha: 0.22),
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
                child: const Icon(
                  Icons.report_problem_outlined,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 18),
              const Expanded(
                child: Text(
                  'Anomali',
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
            'Pantau dan tindak lanjuti anomali wilayah dan pusat dalam satu daftar.',
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
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _buildFilterDropdown(
                  icon: Icons.filter_alt_outlined,
                  label: _selectedSumber,
                  options: const [_allSumber, _sumberWilayah, _sumberPusat],
                  onSelected: (v) => setState(() => _selectedSumber = v),
                ),
                const SizedBox(width: 8),
                _buildFilterDropdown(
                  icon: Icons.flag_outlined,
                  label: _selectedStatus,
                  options: _statusOptions,
                  onSelected: (v) => setState(() => _selectedStatus = v),
                ),
                const SizedBox(width: 8),
                _buildFilterDropdown(
                  icon: Icons.category_outlined,
                  label: _selectedKategoriBesar,
                  options: _kategoriBesarOptions,
                  onSelected: (v) => setState(() {
                    _selectedKategoriBesar = v;
                    _selectedKategoriRincian = _allKategoriRincian;
                  }),
                ),
                const SizedBox(width: 8),
                _buildFilterDropdown(
                  icon: Icons.label_outline,
                  label: _selectedKategoriRincian,
                  options: _kategoriRincianOptions,
                  onSelected: (v) => setState(() => _selectedKategoriRincian = v),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterDropdown({
    required IconData icon,
    required String label,
    required List<String> options,
    required ValueChanged<String> onSelected,
  }) {
    final isDefault = label == _allSumber ||
        label == _allStatus ||
        label == _allKategoriBesar ||
        label == _allKategoriRincian;
    return PopupMenuButton<String>(
      onSelected: onSelected,
      itemBuilder: (context) => options
          .map((o) => PopupMenuItem(value: o, child: Text(_prettyOption(o))))
          .toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isDefault ? Colors.white : const Color(0xFF8B1D5E).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDefault
                ? Colors.grey.withValues(alpha: 0.24)
                : const Color(0xFF8B1D5E),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isDefault ? const Color(0xFF526070) : const Color(0xFF6B1245),
            ),
            const SizedBox(width: 6),
            Text(
              _prettyOption(label),
              style: TextStyle(
                fontSize: 13,
                fontWeight: isDefault ? FontWeight.w500 : FontWeight.w700,
                color: isDefault ? const Color(0xFF526070) : const Color(0xFF6B1245),
              ),
            ),
            const Icon(Icons.arrow_drop_down_rounded, size: 18, color: Color(0xFF526070)),
          ],
        ),
      ),
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
        ],
      ),
    );
  }

  Color _sumberColor(String sumber) =>
      sumber == 'kualitas' ? const Color(0xFF8B1D5E) : const Color(0xFF1F6FEB);

  Widget _buildSumberBadge(AnomaliGabunganItem item) {
    final color = _sumberColor(item.sumber);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            item.isWilayah ? Icons.map_outlined : Icons.assessment_outlined,
            size: 13,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            item.sumberLabel,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnomaliTile(AnomaliGabunganItem item, int index) {
    final sudahDiperiksa = item.sudahDitindaklanjuti;
    final accentColor = _sumberColor(item.sumber);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _showAnomaliDetail(item),
        child: Ink(
          decoration: BoxDecoration(
            color: sudahDiperiksa ? const Color(0xFFF0FBF4) : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: sudahDiperiksa
                  ? const Color(0xFF0F9D58).withValues(alpha: 0.35)
                  : _statusColor(item.statusEfektif).withValues(alpha: 0.2),
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
            padding: const EdgeInsets.all(13),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(
                      colors: [accentColor, accentColor.withValues(alpha: 0.6)],
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 11),
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
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF10243E),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _buildStatusChip(item.statusEfektif),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.wilayahLengkapLabel,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.3,
                          color: Colors.blueGrey[700],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item.deskripsi,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          color: Colors.blueGrey[600],
                        ),
                      ),
                      const SizedBox(height: 9),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _buildSumberBadge(item),
                          _buildMiniBadge(
                            icon: Icons.category_outlined,
                            label: item.kategoriBesarLabel,
                          ),
                          if (item.namaPetugas.isNotEmpty)
                            _buildMiniBadge(
                              icon: Icons.person_outline,
                              label: item.namaPetugas,
                            ),
                        ],
                      ),
                    ],
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F9FD),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: const Color(0xFF3D6B9D)),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF3D5066),
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'dikonfirmasi_valid':
      case 'konfirmasi_valid':
        return Icons.verified_rounded;
      case 'sudah_diperiksa':
        return Icons.check_circle_rounded;
      case 'dikonfirmasi_salah_entri':
      case 'perbaikan':
      case 'sudah_diperbaiki':
        return Icons.build_rounded;
      case 'belum_diperiksa':
      default:
        return Icons.pending_outlined;
    }
  }

  Widget _buildStatusChip(String status) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_statusIcon(status), size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            _prettyOption(status),
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
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
                Icons.search_off_rounded,
                size: 38,
                color: Color(0xFF8B1D5E),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Anomali tidak ditemukan',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'Coba ubah kata kunci pencarian atau filter sumber, status, dan kategori.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.blueGrey[600], height: 1.5),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () {
                _searchController.clear();
                setState(() {
                  _query = '';
                  _selectedSumber = _allSumber;
                  _selectedStatus = _allStatus;
                  _selectedKategoriBesar = _allKategoriBesar;
                  _selectedKategoriRincian = _allKategoriRincian;
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
              'Gagal memuat anomali',
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

  Future<void> _showAnomaliDetail(AnomaliGabunganItem item) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AnomaliDetailSheet(
        item: item,
        service: _service,
        onSaved: _refreshData,
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'dikonfirmasi_valid':
      case 'konfirmasi_valid':
      case 'sudah_diperiksa':
        return const Color(0xFF0F9D58);
      case 'dikonfirmasi_salah_entri':
      case 'perbaikan':
        return const Color(0xFFD97706);
      case 'sudah_diperbaiki':
        return const Color(0xFF1F6FEB);
      case 'belum_diperiksa':
      default:
        return const Color(0xFF8B1D5E);
    }
  }

  String _prettyOption(String value) {
    if (value.isEmpty) return '-';
    if (value == _allStatus ||
        value == _allKategoriBesar ||
        value == _allKategoriRincian ||
        value == _allSumber) {
      return value;
    }
    return value.split('_').map(_capitalize).join(' ');
  }

  String _capitalize(String value) {
    if (value.isEmpty) return value;
    return '${value[0].toUpperCase()}${value.substring(1)}';
  }

}

// ─── Detail sheet gabungan: respons 2 pilihan (perbaikan/data benar) ──────
// Dipakai kedua sumber ('kualitas' & 'pusat_baru') -- lihat
// upsert_anomali_respons()/get_anomali_respons() di
// supabase/migrations/20260703150000_anomali_respons_gabungan.sql.

class _AnomaliDetailSheet extends StatefulWidget {
  final AnomaliGabunganItem item;
  final AnomalyService service;
  final Future<void> Function() onSaved;

  const _AnomaliDetailSheet({
    required this.item,
    required this.service,
    required this.onSaved,
  });

  @override
  State<_AnomaliDetailSheet> createState() => _AnomaliDetailSheetState();
}

class _AnomaliDetailSheetState extends State<_AnomaliDetailSheet> {
  late final TextEditingController _keteranganController;
  late String? _jenisRespons;
  bool _isSaving = false;
  bool _loadingThread = true;
  List<KeteranganPusatItem> _thread = [];

  @override
  void initState() {
    super.initState();
    _keteranganController =
        TextEditingController(text: widget.item.keterangan ?? '');
    _jenisRespons = widget.item.jenisRespons;
    _fetchThread();
  }

  @override
  void dispose() {
    _keteranganController.dispose();
    super.dispose();
  }

  Future<void> _fetchThread() async {
    final item = widget.item;
    setState(() => _loadingThread = true);
    try {
      final list = await widget.service.fetchAnomaliRespons(
        sumber: item.sumber,
        scope: item.kategoriBesar,
        assignmentId: item.assignmentId,
        kategoriKode: item.kategoriKode,
        namaSubjek: item.responsNamaSubjek,
      );
      if (!mounted) return;
      setState(() {
        _thread = list;
        _loadingThread = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingThread = false);
    }
  }

  Future<void> _simpan(String jenisRespons) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final item = widget.item;
    final keterangan = _keteranganController.text.trim();

    if (jenisRespons == 'konfirmasi_valid' && keterangan.isEmpty) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('Keterangan wajib diisi untuk konfirmasi data benar'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      await widget.service.upsertAnomaliRespons(
        sumber: item.sumber,
        scope: item.kategoriBesar,
        assignmentId: item.assignmentId,
        kategoriKode: item.kategoriKode,
        jenisRespons: jenisRespons,
        namaSubjek: item.responsNamaSubjek,
        keterangan: keterangan.isEmpty ? null : keterangan,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      await widget.onSaved();
      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text('Respons berhasil disimpan')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Gagal menyimpan: $e'), backgroundColor: Colors.red),
      );
    }
  }

  String _pretty(String value) {
    if (value.isEmpty) return '-';
    return value.split('_').map((w) {
      if (w.isEmpty) return w;
      return '${w[0].toUpperCase()}${w.substring(1)}';
    }).join(' ');
  }

  String _formatDate(DateTime dt) {
    final l = dt.toLocal();
    final d = l.day.toString().padLeft(2, '0');
    final m = l.month.toString().padLeft(2, '0');
    final h = l.hour.toString().padLeft(2, '0');
    final min = l.minute.toString().padLeft(2, '0');
    return '$d/$m/${l.year} $h:$min';
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.88,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF7F9FC),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
                            crossAxisAlignment: CrossAxisAlignment.start,
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
                                item.wilayahLengkapLabel,
                                style: TextStyle(
                                  color: Colors.blueGrey[700],
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: (item.isWilayah
                                    ? const Color(0xFF8B1D5E)
                                    : const Color(0xFF1F6FEB))
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: Text(
                            item.sumberLabel,
                            style: TextStyle(
                              color: item.isWilayah
                                  ? const Color(0xFF8B1D5E)
                                  : const Color(0xFF1F6FEB),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF6F9FD),
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: Text(
                            item.kategoriRincianLabel,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF3D5066),
                            ),
                          ),
                        ),
                        if (item.namaPetugas.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF6F9FD),
                              borderRadius: BorderRadius.circular(30),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.person_outline,
                                    size: 14, color: Color(0xFF3D6B9D)),
                                const SizedBox(width: 5),
                                Text(
                                  item.namaPetugas,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF3D5066),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Keterangan Anomali',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF162F4D),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            item.deskripsi.isEmpty ? '-' : item.deskripsi,
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.55,
                              color: Colors.blueGrey[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (_loadingThread)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_thread.isNotEmpty) ...[
                      _buildThreadSection(),
                      const SizedBox(height: 18),
                    ],
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
                            'Respons Saya',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF162F4D),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Pilih salah satu, isi keterangan bila diperlukan.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blueGrey[500],
                            ),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _isSaving
                                      ? null
                                      : () => setState(
                                          () => _jenisRespons = 'perbaikan'),
                                  style: OutlinedButton.styleFrom(
                                    backgroundColor: _jenisRespons == 'perbaikan'
                                        ? const Color(0xFFD97706)
                                            .withValues(alpha: 0.12)
                                        : null,
                                    side: BorderSide(
                                      color: _jenisRespons == 'perbaikan'
                                          ? const Color(0xFFD97706)
                                          : Colors.grey.withValues(alpha: 0.4),
                                    ),
                                  ),
                                  icon: const Icon(Icons.build_outlined),
                                  label: const Text('Perbaikan'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _isSaving
                                      ? null
                                      : () => setState(
                                          () => _jenisRespons = 'konfirmasi_valid'),
                                  style: OutlinedButton.styleFrom(
                                    backgroundColor:
                                        _jenisRespons == 'konfirmasi_valid'
                                            ? const Color(0xFF0F9D58)
                                                .withValues(alpha: 0.12)
                                            : null,
                                    side: BorderSide(
                                      color: _jenisRespons == 'konfirmasi_valid'
                                          ? const Color(0xFF0F9D58)
                                          : Colors.grey.withValues(alpha: 0.4),
                                    ),
                                  ),
                                  icon: const Icon(Icons.verified_outlined),
                                  label: const Text('Data Benar'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _keteranganController,
                            maxLines: 4,
                            enabled: !_isSaving,
                            decoration: InputDecoration(
                              labelText: _jenisRespons == 'konfirmasi_valid'
                                  ? 'Keterangan (wajib)'
                                  : 'Keterangan (opsional)',
                              alignLabelWithHint: true,
                              border: const OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _isSaving || _jenisRespons == null
                                  ? null
                                  : () => _simpan(_jenisRespons!),
                              icon: _isSaving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.save_outlined),
                              label: Text(_isSaving ? 'Menyimpan...' : 'Simpan'),
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
        ),
      ),
    );
  }

  Widget _buildThreadSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.forum_outlined, size: 20, color: Color(0xFF1F6FEB)),
              SizedBox(width: 8),
              Text(
                'Keterangan Tim',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF162F4D),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ..._thread.map(_buildThreadCard),
        ],
      ),
    );
  }

  Widget _buildThreadCard(KeteranganPusatItem k) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4FF),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF1F6FEB).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  k.roleLabel,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A3A6B),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  k.namaPetugas,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF10243E),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                _formatDate(k.updatedAt),
                style: TextStyle(fontSize: 11, color: Colors.blueGrey[400]),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _pretty(k.jenisRespons),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1F6FEB),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            k.keterangan.isEmpty ? '-' : k.keterangan,
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: Colors.blueGrey[700],
            ),
          ),
        ],
      ),
    );
  }
}
