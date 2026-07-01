import 'package:flutter/material.dart';

import '../../data/models/anomali_pusat_item.dart';
import '../../data/models/keterangan_pusat_item.dart';
import '../../data/services/anomali_service.dart';

class AnomaliPusatPage extends StatefulWidget {
  const AnomaliPusatPage({super.key});

  @override
  State<AnomaliPusatPage> createState() => _AnomaliPusatPageState();
}

class _AnomaliPusatPageState extends State<AnomaliPusatPage> {
  static const String _allKategori = 'Semua kategori';
  static const String _allStatus = 'Semua status';
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
  String _selectedKategori = _allKategori;
  String _selectedStatus = _allStatus;
  List<AnomaliPusatItem> _items = [];
  Set<String> _myKeteranganKeys = {};

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
      final results = await Future.wait([
        _service.fetchAnomalyPusat(limit: _pageSize, offset: 0),
        _service.fetchMyKeteranganKeys(),
      ]);
      if (!mounted) return;
      final items = results[0] as List<AnomaliPusatItem>;
      final keys = results[1] as Set<String>;
      setState(() {
        _items = items;
        _myKeteranganKeys = keys;
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
      final newItems = await _service.fetchAnomalyPusat(
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

  List<String> get _kategoriOptions {
    final vals = _items
        .map((e) => e.kategori)
        .where((v) => v.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return [_allKategori, ...vals];
  }

  List<String> get _statusOptions {
    final vals = _items
        .map((e) => e.statusText)
        .where((v) => v.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return [_allStatus, ...vals];
  }

  List<AnomaliPusatItem> get _filtered {
    final q = _query.trim().toLowerCase();
    final result = _items.where((item) {
      if (_selectedKategori != _allKategori && item.kategori != _selectedKategori) {
        return false;
      }
      if (_selectedStatus != _allStatus && item.statusText != _selectedStatus) {
        return false;
      }
      if (q.isEmpty) return true;
      final hay = [
        item.nama,
        item.alamat,
        item.namaAnomali,
        item.kategori,
        item.kodeWilayah,
        item.nmKec,
        item.nmDesa,
        item.nmSls,
        item.namaPpl,
        item.namaPml,
      ].join(' ').toLowerCase();
      return hay.contains(q);
    }).toList();
    result.sort((a, b) => a.kodeWilayah.compareTo(b.kodeWilayah));
    return result;
  }

  int get _sudahDitindakCount => _items.where((e) => e.sudahDitindak).length;

  Set<String> get _wilayahSet =>
      _items.map((e) => e.kodeWilayah).where((v) => v.isNotEmpty).toSet();

  @override
  Widget build(BuildContext context) {
    final items = _filtered;
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
                      child: CustomScrollView(
                        controller: _scrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: [
                          SliverToBoxAdapter(child: _buildHero()),
                          SliverToBoxAdapter(child: _buildSearch()),
                          SliverToBoxAdapter(
                            child: _buildSectionHeader(items.length),
                          ),
                          if (items.isEmpty)
                            SliverFillRemaining(
                              hasScrollBody: false,
                              child: _buildEmpty(),
                            )
                          else
                            SliverPadding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                              sliver: SliverList.separated(
                                itemCount: items.length,
                                itemBuilder: (_, i) => _buildTile(items[i], i),
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 12),
                              ),
                            ),
                          SliverToBoxAdapter(child: _buildFooter()),
                        ],
                      ),
                    ),
        ),
      ),
    );
  }

  Widget _buildHero() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A3A6B), Color(0xFF1F6FEB), Color(0xFF5B9BF5)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1F6FEB).withValues(alpha: 0.22),
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
                  Icons.assessment_outlined,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 18),
              const Expanded(
                child: Text(
                  'Anomali Pusat',
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
            'Rekapitulasi anomali dari seluruh petugas berdasarkan hak akses.',
            style: TextStyle(color: Colors.white, height: 1.45),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _badge(
                Icons.warning_amber_rounded,
                '${_items.length}${_hasMore ? '+' : ''} anomali',
              ),
              _badge(Icons.map_outlined, '${_wilayahSet.length} wilayah'),
              _badge(Icons.task_alt_rounded, '$_sudahDitindakCount ditindak'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _badge(IconData icon, String label) {
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

  Widget _buildSearch() {
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
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Cari nama anomali, wilayah, PPL, atau PML',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isEmpty
                    ? IconButton(
                        onPressed: _loadData,
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
          _buildChips(
            title: 'Kategori',
            options: _kategoriOptions,
            selected: _selectedKategori,
            onSelect: (v) => setState(() => _selectedKategori = v),
          ),
          const SizedBox(height: 10),
          _buildChips(
            title: 'Status',
            options: _statusOptions,
            selected: _selectedStatus,
            onSelect: (v) => setState(() => _selectedStatus = v),
          ),
        ],
      ),
    );
  }

  Widget _buildChips({
    required String title,
    required List<String> options,
    required String selected,
    required ValueChanged<String> onSelect,
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
            itemBuilder: (_, i) {
              final opt = options[i];
              final isSelected = opt == selected;
              return FilterChip(
                label: Text(_pretty(opt)),
                selected: isSelected,
                onSelected: (_) => onSelect(opt),
                showCheckmark: false,
                selectedColor: const Color(0xFF1F6FEB).withValues(alpha: 0.12),
                backgroundColor: Colors.white,
                side: BorderSide(
                  color: isSelected
                      ? const Color(0xFF1F6FEB)
                      : Colors.grey.withValues(alpha: 0.24),
                ),
                labelStyle: TextStyle(
                  color: isSelected
                      ? const Color(0xFF1A3A6B)
                      : const Color(0xFF526070),
                  fontWeight:
                      isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Daftar Anomali Pusat',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$count hasil tampil',
                  style: TextStyle(color: Colors.blueGrey[600], fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTile(AnomaliPusatItem item, int index) {
    final statusColor = _statusColor(item.statusText);
    final hasKeterangan = _myKeteranganKeys
        .contains('${item.assignmentId}|${item.namaAnomali}');
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => _showDetail(item),
        child: Ink(
          decoration: BoxDecoration(
            color: hasKeterangan
                ? const Color(0xFFFFF3E0)
                : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: hasKeterangan
                  ? const Color(0xFFFFB74D).withValues(alpha: 0.6)
                  : statusColor.withValues(alpha: 0.2),
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
                      colors: [Color(0xFF1A3A6B), Color(0xFF1F6FEB)],
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
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (item.nama.isNotEmpty)
                                  Text(
                                    item.nama,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF10243E),
                                    ),
                                  ),
                                Text(
                                  item.namaAnomali.isEmpty ? '-' : item.namaAnomali,
                                  style: TextStyle(
                                    fontSize: item.nama.isNotEmpty ? 13 : 15,
                                    fontWeight: item.nama.isNotEmpty
                                        ? FontWeight.w500
                                        : FontWeight.w700,
                                    color: item.nama.isNotEmpty
                                        ? Colors.blueGrey[600]
                                        : const Color(0xFF10243E),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          _statusChip(item.statusText),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        item.lokasiLabel,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: Colors.blueGrey[700],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _miniBadge(
                            Icons.category_outlined,
                            _pretty(item.kategori),
                          ),
                          if (item.alamat.isNotEmpty)
                            _miniBadge(Icons.location_on_outlined, item.alamat),
                          if (item.namaPpl.isNotEmpty)
                            _miniBadge(Icons.person_outline, item.namaPpl),
                          if (item.namaPml.isNotEmpty)
                            _miniBadge(
                                Icons.supervisor_account_outlined, item.namaPml),
                        ],
                      ),
                      if (item.tindakLanjut.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            'Tindak lanjut: ${_pretty(item.tindakLanjut)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blueGrey[500],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      if (hasKeterangan)
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
                                'Sudah ada keterangan',
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
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statusChip(String status) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        _pretty(status),
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _miniBadge(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4FF),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: const Color(0xFF1F6FEB)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A3A6B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showDetail(AnomaliPusatItem item) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AnomaliPusatDetailSheet(
        item: item,
        service: _service,
        onSaved: () {
          final key = '${item.assignmentId}|${item.namaAnomali}';
          setState(() => _myKeteranganKeys = {..._myKeteranganKeys, key});
        },
      ),
    );
  }

  Widget _buildFooter() {
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

  Widget _buildEmpty() {
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
                color: Color(0xFF1F6FEB),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Anomali tidak ditemukan',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'Coba ubah kata kunci pencarian atau filter.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.blueGrey[600], height: 1.5),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () {
                _searchController.clear();
                setState(() {
                  _query = '';
                  _selectedKategori = _allKategori;
                  _selectedStatus = _allStatus;
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
              'Gagal memuat anomali pusat',
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

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'valid':
      case 'dikonfirmasi_valid':
        return const Color(0xFF0F9D58);
      case 'salah_entri':
      case 'dikonfirmasi_salah_entri':
        return const Color(0xFFD97706);
      case 'sudah_diperbaiki':
        return const Color(0xFF1F6FEB);
      default:
        return const Color(0xFF8B154A);
    }
  }

  String _pretty(String value) {
    if (value.isEmpty) return '-';
    if (value == _allKategori || value == _allStatus) return value;
    return value.split('_').map((w) {
      if (w.isEmpty) return w;
      return '${w[0].toUpperCase()}${w.substring(1)}';
    }).join(' ');
  }
}

// ─── Detail sheet dengan keterangan per petugas ───────────────────────────────

class _AnomaliPusatDetailSheet extends StatefulWidget {
  final AnomaliPusatItem item;
  final AnomalyService service;
  final VoidCallback onSaved;

  const _AnomaliPusatDetailSheet({
    required this.item,
    required this.service,
    required this.onSaved,
  });

  @override
  State<_AnomaliPusatDetailSheet> createState() =>
      _AnomaliPusatDetailSheetState();
}

class _AnomaliPusatDetailSheetState extends State<_AnomaliPusatDetailSheet> {
  final TextEditingController _keteranganController = TextEditingController();
  List<KeteranganPusatItem> _keteranganList = [];
  bool _loadingKeterangan = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _fetchKeterangan();
  }

  @override
  void dispose() {
    _keteranganController.dispose();
    super.dispose();
  }

  Future<void> _fetchKeterangan() async {
    setState(() => _loadingKeterangan = true);
    try {
      final list = await widget.service.fetchKeteranganPusat(
        assignmentId: widget.item.assignmentId,
        namaAnomali: widget.item.namaAnomali,
      );
      if (!mounted) return;
      setState(() {
        _keteranganList = list;
        _loadingKeterangan = false;
        // Isi field dengan keterangan milik user sendiri jika ada
        // (item pertama = terbaru, tapi kita cari yang paling relevan)
        // RPC sudah filter per petugas via policy, jadi ambil yang pertama
        if (list.isNotEmpty) {
          _keteranganController.text = list.first.keterangan;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingKeterangan = false);
    }
  }

  Future<void> _simpan() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      await widget.service.upsertKeteranganPusat(
        assignmentId: widget.item.assignmentId,
        namaAnomali: widget.item.namaAnomali,
        keterangan: _keteranganController.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onSaved();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Keterangan berhasil disimpan')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal menyimpan: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.88,
        minChildSize: 0.55,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, scroll) => Container(
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
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
                  children: [
                    // ── Header ──────────────────────────────────────────────
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (item.nama.isNotEmpty)
                                Text(
                                  item.nama,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF10243E),
                                  ),
                                ),
                              Text(
                                item.namaAnomali.isEmpty
                                    ? '-'
                                    : item.namaAnomali,
                                style: TextStyle(
                                  fontSize: item.nama.isNotEmpty ? 14 : 20,
                                  fontWeight: item.nama.isNotEmpty
                                      ? FontWeight.w500
                                      : FontWeight.w800,
                                  color: item.nama.isNotEmpty
                                      ? Colors.blueGrey[600]
                                      : const Color(0xFF10243E),
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _chip(item.statusText),
                        _badge(Icons.category_outlined, _pretty(item.kategori)),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // ── Subjek ───────────────────────────────────────────────
                    _section('Subjek', [
                      _row('Nama', item.nama),
                      _row('Alamat', item.alamat),
                    ]),
                    const SizedBox(height: 12),

                    // ── Lokasi ───────────────────────────────────────────────
                    _section('Lokasi', [
                      _row('Kode Wilayah', item.kodeWilayah),
                      _row('Kecamatan', item.nmKec),
                      _row('Desa/Kelurahan', item.nmDesa),
                      _row('SLS', item.nmSls),
                    ]),
                    const SizedBox(height: 12),

                    // ── Petugas ──────────────────────────────────────────────
                    _section('Petugas', [
                      _row('PPL', item.namaPpl.isEmpty ? '-' : item.namaPpl),
                      _row('PML', item.namaPml.isEmpty ? '-' : item.namaPml),
                    ]),
                    const SizedBox(height: 12),

                    // ── Tindak lanjut ────────────────────────────────────────
                    _section('Tindak Lanjut', [
                      _row(
                        'Status',
                        _pretty(
                          item.tindakLanjut.isEmpty ? '-' : item.tindakLanjut,
                        ),
                      ),
                    ]),
                    const SizedBox(height: 20),

                    // ── Keterangan petugas lain (read-only) ──────────────────
                    if (_loadingKeterangan)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_keteranganList.length > 1)
                      ...[
                        _keteranganListSection(_keteranganList),
                        const SizedBox(height: 20),
                      ],

                    // ── Form input keterangan ────────────────────────────────
                    Container(
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
                              Icon(
                                Icons.edit_note_rounded,
                                size: 20,
                                color: Color(0xFF1F6FEB),
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Keterangan Saya',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF162F4D),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Tuliskan penjelasan atau catatan Anda untuk anomali ini.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blueGrey[500],
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _keteranganController,
                            maxLines: 5,
                            enabled: !_isSaving,
                            decoration: const InputDecoration(
                              hintText: 'Tulis keterangan di sini...',
                              alignLabelWithHint: true,
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _isSaving ? null : _simpan,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1F6FEB),
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
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
                              label: Text(
                                  _isSaving ? 'Menyimpan...' : 'Simpan Keterangan'),
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

  Widget _keteranganListSection(List<KeteranganPusatItem> list) {
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
          ...list.map((k) => _keteranganCard(k)),
        ],
      ),
    );
  }

  Widget _keteranganCard(KeteranganPusatItem k) {
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
          const SizedBox(height: 8),
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

  Widget _section(String title, List<Widget> rows) {
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
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: Color(0xFF162F4D),
            ),
          ),
          const SizedBox(height: 12),
          ...rows,
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
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
              value.isEmpty ? '-' : value,
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
  }

  Widget _chip(String status) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        _pretty(status),
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _badge(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4FF),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: const Color(0xFF1F6FEB)),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A3A6B),
            ),
          ),
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'valid':
      case 'dikonfirmasi_valid':
        return const Color(0xFF0F9D58);
      case 'salah_entri':
      case 'dikonfirmasi_salah_entri':
        return const Color(0xFFD97706);
      case 'sudah_diperbaiki':
        return const Color(0xFF1F6FEB);
      default:
        return const Color(0xFF8B154A);
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
}
