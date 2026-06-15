import 'package:flutter/material.dart';

import '../../data/models/usaha_organik_item.dart';
import '../../data/services/usaha_organik_sheets_service.dart';

class UsahaOrganikPage extends StatefulWidget {
  const UsahaOrganikPage({super.key});

  @override
  State<UsahaOrganikPage> createState() => _UsahaOrganikPageState();
}

class _UsahaOrganikPageState extends State<UsahaOrganikPage> {
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

  final UsahaOrganikSheetsService _service = UsahaOrganikSheetsService();
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  String? _error;
  String? _statusMessage;
  DateTime? _lastUpdatedAt;
  String _query = '';
  List<UsahaOrganikItem> _entries = [];

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
          _statusMessage = 'Menampilkan data Usaha Organik dari cache lokal.';
        });
        return;
      }

      final entries = await _service.refreshEntries();
      if (!mounted) return;

      setState(() {
        _entries = entries;
        _isLoading = false;
        _lastUpdatedAt = DateTime.now();
        _statusMessage = 'Data Usaha Organik diperbarui dari Google Sheets.';
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
        _statusMessage = 'Data Usaha Organik diperbarui dari Google Sheets.';
      });
    } catch (e) {
      if (!mounted) return;

      if (hadEntries) {
        setState(() {
          _isLoading = false;
          _statusMessage =
              'Refresh gagal. Menampilkan data Usaha Organik terakhir dari cache lokal.';
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Refresh Usaha Organik gagal: $e'),
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

  List<UsahaOrganikItem> get _filteredEntries {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) {
      return _entries;
    }

    return _entries.where((item) {
      final haystack = [
        item.nama,
        item.alamat,
        item.keterangan,
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final entries = _filteredEntries;

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
                        child: _buildSectionHeader(resultCount: entries.length),
                      ),
                      if (entries.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: _buildEmptyState(),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                          sliver: SliverList.separated(
                            itemCount: entries.length,
                            itemBuilder: (context, index) =>
                                _buildUsahaTile(entries[index], index),
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
            child: const Icon(Icons.eco_rounded, color: Colors.white),
          ),
          const SizedBox(width: 18),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Usaha Organik',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Daftar usaha dari Google Sheets publik dengan pencarian dan cache lokal.',
                  style: TextStyle(
                    color: Colors.white,
                    height: 1.45,
                  ),
                ),
              ],
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
                hintText: 'Cari nama, alamat, atau keterangan',
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
          if (_lastUpdatedAt != null) ...[
            const SizedBox(height: 6),
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
                  'Daftar Usaha',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  '$resultCount usaha tampil',
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
            child: const Text(
              'Sumber: Sheet1',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Color(0xFF144A8B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUsahaTile(UsahaOrganikItem item, int index) {
    return Ink(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF2D77D0).withValues(alpha: 0.08)),
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
                  colors: [Color(0xFF12733E), Color(0xFF34A853)],
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
                    item.nama,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF10243E),
                    ),
                  ),
                  if (item.alamat.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _buildInfoRow(
                      icon: Icons.location_on_outlined,
                      text: item.alamat,
                    ),
                  ],
                  if (item.keterangan.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _buildInfoRow(
                      icon: Icons.sticky_note_2_outlined,
                      text: item.keterangan,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow({required IconData icon, required String text}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: const Color(0xFF2D77D0)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 14,
              color: Colors.blueGrey[700],
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    final isSearching = _query.trim().isNotEmpty;

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
            Text(
              isSearching ? 'Data tidak ditemukan' : 'Belum ada data usaha',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              isSearching
                  ? 'Coba ganti kata kunci pencarian Anda.'
                  : 'Tarik ke bawah atau tekan refresh untuk memuat data dari Google Sheets.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.blueGrey[600], height: 1.5),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () {
                _searchController.clear();
                setState(() {
                  _query = '';
                });
              },
              child: Text(isSearching ? 'Reset Pencarian' : 'Kosongkan Filter'),
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
              'Gagal memuat Usaha Organik',
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

  String _formatUpdatedAt(DateTime value) {
    final local = value.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = _monthNames[local.month - 1];
    final year = local.year;
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day $month $year $hour:$minute';
  }
}
