import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_file/open_file.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models/anomali_gabungan_item.dart';
import '../../data/models/anomali_progress_item.dart';
import '../../data/models/keterangan_pusat_item.dart';
import '../../data/services/anomali_export_service.dart';
import '../../data/services/anomali_service.dart';
import '../widgets/progress_donut.dart';

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
  static const String _allPml = 'Semua PML';
  static const String _allVerifikasi = 'Semua verifikasi';
  static const String _sudahVerifikasi = 'Terverifikasi';
  static const String _belumVerifikasi = 'Belum verifikasi';
  static const int _pageSize = 500;

  // ID survei/kegiatan Fasih untuk menyusun URL halaman edit assignment.
  // link_fasih dari export berbentuk .../app/assignment-detail/{id}/edit,
  // sedangkan halaman edit yang benar: .../app/assignment/{surveyId}/{id}/edit.
  static const String _fasihSurveyId = 'fd68e454-ba45-4b85-8205-f3bf777ded24';

  final AnomalyService _service = AnomalyService();
  final AnomaliExportService _exportService = AnomaliExportService();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isExporting = false;

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
  String _selectedVerifikasi = _allVerifikasi;
  List<AnomaliGabunganItem> _items = [];
  List<AnomaliProgressItem> _progress = [];
  List<AnomaliProgressItem> _pmlOptions = [];
  final Set<String> _selectedPmlNames = {};
  int _notifCount = 0;
  bool _filterPerluTindak = false;

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
      final progress = await _service.fetchAnomaliProgress();
      final notif = await _service.fetchNotifCount();
      if (!mounted) return;
      setState(() {
        _items = items;
        _progress = progress;
        _notifCount = notif;
        // Daftar PML untuk filter (hanya admin -> dimensi 'pml').
        if (progress.isNotEmpty && progress.first.dimensi == 'pml') {
          _pmlOptions = progress;
        }
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

  Future<void> _exportExcel() async {
    if (_isExporting) return;
    setState(() => _isExporting = true);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    try {
      // Ambil semua halaman dari server supaya ekspor lengkap (bukan hanya
      // yang sudah ter-scroll), lalu terapkan filter yang sedang aktif.
      final all = <AnomaliGabunganItem>[];
      var offset = 0;
      while (true) {
        final batch = await _service.fetchAnomaliGabungan(
          limit: _pageSize,
          offset: offset,
        );
        all.addAll(batch);
        if (batch.length < _pageSize) break;
        offset += batch.length;
      }

      final rows = _filterItems(all);
      if (rows.isEmpty) {
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('Tidak ada anomali untuk diekspor.')),
        );
        return;
      }

      final path = await _exportService.exportToFile(rows);
      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Berhasil mengekspor ${rows.length} anomali.')),
      );
      await OpenFile.open(path);
    } catch (e) {
      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Gagal mengekspor: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  List<String> get _statusOptions {
    final values =
        _items
            .map((item) => item.statusEfektif)
            .where((v) => v.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return [_allStatus, ...values];
  }

  List<String> get _kategoriBesarOptions {
    final values =
        _items
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
    final values =
        _items
            .where(
              (item) =>
                  _selectedKategoriBesar == _allKategoriBesar ||
                  item.kategoriBesar == _selectedKategoriBesar,
            )
            .map((item) => item.kategoriKode)
            .where((v) => v.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return [_allKategoriRincian, ...values];
  }

  List<AnomaliGabunganItem> get _filteredItems => _filterItems(_items);

  List<AnomaliGabunganItem> _filterItems(List<AnomaliGabunganItem> source) {
    final query = _query.trim().toLowerCase();
    final result = source.where((item) {
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
      if (_selectedVerifikasi == _sudahVerifikasi && !item.isVerified) {
        return false;
      }
      if (_selectedVerifikasi == _belumVerifikasi && item.isVerified) {
        return false;
      }
      if (_selectedPmlNames.isNotEmpty &&
          !_selectedPmlNames.contains(item.namaPml)) {
        return false;
      }
      if (_filterPerluTindak && !item.perluTindakLanjut) {
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

  /// Progres yang ditampilkan di donut/rincian, mengikuti filter PML (admin).
  List<AnomaliProgressItem> get _progressForDisplay {
    if (_selectedPmlNames.isEmpty) return _progress;
    if (_progress.isNotEmpty && _progress.first.dimensi == 'pml') {
      return _progress
          .where((e) => _selectedPmlNames.contains(e.grupNama))
          .toList();
    }
    return _progress;
  }

  int get _progresTotal => _progressForDisplay.fold(0, (s, e) => s + e.total);
  int get _progresSudah => _progressForDisplay.fold(0, (s, e) => s + e.sudah);
  String get _progresDimensi =>
      _progress.isEmpty ? 'self' : _progress.first.dimensi;

  /// Admin dikenali dari breakdown progres per-PML.
  bool get _isAdmin => _progresDimensi == 'pml';
  bool get _progresBisaDrill =>
      _progresDimensi != 'self' && _progressForDisplay.isNotEmpty;

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
                      SliverToBoxAdapter(child: _buildPaginationFooter()),
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final donutSize = (constraints.maxWidth * 0.34).clamp(96.0, 156.0);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.report_problem_outlined,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Text(
                            'Anomali',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_notifCount > 0) ...[
                      const SizedBox(height: 14),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: _buildHeroNotif(),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 16),
              _buildHeroProgress(donutSize),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeroNotif() {
    final active = _filterPerluTindak;
    return InkWell(
      borderRadius: BorderRadius.circular(30),
      onTap: () => setState(() => _filterPerluTindak = !_filterPerluTindak),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active ? Colors.white : const Color(0xFFF59E0B),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: const Color(0xFFF59E0B)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.notifications_active_rounded,
              size: 16,
              color: active ? const Color(0xFFB45309) : Colors.white,
            ),
            const SizedBox(width: 6),
            Text(
              '$_notifCount perlu ditindak',
              style: TextStyle(
                color: active ? const Color(0xFFB45309) : Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroProgress(double size) {
    final donut = ProgressDonut(
      sudah: _progresSudah,
      total: _progresTotal,
      size: size,
      stroke: (size * 0.1).clamp(7.0, 14.0),
      showCount: true,
    );
    if (!_progresBisaDrill) return donut;
    return InkWell(
      borderRadius: BorderRadius.circular(size),
      onTap: _showProgressBreakdown,
      child: Column(mainAxisSize: MainAxisSize.min, children: [donut]),
    );
  }

  Future<void> _showProgressBreakdown() async {
    final dimensi = _progresDimensi;
    final judul = dimensi == 'pml'
        ? 'Progres per Pengawas (PML)'
        : 'Progres per Petugas';
    final rows = [..._progressForDisplay]
      ..sort((a, b) => a.persen.compareTo(b.persen));
    final media = MediaQuery.of(context);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: const Color(0xFFF7F9FC),
        insetPadding: EdgeInsets.symmetric(
          horizontal: media.size.width * 0.05,
          vertical: 24,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 10, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      judul,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF10243E),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Text(
                      '$_progresSudah/$_progresTotal',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.blueGrey[600],
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    icon: const Icon(Icons.close_rounded),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: media.size.height * 0.6),
                child: SingleChildScrollView(
                  child: _buildProgressBarChart(rows),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _barColor(double persen) {
    if (persen >= 0.8) return const Color(0xFF0F9D58);
    if (persen >= 0.5) return const Color(0xFF1F6FEB);
    if (persen >= 0.25) return const Color(0xFFD97706);
    return const Color(0xFF8B1D5E);
  }

  Widget _buildProgressBarChart(List<AnomaliProgressItem> rows) {
    const chartHeight = 200.0;
    const minSlot = 52.0;
    if (rows.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final fits = rows.length * minSlot <= maxW;
        final slot = fits ? maxW / rows.length : minSlot;
        final row = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: rows
              .map(
                (r) => SizedBox(
                  width: slot,
                  child: _buildBar(r, chartHeight, slot),
                ),
              )
              .toList(),
        );
        if (fits) return row;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: row,
        );
      },
    );
  }

  Widget _buildBar(
    AnomaliProgressItem item,
    double chartHeight,
    double slotWidth,
  ) {
    final color = _barColor(item.persen);
    final fill = (chartHeight * item.persen).clamp(
      item.sudah > 0 ? 3.0 : 0.0,
      chartHeight,
    );
    final barWidth = (slotWidth - 14).clamp(16.0, 64.0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${(item.persen * 100).round()}%',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: barWidth,
          height: chartHeight,
          decoration: BoxDecoration(
            color: const Color(0xFFEDF1F6),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.bottomCenter,
          child: Container(
            width: barWidth,
            height: fill,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${item.sudah}/${item.total}',
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Color(0xFF10243E),
          ),
        ),
        const SizedBox(height: 2),
        SizedBox(
          width: slotWidth - 4,
          child: Text(
            item.grupNama,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              height: 1.2,
              color: Colors.blueGrey[600],
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
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
                if (_pmlOptions.isNotEmpty) ...[
                  _buildPmlFilter(),
                  const SizedBox(width: 8),
                ],
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
                  onSelected: (v) =>
                      setState(() => _selectedKategoriRincian = v),
                ),
                if (_isAdmin) ...[
                  const SizedBox(width: 8),
                  _buildFilterDropdown(
                    icon: Icons.verified_user_outlined,
                    label: _selectedVerifikasi,
                    options: const [
                      _allVerifikasi,
                      _sudahVerifikasi,
                      _belumVerifikasi,
                    ],
                    onSelected: (v) => setState(() => _selectedVerifikasi = v),
                  ),
                ],
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
    final isDefault =
        label == _allSumber ||
        label == _allStatus ||
        label == _allKategoriBesar ||
        label == _allKategoriRincian ||
        label == _allVerifikasi;
    return PopupMenuButton<String>(
      onSelected: onSelected,
      itemBuilder: (context) => options
          .map((o) => PopupMenuItem(value: o, child: Text(_prettyOption(o))))
          .toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isDefault
              ? Colors.white
              : const Color(0xFF8B1D5E).withValues(alpha: 0.1),
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
              color: isDefault
                  ? const Color(0xFF526070)
                  : const Color(0xFF6B1245),
            ),
            const SizedBox(width: 6),
            Text(
              _prettyOption(label),
              style: TextStyle(
                fontSize: 13,
                fontWeight: isDefault ? FontWeight.w500 : FontWeight.w700,
                color: isDefault
                    ? const Color(0xFF526070)
                    : const Color(0xFF6B1245),
              ),
            ),
            const Icon(
              Icons.arrow_drop_down_rounded,
              size: 18,
              color: Color(0xFF526070),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPmlFilter() {
    final isDefault = _selectedPmlNames.isEmpty;
    final label = isDefault
        ? _allPml
        : (_selectedPmlNames.length == 1
              ? _selectedPmlNames.first
              : '${_selectedPmlNames.length} PML');
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: _showPmlFilterDialog,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isDefault
              ? Colors.white
              : const Color(0xFF8B1D5E).withValues(alpha: 0.1),
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
              Icons.supervisor_account_outlined,
              size: 16,
              color: isDefault
                  ? const Color(0xFF526070)
                  : const Color(0xFF6B1245),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isDefault ? FontWeight.w500 : FontWeight.w700,
                color: isDefault
                    ? const Color(0xFF526070)
                    : const Color(0xFF6B1245),
              ),
            ),
            const Icon(
              Icons.arrow_drop_down_rounded,
              size: 18,
              color: Color(0xFF526070),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showPmlFilterDialog() async {
    final media = MediaQuery.of(context);
    final temp = {..._selectedPmlNames};
    var query = '';

    final result = await showDialog<Set<String>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            final filtered = _pmlOptions
                .where(
                  (e) =>
                      query.isEmpty ||
                      e.grupNama.toLowerCase().contains(query.toLowerCase()),
                )
                .toList();
            return Dialog(
              backgroundColor: Colors.white,
              insetPadding: EdgeInsets.symmetric(
                horizontal: media.size.width * 0.05,
                vertical: 40,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 12, 4),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Filter Pengawas (PML)',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF10243E),
                            ),
                          ),
                        ),
                        Text(
                          '${temp.length} dipilih',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.blueGrey[600],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          icon: const Icon(Icons.close_rounded),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                    child: TextField(
                      autofocus: false,
                      onChanged: (v) => setLocal(() => query = v),
                      decoration: InputDecoration(
                        hintText: 'Cari nama PML...',
                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 10,
                        ),
                        filled: true,
                        fillColor: const Color(0xFFF3F6FB),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  Flexible(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: media.size.height * 0.5,
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final pml = filtered[index];
                          final checked = temp.contains(pml.grupNama);
                          return CheckboxListTile(
                            value: checked,
                            dense: true,
                            controlAffinity: ListTileControlAffinity.leading,
                            activeColor: const Color(0xFF8B1D5E),
                            title: Text(
                              pml.grupNama,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF10243E),
                              ),
                            ),
                            subtitle: Text(
                              '${pml.sudah}/${pml.total} diperiksa',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.blueGrey[500],
                              ),
                            ),
                            onChanged: (v) => setLocal(() {
                              if (v == true) {
                                temp.add(pml.grupNama);
                              } else {
                                temp.remove(pml.grupNama);
                              }
                            }),
                          );
                        },
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    child: Row(
                      children: [
                        TextButton(
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(<String>{}),
                          child: const Text('Bersihkan'),
                        ),
                        const Spacer(),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF8B1D5E),
                          ),
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(temp),
                          child: Text('Terapkan (${temp.length})'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (result != null) {
      setState(() {
        _selectedPmlNames
          ..clear()
          ..addAll(result);
      });
    }
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
          if (_isAdmin)
            OutlinedButton.icon(
              onPressed: _isExporting ? null : _exportExcel,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF1D8F5A),
                side: const BorderSide(color: Color(0xFF1D8F5A)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: _isExporting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.file_download_outlined, size: 18),
              label: Text(_isExporting ? 'Menyiapkan...' : 'Export'),
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
    // Mode compact untuk layar sempit (mobile): nama dapat baris penuh, chip
    // status pindah ke baris bawah agar tidak menjepit nama.
    final compact = MediaQuery.of(context).size.width < 600;
    // Di mobile chip status cukup ikon saja supaya ringkas.
    final statusChips = <Widget>[
      _buildStatusChip(item.statusEfektif, iconOnly: compact),
      if (item.adaKonfirmasi) _buildKonfirmasiBadge(iconOnly: compact),
      if (item.isVerified)
        _buildVerifiedBadge(iconOnly: compact)
      else if (item.isRejected)
        _buildRejectedBadge(iconOnly: compact),
    ];
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
            padding: EdgeInsets.all(compact ? 11 : 13),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: compact ? 30 : 38,
                  height: compact ? 30 : 38,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(compact ? 10 : 12),
                    gradient: LinearGradient(
                      colors: [accentColor, accentColor.withValues(alpha: 0.6)],
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: compact ? 12 : 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                SizedBox(width: compact ? 9 : 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Tanda kecil: kasus ini perlu saya tindaklanjuti.
                          if (item.perluTindakLanjut) ...[
                            Container(
                              margin: const EdgeInsets.only(top: 6, right: 6),
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Color(0xFFF59E0B),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                          Expanded(
                            child: Text(
                              item.subjekLabel,
                              style: TextStyle(
                                fontSize: compact ? 14 : 15,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF10243E),
                              ),
                            ),
                          ),
                          // Chip status di kanan atas, sebaris nama. Di mobile
                          // chip berupa ikon-saja jadi tidak menjepit nama.
                          for (final chip in statusChips) ...[
                            const SizedBox(width: 6),
                            chip,
                          ],
                        ],
                      ),
                      SizedBox(height: compact ? 5 : 4),
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
                      SizedBox(height: compact ? 8 : 9),
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
                if (item.linkFasih.isNotEmpty)
                  IconButton(
                    onPressed: () => _openFasih(item.linkFasih),
                    icon: const Icon(Icons.open_in_new_rounded),
                    iconSize: 20,
                    color: const Color(0xFF1F6FEB),
                    tooltip: 'Buka di Fasih',
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.only(left: 6, top: 2),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openFasih(String link) async {
    var url = link.trim();
    if (url.isEmpty) return;
    // Ubah rute assignment-detail -> assignment/{surveyId} agar mengarah ke
    // halaman edit assignment yang benar di Fasih.
    if (url.contains('/assignment-detail/')) {
      url = url.replaceFirst(
        '/assignment-detail/',
        '/assignment/$_fasihSurveyId/',
      );
    }
    url = url.replaceAll(RegExp(r'/+$'), '');
    if (!url.endsWith('/edit')) url = '$url/edit';
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tidak bisa membuka link Fasih')),
      );
    }
  }

  /// Chip label+ikon berwarna. [iconOnly] -> tampilkan ikon saja (mobile).
  Widget _buildChip({
    required IconData icon,
    required String label,
    required Color color,
    required Color bg,
    double iconSize = 13,
    bool iconOnly = false,
  }) {
    if (iconOnly) {
      return Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        child: Icon(icon, size: iconSize, color: color),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: iconSize, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKonfirmasiBadge({bool iconOnly = false}) {
    return _buildChip(
      icon: Icons.campaign_rounded,
      label: 'Konfirmasi',
      color: const Color(0xFFB45309),
      bg: const Color(0xFFF59E0B).withValues(alpha: 0.16),
      iconOnly: iconOnly,
    );
  }

  Widget _buildVerifiedBadge({bool iconOnly = false}) {
    return _buildChip(
      icon: Icons.verified_user_rounded,
      label: 'Terverifikasi',
      color: const Color(0xFF0F9D58),
      bg: const Color(0xFF0F9D58).withValues(alpha: 0.12),
      iconOnly: iconOnly,
    );
  }

  Widget _buildRejectedBadge({bool iconOnly = false}) {
    return _buildChip(
      icon: Icons.gpp_bad_rounded,
      label: 'Ditolak',
      color: const Color(0xFFD1435B),
      bg: const Color(0xFFD1435B).withValues(alpha: 0.12),
      iconOnly: iconOnly,
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
      case 'konfirmasi':
        return Icons.campaign_outlined;
      case 'dikonfirmasi_salah_entri':
      case 'perbaikan':
      case 'sudah_diperbaiki':
        return Icons.build_rounded;
      case 'belum_diperiksa':
      default:
        return Icons.pending_outlined;
    }
  }

  Widget _buildStatusChip(String status, {bool iconOnly = false}) {
    final color = _statusColor(status);
    return _buildChip(
      icon: _statusIcon(status),
      label: _prettyOption(status),
      color: color,
      bg: color.withValues(alpha: 0.12),
      iconSize: 12,
      iconOnly: iconOnly,
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
                  _selectedVerifikasi = _allVerifikasi;
                  _selectedPmlNames.clear();
                  _filterPerluTindak = false;
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
    final width = MediaQuery.of(context).size.width;
    // Di layar lebar (desktop/tablet) bottom sheet Material dibatasi ~640px
    // sehingga terlihat sempit; lebarkan ke 80%. Di mobile biarkan full width.
    final isWide = width >= 600;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: isWide
          ? BoxConstraints(maxWidth: width * 0.8)
          : null,
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
      case 'konfirmasi':
        return const Color(0xFFFB923C);
      case 'sudah_diperbaiki':
        return const Color(0xFF1F6FEB);
      case 'belum_diperiksa':
      default:
        return const Color(0xFF8B1D5E);
    }
  }

  String _prettyOption(String value) {
    if (value.isEmpty) return '-';
    if (value == 'perbaikan') return 'Salah Input';
    if (value == 'konfirmasi') return 'Konfirmasi';
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

  /// Keputusan admin saat ini: 'verified', 'rejected', atau null.
  String? _verifStatus;
  DateTime? _verifiedAt;
  String? _verifiedOleh;
  bool _savingVerif = false;

  bool get _verified => _verifStatus == 'verified';
  bool get _rejected => _verifStatus == 'rejected';

  @override
  void initState() {
    super.initState();
    _keteranganController = TextEditingController(
      text: widget.item.keterangan ?? '',
    );
    _jenisRespons = widget.item.jenisRespons;
    _verifStatus = widget.item.verifikasiStatus;
    _verifiedAt = widget.item.verifiedAt;
    _verifiedOleh = widget.item.verifiedOleh;
    _fetchThread();
  }

  /// Set keputusan admin. Menekan tombol status yang sedang aktif akan
  /// membatalkannya (target null).
  Future<void> _setVerifikasi(String status) async {
    final item = widget.item;
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final target = _verifStatus == status ? null : status;
    setState(() => _savingVerif = true);
    try {
      await widget.service.setVerifikasi(
        scope: item.kategoriBesar,
        assignmentId: item.assignmentId,
        namaSubjek: item.responsNamaSubjek,
        kategoriKode: item.kategoriKode,
        status: target,
      );
      if (!mounted) return;
      setState(() {
        _verifStatus = target;
        _verifiedAt = target != null ? DateTime.now() : null;
        _verifiedOleh = null;
        _savingVerif = false;
      });
      await widget.onSaved();
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(
            target == 'verified'
                ? 'Anomali diverifikasi'
                : target == 'rejected'
                    ? 'Anomali ditolak'
                    : 'Keputusan verifikasi dibatalkan',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _savingVerif = false);
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Gagal memperbarui verifikasi: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
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
        SnackBar(
          content: Text('Gagal menyimpan: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _salinRespons() {
    final item = widget.item;
    final buf = StringBuffer()
      ..writeln(item.subjekLabel)
      ..writeln(item.kategoriRincianLabel)
      ..writeln(item.wilayahLengkapLabel);
    if (item.deskripsi.isNotEmpty) {
      buf.writeln('Anomali: ${item.deskripsi}');
    }
    buf.writeln('---');
    if (_thread.isEmpty) {
      final k = _keteranganController.text.trim();
      buf.writeln(k.isEmpty ? 'Belum ada respons.' : k);
    } else {
      for (final k in _thread) {
        buf.writeln(
          '${k.namaPetugas} (${k.roleLabel}) - '
          '${_pretty(k.jenisRespons)}: '
          '${k.keterangan.isEmpty ? '-' : k.keterangan}',
        );
      }
    }

    Clipboard.setData(ClipboardData(text: buf.toString().trim()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Respons disalin ke clipboard')),
    );
  }

  void _salinKeterangan(String keterangan) {
    Clipboard.setData(ClipboardData(text: keterangan.trim()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Keterangan disalin ke clipboard')),
    );
  }

  Widget _buildResponsChoice(
      String value, String label, Color color, IconData icon) {
    final selected = _jenisRespons == value;
    return OutlinedButton.icon(
      onPressed: _isSaving ? null : () => setState(() => _jenisRespons = value),
      style: OutlinedButton.styleFrom(
        backgroundColor: selected ? color.withValues(alpha: 0.12) : null,
        foregroundColor: selected ? color : const Color(0xFF526070),
        side: BorderSide(
          color: selected ? color : Colors.grey.withValues(alpha: 0.4),
        ),
      ),
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }

  String _pretty(String value) {
    if (value.isEmpty) return '-';
    if (value == 'perbaikan') return 'Salah Input';
    if (value == 'konfirmasi') return 'Konfirmasi';
    return value
        .split('_')
        .map((w) {
          if (w.isEmpty) return w;
          return '${w[0].toUpperCase()}${w.substring(1)}';
        })
        .join(' ');
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
    // Di mobile sheet dibuat lebih penuh (tinggi) dan compact (padding rapat,
    // sudut lebih kecil). Di layar lebar tetap seperti semula.
    final isCompact = MediaQuery.of(context).size.width < 600;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DraggableScrollableSheet(
        initialChildSize: isCompact ? 0.95 : 0.88,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF7F9FC),
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(isCompact ? 20 : 28),
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
                  padding: isCompact
                      ? const EdgeInsets.fromLTRB(14, 14, 14, 20)
                      : const EdgeInsets.fromLTRB(18, 18, 18, 28),
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
                                style: TextStyle(
                                  fontSize: isCompact ? 18 : 22,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF10243E),
                                ),
                              ),
                              SizedBox(height: isCompact ? 6 : 8),
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
                          onPressed: _salinRespons,
                          icon: const Icon(Icons.copy_rounded),
                          tooltip: 'Salin respons',
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
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color:
                                (item.isWilayah
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
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF6F9FD),
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: Text(
                            // Cukup kode kategori (mis. "KP2"); penjelasan
                            // lengkap sudah ada di section "Keterangan Anomali".
                            item.kategoriKode.isEmpty
                                ? item.kategoriRincianLabel
                                : item.kategoriKode,
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
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF6F9FD),
                              borderRadius: BorderRadius.circular(30),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.person_outline,
                                  size: 14,
                                  color: Color(0xFF3D6B9D),
                                ),
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
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              // Admin (bolehVerifikasi) hanya boleh
                              // "Konfirmasi"; petugas lain memilih antara
                              // "Salah Input" / "Data Benar".
                              if (widget.item.bolehVerifikasi)
                                _buildResponsChoice(
                                  'konfirmasi',
                                  'Konfirmasi',
                                  const Color(0xFFFB923C),
                                  Icons.campaign_outlined,
                                )
                              else ...[
                                _buildResponsChoice(
                                  'perbaikan',
                                  'Salah Input',
                                  const Color(0xFFD97706),
                                  Icons.build_outlined,
                                ),
                                _buildResponsChoice(
                                  'konfirmasi_valid',
                                  'Data Benar',
                                  const Color(0xFF0F9D58),
                                  Icons.verified_outlined,
                                ),
                              ],
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
                              label: Text(
                                _isSaving ? 'Menyimpan...' : 'Simpan',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (widget.item.bolehVerifikasi &&
                        widget.item.sudahDitindaklanjuti) ...[
                      const SizedBox(height: 18),
                      _buildVerifikasiSection(),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVerifikasiSection() {
    const green = Color(0xFF0F9D58);
    const red = Color(0xFFD1435B);
    final accent = _verified
        ? green
        : _rejected
            ? red
            : const Color(0xFF6B7A8D);
    final active = _verified || _rejected;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: active ? accent.withValues(alpha: 0.08) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: active ? Border.all(color: accent.withValues(alpha: 0.4)) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _verified
                    ? Icons.verified_user_rounded
                    : _rejected
                        ? Icons.gpp_bad_rounded
                        : Icons.verified_user_outlined,
                size: 20,
                color: accent,
              ),
              const SizedBox(width: 8),
              const Text(
                'Verifikasi Admin',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF162F4D),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _verified
                ? 'Sudah diverifikasi'
                      '${_verifiedOleh != null ? ' oleh $_verifiedOleh' : ''}'
                      '${_verifiedAt != null ? ' · ${_formatDate(_verifiedAt!)}' : ''}'
                : _rejected
                    ? 'Ditolak admin'
                          '${_verifiedOleh != null ? ' oleh $_verifiedOleh' : ''}'
                          '${_verifiedAt != null ? ' · ${_formatDate(_verifiedAt!)}' : ''}'
                    : 'Belum ada keputusan. Setujui bila kasus valid, atau '
                          'tolak bila tidak sesuai.',
            style: TextStyle(fontSize: 12, color: Colors.blueGrey[600]),
          ),
          const SizedBox(height: 12),
          // Sudah ada keputusan -> cuma tombol Batalkan.
          // Belum ada keputusan -> pilih Verifikasi atau Tolak.
          if (active)
            SizedBox(
              width: double.infinity,
              child: _buildVerifButton(
                status: _verifStatus!,
                warna: accent,
                ikon: Icons.undo_rounded,
                label: 'Batalkan',
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: _buildVerifButton(
                    status: 'verified',
                    warna: green,
                    ikon: Icons.verified_rounded,
                    label: 'Verifikasi',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildVerifButton(
                    status: 'rejected',
                    warna: red,
                    ikon: Icons.gpp_bad_rounded,
                    label: 'Tolak',
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// Tombol keputusan verifikasi. Untuk "Batalkan", [status] adalah keputusan
  /// yang sedang aktif -- menekannya membatalkan (target jadi null).
  Widget _buildVerifButton({
    required String status,
    required Color warna,
    required IconData ikon,
    required String label,
  }) {
    final batalkan = label == 'Batalkan';
    return ElevatedButton.icon(
      onPressed: _savingVerif ? null : () => _setVerifikasi(status),
      style: ElevatedButton.styleFrom(
        backgroundColor: batalkan ? Colors.white : warna,
        foregroundColor: batalkan ? warna : Colors.white,
        side: batalkan ? BorderSide(color: warna) : null,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
      icon: _savingVerif
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(ikon, size: 18),
      label: Text(label),
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
              const SizedBox(width: 4),
              InkWell(
                onTap: k.keterangan.trim().isEmpty
                    ? null
                    : () => _salinKeterangan(k.keterangan),
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.copy_rounded,
                    size: 16,
                    color: k.keterangan.trim().isEmpty
                        ? Colors.blueGrey[200]
                        : const Color(0xFF1F6FEB),
                  ),
                ),
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
