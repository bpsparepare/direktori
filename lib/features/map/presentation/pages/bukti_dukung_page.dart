import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/services/bukti_dukung_service.dart';

class BuktiDukungPage extends StatefulWidget {
  const BuktiDukungPage({super.key});

  @override
  State<BuktiDukungPage> createState() => _BuktiDukungPageState();
}

class _BuktiDukungPageState extends State<BuktiDukungPage> {
  final BuktiDukungService _service = BuktiDukungService();
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  String? _error;
  String _query = '';
  // Filter "belum ada" per kategori: 't1', 't2', 'pd'.
  final Set<String> _missingFilters = {};
  List<BuktiDukungRow> _rows = [];

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
      final rows = await _service.fetchRows();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  bool _isMissing(BuktiDukungRow r, String key) {
    switch (key) {
      case 't1':
        return r.termin1 == null;
      case 't2':
        return r.termin2 == null;
      case 'pd':
        return r.paketData == null;
    }
    return false;
  }

  bool _matchesSearch(BuktiDukungRow r) {
    final q = _query.trim().toLowerCase();
    return q.isEmpty || r.nama.toLowerCase().contains(q);
  }

  List<BuktiDukungRow> get _filtered {
    return _rows.where((r) {
      if (!_matchesSearch(r)) return false;
      if (_missingFilters.isEmpty) return true;
      // Tampil jika belum ada bukti pada salah satu kategori yang dipilih.
      return _missingFilters.any((key) => _isMissing(r, key));
    }).toList();
  }

  int _missingCount(String key) =>
      _rows.where((r) => _matchesSearch(r) && _isMissing(r, key)).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FB),
      appBar: AppBar(
        title: const Text('Bukti Dukung'),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _loadData,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _buildError()
          : Column(
              children: [
                _buildSearch(),
                _buildFilterBar(),
                _buildHeaderRow(),
                Expanded(child: _buildList()),
              ],
            ),
    );
  }

  Widget _buildSearch() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
      child: TextField(
        controller: _searchController,
        onChanged: (v) => setState(() => _query = v),
        decoration: InputDecoration(
          hintText: 'Cari nama petugas',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _query = '');
                  },
                  icon: const Icon(Icons.close_rounded),
                ),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 4),
        ),
      ),
    );
  }

  Widget _buildFilterBar() {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Center(
              child: Text(
                'Belum ada:',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.blueGrey[500],
                ),
              ),
            ),
          ),
          _filterChip('t1', 'Termin 1'),
          _filterChip('t2', 'Termin 2'),
          _filterChip('pd', 'Paket Data'),
        ],
      ),
    );
  }

  Widget _filterChip(String key, String label) {
    final selected = _missingFilters.contains(key);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        selected: selected,
        onSelected: (v) => setState(() {
          if (v) {
            _missingFilters.add(key);
          } else {
            _missingFilters.remove(key);
          }
        }),
        label: Text('$label (${_missingCount(key)})'),
        labelStyle: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: selected ? Colors.white : const Color(0xFF23374D),
        ),
        selectedColor: const Color(0xFF2D77D0),
        backgroundColor: Colors.white,
        showCheckmark: false,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFFDCE3EC)),
        ),
      ),
    );
  }

  Widget _buildHeaderRow() {
    const style = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w800,
      color: Color(0xFF10243E),
    );
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 6, 14, 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFE9F0FA),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 26,
            child: Text('No',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF10243E))),
          ),
          const Expanded(flex: 3, child: Text('Petugas', style: style)),
          _headerCell('Termin 1', 's/d Juli'),
          _headerCell('Termin 2', 'Mulai Agst'),
          _headerCell('Paket', 'Terakhir'),
        ],
      ),
    );
  }

  Widget _headerCell(String title, String sub) {
    return Expanded(
      flex: 2,
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Color(0xFF10243E),
              ),
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              sub,
              style: const TextStyle(fontSize: 9.5, color: Color(0xFF8593A5)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    final rows = _filtered;
    if (rows.isEmpty) return _buildEmpty();
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
        itemCount: rows.length,
        itemBuilder: (context, index) => _buildDataRow(rows[index], index),
      ),
    );
  }

  Widget _buildDataRow(BuktiDukungRow row, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEDF1F6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 26,
            child: Text(
              '${index + 1}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF6B7B8F),
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.nama,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF10243E),
                    ),
                  ),
                  if (row.role.isNotEmpty)
                    Text(
                      row.role,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: Color(0xFF8593A5),
                      ),
                    ),
                ],
              ),
            ),
          ),
          _buildCell(row.termin1, 'Termin 1'),
          _buildCell(row.termin2, 'Termin 2'),
          _buildCell(row.paketData, 'Paket Data'),
        ],
      ),
    );
  }

  Widget _buildCell(BuktiDukungCell? cell, String title) {
    final hasEvidence = cell != null && cell.isNotEmpty;
    return Expanded(
      flex: 2,
      child: Center(
        child: hasEvidence
            ? InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => _showEvidence(title, cell),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF7EF),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFF1D8F5A).withValues(alpha: 0.25),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.check_circle_rounded,
                        size: 18,
                        color: Color(0xFF1D8F5A),
                      ),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          _formatDate(cell.createdAt),
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1D8F5A),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : const Icon(
                Icons.remove_rounded,
                size: 18,
                color: Color(0xFFC2CBD6),
              ),
      ),
    );
  }

  void _showEvidence(String title, BuktiDukungCell cell) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final size = MediaQuery.of(dialogContext).size;
        final maxWidth = size.width > 720 ? 680.0 : size.width - 24;
        final imageUrl = cell.imageUrl;

        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxWidth,
              maxHeight: size.height * 0.82,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 18, 10, 16),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF143A70), Color(0xFF2D77D0)],
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Diupload ${_formatDateTime(cell.createdAt)}',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.88),
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
                Flexible(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    shrinkWrap: true,
                    children: [
                      if (imageUrl.isNotEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            loadingBuilder: (context, child, progress) {
                              if (progress == null) return child;
                              return const SizedBox(
                                height: 220,
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            },
                            errorBuilder: (context, error, stackTrace) =>
                                _imageFallback(),
                          ),
                        )
                      else
                        _imageFallback(),
                      const SizedBox(height: 12),
                      if (cell.namaFile.isNotEmpty)
                        Text(
                          cell.namaFile,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF31465D),
                          ),
                        ),
                      const SizedBox(height: 12),
                      if (cell.linkFile.isNotEmpty)
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () => _openUrl(cell.linkFile),
                            icon: const Icon(Icons.open_in_new),
                            label: const Text('Buka di Drive'),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _imageFallback() {
    return Container(
      height: 180,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5FB),
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.image_not_supported_outlined,
              size: 40, color: Color(0xFF9AA6B6)),
          SizedBox(height: 8),
          Text(
            'Pratinjau tidak tersedia.\nBuka di Drive untuk melihat.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF6B7B8F)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: const [
        SizedBox(height: 120),
        Icon(Icons.inbox_rounded, size: 52, color: Color(0xFF9AA6B6)),
        SizedBox(height: 12),
        Center(
          child: Text(
            'Tidak ada petugas untuk ditampilkan',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF4A5A6D),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 52, color: Colors.red),
            const SizedBox(height: 14),
            const Text(
              'Gagal memuat data',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? 'Terjadi kesalahan',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.blueGrey[600]),
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

  Future<void> _openUrl(String value) async {
    final uri = Uri.tryParse(value);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String _formatDate(String isoValue) {
    final dt = DateTime.tryParse(isoValue)?.toLocal();
    if (dt == null) return '-';
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    return '$d/$m/${dt.year}';
  }

  String _formatDateTime(String isoValue) {
    final dt = DateTime.tryParse(isoValue)?.toLocal();
    if (dt == null) return isoValue;
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$d-$m-${dt.year} $h:$min';
  }
}
