import 'package:flutter/material.dart';

import '../../data/models/nik_tidak_valid_item.dart';
import '../../data/services/nik_tidak_valid_service.dart';

class NikTidakValidPage extends StatefulWidget {
  const NikTidakValidPage({super.key});

  @override
  State<NikTidakValidPage> createState() => _NikTidakValidPageState();
}

class _NikTidakValidPageState extends State<NikTidakValidPage> {
  static const List<String> _bulan = [
    'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
    'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
  ];

  final NikTidakValidService _service = NikTidakValidService();
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  String? _error;
  String? _statusMessage;
  DateTime? _lastUpdatedAt;
  String _query = '';
  String _selectedKategori = _allKategori;
  List<NikTidakValidItem> _entries = [];

  static const String _allKategori = 'Semua';

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
      final cached = await _service.loadCachedEntries();
      final cachedAt = await _service.loadCacheUpdatedAt();
      if (!mounted) return;
      if (cached.isNotEmpty) {
        setState(() {
          _entries = cached;
          _isLoading = false;
          _lastUpdatedAt = cachedAt;
          _statusMessage = 'Cache lokal.';
        });
        return;
      }
      final entries = await _service.refreshEntries();
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _isLoading = false;
        _lastUpdatedAt = DateTime.now();
        _statusMessage = 'Data diperbarui dari server.';
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
      setState(() => _error = null);
    }
    try {
      final entries = await _service.refreshEntries();
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _isLoading = false;
        _lastUpdatedAt = DateTime.now();
        _statusMessage = 'Data diperbarui dari server.';
      });
    } catch (e) {
      if (!mounted) return;
      if (hadEntries) {
        setState(() {
          _isLoading = false;
          _statusMessage = 'Refresh gagal. Menampilkan cache terakhir.';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Refresh gagal: $e'),
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

  List<String> get _kategoriList {
    final set = <String>{};
    for (final item in _entries) {
      set.add(item.kategori);
    }
    final list = set.toList()..sort();
    return [_allKategori, ...list];
  }

  List<NikTidakValidItem> get _filteredEntries {
    final query = _query.trim().toLowerCase();
    return _entries.where((item) {
      if (_selectedKategori != _allKategori &&
          item.kategori != _selectedKategori) {
        return false;
      }
      if (query.isEmpty) return true;
      return [
        item.namaKk,
        item.namaDtsen,
        item.nikDtsen ?? '',
        item.nmKec,
        item.nmDesa,
        item.nmSls,
        item.namaPpl ?? '',
        item.status,
      ].join(' ').toLowerCase().contains(query);
    }).toList();
  }

  void _openAnggotaSheet(NikTidakValidItem item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AnggotaSheet(item: item, service: _service),
    );
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
                          SliverToBoxAdapter(child: _buildHero()),
                          SliverToBoxAdapter(child: _buildSearch()),
                          SliverToBoxAdapter(child: _buildFilter()),
                          SliverToBoxAdapter(child: _buildHeader(entries.length)),
                          if (entries.isEmpty)
                            SliverFillRemaining(
                              hasScrollBody: false,
                              child: _buildEmpty(),
                            )
                          else
                            SliverPadding(
                              padding:
                                  const EdgeInsets.fromLTRB(12, 0, 12, 100),
                              sliver: SliverList.separated(
                                itemCount: entries.length,
                                itemBuilder: (_, i) =>
                                    _buildCard(entries[i]),
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 10),
                              ),
                            ),
                        ],
                      ),
                    ),
        ),
      ),
    );
  }

  Widget _buildHero() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFF7B1B1B), Color(0xFFB83232), Color(0xFFE57373)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFB83232).withValues(alpha: 0.25),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.fingerprint, color: Colors.white, size: 32),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'NIK Tidak Valid',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                Text(
                  '${_entries.length} anggota · NIK di luar format 16 digit',
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 12, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearch() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Cari nama, NIK, wilayah, petugas...',
                hintStyle: TextStyle(fontSize: 13, color: Colors.blueGrey[400]),
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _query.isEmpty
                    ? IconButton(
                        onPressed: _refreshData,
                        icon: const Icon(Icons.refresh_rounded, size: 20),
                      )
                    : IconButton(
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                        icon: const Icon(Icons.close_rounded, size: 20),
                      ),
                border: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
          ),
          if (_statusMessage != null || _lastUpdatedAt != null) ...[
            const SizedBox(height: 6),
            Text(
              [
                if (_statusMessage != null) _statusMessage!,
                if (_lastUpdatedAt != null)
                  'Update: ${_fmtDate(_lastUpdatedAt!)}',
              ].join('  ·  '),
              style: TextStyle(fontSize: 11, color: Colors.blueGrey[500]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFilter() {
    final items = _kategoriList;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Row(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Builder(builder: (context) {
              final label = items[i];
              final sel = label == _selectedKategori;
              return FilterChip(
                label: Text(label, style: const TextStyle(fontSize: 12)),
                selected: sel,
                onSelected: (_) => setState(() => _selectedKategori = label),
                selectedColor: const Color(0xFFB83232).withValues(alpha: 0.12),
                checkmarkColor: const Color(0xFFB83232),
                labelStyle: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: sel ? const Color(0xFFB83232) : Colors.blueGrey[700],
                ),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader(int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
      child: Text(
        '$count record tampil',
        style: TextStyle(
          fontSize: 12,
          color: Colors.blueGrey[600],
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  // ── Card ──────────────────────────────────────────────────────────────────

  Widget _buildCard(NikTidakValidItem item) {
    final lokasi = _lokasiText(item);
    return Ink(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFB83232).withValues(alpha: 0.10),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openAnggotaSheet(item),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Nama + No. urut
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      item.namaDtsen.isNotEmpty
                          ? item.namaDtsen
                          : '(Tanpa Nama)',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF10243E),
                      ),
                    ),
                  ),
                  Text(
                    'No. ${item.noUrut}',
                    style: TextStyle(fontSize: 11, color: Colors.blueGrey[500]),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // NIK + badge
              Row(
                children: [
                  const Icon(Icons.fingerprint,
                      size: 14, color: Color(0xFFB83232)),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      item.nikDtsen ?? 'NULL',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blueGrey[700],
                        fontFamily: 'monospace',
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  _kategoriBadge(item.kategori),
                ],
              ),
              const SizedBox(height: 8),
              // KK
              if (item.namaKk.isNotEmpty) ...[
                _infoRow(Icons.home_outlined, item.namaKk),
                const SizedBox(height: 3),
              ],
              // Lokasi (satu baris)
              if (lokasi.isNotEmpty) ...[
                _infoRow(Icons.location_on_outlined, lokasi, maxLines: 2),
                const SizedBox(height: 3),
              ],
              // PPL + status
              Row(
                children: [
                  Expanded(
                    child: _infoRow(
                      Icons.person_outline_rounded,
                      item.namaPpl?.isNotEmpty == true
                          ? item.namaPpl!
                          : '-',
                    ),
                  ),
                  if (item.status.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    _statusChip(item.status),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _lokasiText(NikTidakValidItem item) {
    final parts = <String>[];
    if (item.nmKec.isNotEmpty) parts.add('Kec. ${item.nmKec}');
    if (item.nmDesa.isNotEmpty) parts.add(item.nmDesa);
    if (item.nmSls.isNotEmpty) parts.add(item.nmSls);
    if (item.kodeSubsls?.isNotEmpty == true) parts.add('(${item.kodeSubsls})');
    return parts.join(' / ');
  }

  Widget _infoRow(IconData icon, String text, {int maxLines = 1}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 13, color: Colors.blueGrey[400]),
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            text,
            style: TextStyle(fontSize: 12, color: Colors.blueGrey[700]),
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _kategoriBadge(String kategori) {
    final color = _kategoriColor(kategori);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Text(
        kategori,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }

  Color _kategoriColor(String k) {
    if (k == 'NULL') return const Color(0xFFC62828);
    if (k.startsWith('9999')) return const Color(0xFFE65100);
    if (k.startsWith('8888')) return const Color(0xFFF57F17);
    if (k.startsWith('7777')) return const Color(0xFF546E7A);
    if (k.startsWith('Angka')) return const Color(0xFF1565C0);
    return const Color(0xFF6A1B9A);
  }

  Widget _statusChip(String status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF0F4C81).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: Color(0xFF0F4C81),
        ),
      ),
    );
  }

  // ── Empty / Error ─────────────────────────────────────────────────────────

  Widget _buildEmpty() {
    final isFiltering =
        _query.trim().isNotEmpty || _selectedKategori != _allKategori;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.manage_search_rounded,
                size: 48, color: Color(0xFFB83232)),
            const SizedBox(height: 16),
            Text(
              isFiltering ? 'Data tidak ditemukan' : 'Tidak ada NIK tidak valid',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              isFiltering
                  ? 'Coba ubah kata kunci atau filter.'
                  : 'Semua NIK sudah valid.',
              style: TextStyle(color: Colors.blueGrey[600], fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: () {
                _searchController.clear();
                setState(() {
                  _query = '';
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
            const Icon(Icons.cloud_off_rounded, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            const Text(
              'Gagal memuat NIK Tidak Valid',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? 'Terjadi kesalahan',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.blueGrey[600], fontSize: 13),
            ),
            const SizedBox(height: 14),
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

  String _fmtDate(DateTime v) {
    final l = v.toLocal();
    final d = l.day.toString().padLeft(2, '0');
    final m = _bulan[l.month - 1];
    final h = l.hour.toString().padLeft(2, '0');
    final min = l.minute.toString().padLeft(2, '0');
    return '$d $m ${l.year} $h:$min';
  }
}

// ─── Bottom Sheet: Anggota KK ─────────────────────────────────────────────────

class _AnggotaSheet extends StatefulWidget {
  final NikTidakValidItem item;
  final NikTidakValidService service;
  const _AnggotaSheet({required this.item, required this.service});

  @override
  State<_AnggotaSheet> createState() => _AnggotaSheetState();
}

class _AnggotaSheetState extends State<_AnggotaSheet> {
  List<AnggotaItem>? _anggota;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await widget.service.fetchAnggota(widget.item.assignmentId);
      if (mounted) setState(() => _anggota = data);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      minChildSize: 0.35,
      expand: false,
      builder: (context, ctrl) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 6),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.blueGrey[200],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                child: Row(
                  children: [
                    const Icon(Icons.people_rounded,
                        color: Color(0xFFB83232), size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Anggota Keluarga',
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w800),
                          ),
                          if (widget.item.namaKk.isNotEmpty)
                            Text(
                              widget.item.namaKk,
                              style: TextStyle(
                                  fontSize: 12, color: Colors.blueGrey[600]),
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // List
              Expanded(
                child: _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Gagal memuat: $_error',
                            style: const TextStyle(
                                color: Colors.red, fontSize: 13),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : _anggota == null
                        ? const Center(child: CircularProgressIndicator())
                        : _anggota!.isEmpty
                            ? Center(
                                child: Text(
                                  'Tidak ada data anggota.',
                                  style: TextStyle(color: Colors.blueGrey[600]),
                                ),
                              )
                            : ListView.separated(
                                controller: ctrl,
                                padding:
                                    const EdgeInsets.fromLTRB(12, 10, 12, 40),
                                itemCount: _anggota!.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (ctx, i) =>
                                    _buildRow(ctx, _anggota![i]),
                              ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRow(BuildContext context, AnggotaItem a) {
    final invalid = !a.isNikValid;
    return InkWell(
      onTap: () => showDialog(
        context: context,
        builder: (_) => _DetailDialog(anggota: a),
      ),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: invalid
              ? const Color(0xFFB83232).withValues(alpha: 0.04)
              : const Color(0xFFF3F6FB),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: invalid
                ? const Color(0xFFB83232).withValues(alpha: 0.20)
                : Colors.grey.withValues(alpha: 0.12),
          ),
        ),
        child: Row(
          children: [
            // No urut
            SizedBox(
              width: 28,
              child: Text(
                '${a.noUrut}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: invalid
                      ? const Color(0xFFB83232)
                      : Colors.blueGrey[600],
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          a.namaDtsen.isNotEmpty ? a.namaDtsen : '(Tanpa Nama)',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (a.jkDtsen?.isNotEmpty == true) ...[
                        const SizedBox(width: 6),
                        Text(
                          a.jkDtsen!,
                          style: TextStyle(
                              fontSize: 11, color: Colors.blueGrey[500]),
                        ),
                      ],
                      if (a.umurAk != null)
                        Text(
                          '  ${a.umurAk} th',
                          style: TextStyle(
                              fontSize: 11, color: Colors.blueGrey[500]),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    a.nikDtsen ?? 'NULL',
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: invalid
                          ? const Color(0xFFB83232)
                          : Colors.blueGrey[500],
                      fontWeight:
                          invalid ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
            if (a.hubungan?.isNotEmpty == true) ...[
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blueGrey[50],
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  a.hubungan!,
                  style: TextStyle(fontSize: 10, color: Colors.blueGrey[600]),
                ),
              ),
            ],
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded,
                size: 16, color: Colors.blueGrey[300]),
          ],
        ),
      ),
    );
  }
}

// ─── Detail Dialog ────────────────────────────────────────────────────────────

class _DetailDialog extends StatelessWidget {
  final AnggotaItem anggota;

  static const List<String> _bln = [
    'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
    'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
  ];

  const _DetailDialog({required this.anggota});

  String get _tglLahir {
    final parts = <String>[];
    if (anggota.tglLahir?.isNotEmpty == true) parts.add(anggota.tglLahir!);
    final bln = anggota.blnLahir;
    if (bln != null && bln >= 1 && bln <= 12) parts.add(_bln[bln - 1]);
    if (anggota.thnLahir != null) parts.add('${anggota.thnLahir}');
    return parts.isEmpty ? '-' : parts.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final invalid = !anggota.isNikValid;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      titlePadding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
      contentPadding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
      title: Text(
        anggota.namaDtsen.isNotEmpty ? anggota.namaDtsen : '(Tanpa Nama)',
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _row('NIK', anggota.nikDtsen ?? 'NULL',
                color: invalid ? const Color(0xFFB83232) : null,
                mono: true,
                badge: invalid ? 'Tidak Valid' : null,
                badgeColor: const Color(0xFFB83232)),
            _row('Hubungan', anggota.hubungan ?? '-'),
            _row('Jenis Kelamin', anggota.jkDtsen ?? '-'),
            _row('Tgl. Lahir', _tglLahir),
            if (anggota.umurAk != null)
              _row('Umur', '${anggota.umurAk} tahun'),
            _row('Status Kawin', anggota.statusKawin ?? '-'),
            _row('Keberadaan', anggota.keberadaanDtsen ?? '-'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Tutup'),
        ),
      ],
    );
  }

  Widget _row(
    String label,
    String value, {
    Color? color,
    bool mono = false,
    String? badge,
    Color? badgeColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: TextStyle(
                  fontSize: 12,
                  color: Colors.blueGrey[500],
                  fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 12,
                      color: color ?? Colors.blueGrey[800],
                      fontFamily: mono ? 'monospace' : null,
                      fontWeight: color != null ? FontWeight.w600 : null,
                    ),
                  ),
                ),
                if (badge != null && badgeColor != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: badgeColor.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      badge,
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: badgeColor),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
