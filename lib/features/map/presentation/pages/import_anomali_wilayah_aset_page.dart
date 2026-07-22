import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models/keluarga_aset_item.dart';
import '../../data/services/anomali_wilayah_service.dart';
import '../../data/services/aset_thresholds.dart';
import 'aset_threshold_settings_page.dart';

/// Impor anomali wilayah - Kepemilikan Aset Tidak Wajar (UW5).
class ImportAnomaliWilayahAsetPage extends StatefulWidget {
  const ImportAnomaliWilayahAsetPage({super.key});

  @override
  State<ImportAnomaliWilayahAsetPage> createState() =>
      _ImportAnomaliWilayahAsetPageState();
}

class _ImportAnomaliWilayahAsetPageState
    extends State<ImportAnomaliWilayahAsetPage> {
  final AnomaliWilayahService _service = AnomaliWilayahService();
  final TextEditingController _searchController = TextEditingController();

  static const Color _accent = Color(0xFF9A3412);
  static const Color _warn = Color(0xFFDC2626);
  static const String _allPtg = 'Semua petugas';
  static const int _pageSize = 200;
  static const String _fasihSurveyId = 'fd68e454-ba45-4b85-8205-f3bf777ded24';

  Future<void> _openFasih(String assignmentId) async {
    if (assignmentId.isEmpty) return;
    final uri = Uri.tryParse(
        'https://fasih-sm.bps.go.id/app/assignment/$_fasihSurveyId/$assignmentId/edit');
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tidak bisa membuka Fasih')),
      );
    }
  }

  bool _isLoading = false;
  String? _error;
  List<KeluargaAsetItem> _items = [];
  bool _hasSearched = false;
  int _page = 0;
  bool _hasNext = false;

  static const String _allAset = 'Semua aset';

  List<String> _ptgOpts = [];
  String _petugasFilter = _allPtg;
  String _asetFilter = _allAset; // key aset atau _allAset
  bool _hanyaAnomali = false;
  Map<String, int> _thresholds = {};
  int _sortColumnIndex = 1;
  bool _sortAscending = true;

  final Set<String> _selected = {};
  bool _batchMode = false;

  void _onSort(int col, bool asc) => setState(() {
        _sortColumnIndex = col;
        _sortAscending = asc;
      });

  String _sortKey(KeluargaAsetItem it, int col) {
    switch (col) {
      case 1:
        return (it.namaKk.isEmpty ? it.assignmentId : it.namaKk).toLowerCase();
      case 2:
        return it.namaPetugas.toLowerCase();
      case 3:
        return it.wilayahLabel.toLowerCase();
      default:
        const start = 5; // kolom aset mulai indeks 5
        final n = KeluargaAsetItem.asetKeys.length;
        if (col >= start && col < start + n) {
          final k = KeluargaAsetItem.asetKeys[col - start];
          return (it.nilai[k] ?? 0).toString().padLeft(8, '0');
        }
        if (col == start + n) return it.statusText.toLowerCase(); // Status
        return '';
    }
  }

  List<KeluargaAsetItem> get _viewItems {
    final list = [..._items];
    list.sort((a, b) =>
        _sortKey(a, _sortColumnIndex).compareTo(_sortKey(b, _sortColumnIndex)));
    return _sortAscending ? list : list.reversed.toList();
  }

  @override
  void initState() {
    super.initState();
    _loadOptions();
    _loadThresholds();
  }

  Future<void> _loadThresholds() async {
    final t = await AsetThresholds.load();
    if (!mounted) return;
    setState(() => _thresholds = t);
  }

  Future<void> _openSettings() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AsetThresholdSettingsPage()),
    );
    if (changed == true) {
      await _loadThresholds();
      if (_hasSearched) await _loadPage(_page);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    try {
      final opts = await _service.fetchAsetPetugasOptions();
      if (!mounted) return;
      setState(() => _ptgOpts = opts);
    } catch (_) {}
  }

  Future<void> _cari() => _loadPage(0);

  Future<void> _loadPage(int page) async {
    setState(() {
      _isLoading = true;
      _error = null;
      _hasSearched = true;
    });
    try {
      final items = await _service.fetchKeluargaAset(
        query: _searchController.text.trim().isEmpty
            ? null
            : _searchController.text.trim(),
        petugas: _petugasFilter == _allPtg ? null : _petugasFilter,
        hanyaAnomali: _hanyaAnomali,
        aset: _asetFilter == _allAset ? null : _asetFilter,
        thresholds: _thresholds,
        limit: _pageSize,
        offset: page * _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _items = items;
        _page = page;
        _hasNext = items.length == _pageSize;
        _selected.clear();
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

  Future<void> _tandai(KeluargaAsetItem item) async {
    final controller = TextEditingController(text: item.komentarAdmin);
    final komentar = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Tandai Anomali Aset'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.namaKk.isEmpty ? item.assignmentId : item.namaKk,
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text('Petugas: ${item.namaPetugas}',
                  style: const TextStyle(fontSize: 13)),
              Text('Wilayah: ${item.wilayahLabel}',
                  style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 8),
              const Text('Aset melewati ambang:',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              if (item.lewat.isEmpty)
                const Text('—')
              else
                ...item.lewat.map((k) => Text(
                    '• ${KeluargaAsetItem.asetLabel[k] ?? k}: ${item.nilai[k]}',
                    style: const TextStyle(fontSize: 13, color: _warn))),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                maxLines: 3,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Catatan (wajib)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _accent),
            onPressed: () {
              final v = controller.text.trim();
              if (v.isEmpty) return;
              Navigator.of(dialogContext).pop(v);
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );

    if (komentar == null || komentar.isEmpty || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _service.insertAnomaliAset(
        assignmentId: item.assignmentId,
        komentar: komentar,
        thresholds: _thresholds,
      );
      if (!mounted) return;
      messenger
          .showSnackBar(const SnackBar(content: Text('Anomali aset ditandai.')));
      await _loadPage(_page);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
          content: Text('Gagal: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _tandaiBatch() async {
    final chosen = _items.where((e) => _selected.contains(e.key)).toList();
    if (chosen.isEmpty) return;
    final controller = TextEditingController();
    final komentar = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Tandai ${chosen.length} keluarga'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Catatan sama untuk semua terpilih.',
                style: TextStyle(fontSize: 12, color: Colors.blueGrey[600])),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 3,
              autofocus: true,
              decoration: const InputDecoration(
                  labelText: 'Catatan (wajib)', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _accent),
            onPressed: () {
              final v = controller.text.trim();
              if (v.isEmpty) return;
              Navigator.of(dialogContext).pop(v);
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );

    if (komentar == null || komentar.isEmpty || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final n = await _service.insertAnomaliAsetBatch(
        items: chosen.map((e) => {'assignment_id': e.assignmentId}).toList(),
        komentar: komentar,
        thresholds: _thresholds,
      );
      if (!mounted) return;
      messenger.showSnackBar(
          SnackBar(content: Text('$n keluarga ditandai anomali.')));
      await _loadPage(_page);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
          content: Text('Gagal: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FB),
      appBar: AppBar(
        title: const Text('Anomali Aset'),
        backgroundColor: _accent,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Atur ambang',
            icon: const Icon(Icons.tune_rounded),
            onPressed: _openSettings,
          ),
        ],
      ),
      floatingActionButton: _buildFab(),
      body: SafeArea(
        child: Column(
          children: [
            _buildControls(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget? _buildFab() {
    if (!_hasSearched) return null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 56),
      child: _buildFabInner(),
    );
  }

  Widget _buildFabInner() {
    if (!_batchMode) {
      return FloatingActionButton.extended(
        backgroundColor: _accent,
        foregroundColor: Colors.white,
        onPressed: () => setState(() {
          _batchMode = true;
          _selected.clear();
        }),
        icon: const Icon(Icons.checklist_rtl_rounded),
        label: const Text('Mode Tandai Batch'),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_selected.isNotEmpty) ...[
          FloatingActionButton.extended(
            heroTag: 'aset-tandai',
            backgroundColor: _accent,
            foregroundColor: Colors.white,
            onPressed: _tandaiBatch,
            icon: const Icon(Icons.playlist_add_check_rounded),
            label: Text('Tandai (${_selected.length})'),
          ),
          const SizedBox(height: 10),
        ],
        FloatingActionButton.extended(
          heroTag: 'aset-keluar',
          backgroundColor: Colors.blueGrey[700],
          foregroundColor: Colors.white,
          onPressed: () => setState(() {
            _batchMode = false;
            _selected.clear();
          }),
          icon: const Icon(Icons.close_rounded),
          label: const Text('Keluar Mode'),
        ),
      ],
    );
  }

  Widget _buildControls() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onSubmitted: (_) => _cari(),
                  decoration: const InputDecoration(
                    hintText: 'Cari nama KK...',
                    prefixIcon: Icon(Icons.search_rounded),
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: _isLoading ? null : _cari,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                ),
                child: const Text('Cari'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey('ptg-$_petugasFilter'),
                  initialValue: _petugasFilter,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Petugas',
                    isDense: true,
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: [_allPtg, ..._ptgOpts]
                      .map((o) => DropdownMenuItem(
                          value: o,
                          child: Text(o, overflow: TextOverflow.ellipsis)))
                      .toList(),
                  onChanged: (v) {
                    setState(() => _petugasFilter = v ?? _allPtg);
                    _loadPage(0);
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey('aset-$_asetFilter'),
                  initialValue: _asetFilter,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Filter aset',
                    isDense: true,
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: [_allAset, ...KeluargaAsetItem.asetKeys]
                      .map((o) => DropdownMenuItem(
                            value: o,
                            child: Text(
                                o == _allAset
                                    ? _allAset
                                    : (KeluargaAsetItem.asetLabel[o] ?? o),
                                overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (v) {
                    setState(() => _asetFilter = v ?? _allAset);
                    _loadPage(0);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FilterChip(
              selected: _hanyaAnomali,
              label: const Text('Hanya anomali'),
              selectedColor: _warn.withValues(alpha: 0.16),
              checkmarkColor: _warn,
              onSelected: (v) {
                setState(() => _hanyaAnomali = v);
                _loadPage(0);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, style: const TextStyle(color: Colors.red)),
        ),
      );
    }
    if (!_hasSearched) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Tekan Cari untuk menampilkan aset keluarga. Nilai yang melewati '
            'ambang wajar disorot merah.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.blueGrey[600], height: 1.5),
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Text('Tidak ada data.',
            style: TextStyle(color: Colors.blueGrey[600])),
      );
    }
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: _buildTable(_viewItems),
              ),
            ),
          ),
        ),
        _buildPagination(),
      ],
    );
  }

  Widget _buildTable(List<KeluargaAsetItem> rows) {
    return DataTable(
      showCheckboxColumn: _batchMode,
      sortColumnIndex: _sortColumnIndex,
      sortAscending: _sortAscending,
      dataRowMinHeight: 44,
      dataRowMaxHeight: 60,
      headingRowColor:
          WidgetStatePropertyAll(_accent.withValues(alpha: 0.08)),
      columnSpacing: 16,
      columns: [
        const DataColumn(label: Text('No')),
        DataColumn(label: const Text('Nama KK'), onSort: _onSort),
        DataColumn(label: const Text('Petugas'), onSort: _onSort),
        DataColumn(label: const Text('Wilayah'), onSort: _onSort),
        const DataColumn(label: Text('Fasih')),
        for (final k in KeluargaAsetItem.asetKeys)
          DataColumn(
            label: Text(KeluargaAsetItem.asetLabel[k] ?? k),
            numeric: true,
            onSort: _onSort,
          ),
        DataColumn(label: const Text('Status'), onSort: _onSort),
        const DataColumn(label: Text('Aksi')),
      ],
      rows: [for (var i = 0; i < rows.length; i++) _row(rows[i], i)],
    );
  }

  DataRow _row(KeluargaAsetItem it, int index) {
    return DataRow(
      selected: _batchMode && _selected.contains(it.key),
      onSelectChanged: (v) {
        if (_batchMode) {
          setState(() {
            if (v == true) {
              _selected.add(it.key);
            } else {
              _selected.remove(it.key);
            }
          });
        } else {
          _tandai(it);
        }
      },
      color: it.sudahAnomali
          ? WidgetStatePropertyAll(_accent.withValues(alpha: 0.06))
          : null,
      cells: [
        DataCell(Text('${index + 1}')),
        DataCell(ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 150),
          child: Text(it.namaKk.isEmpty ? it.assignmentId : it.namaKk,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700)),
        )),
        DataCell(ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 120),
          child: Text(it.namaPetugas.isEmpty ? '-' : it.namaPetugas,
              maxLines: 1, overflow: TextOverflow.ellipsis),
        )),
        DataCell(ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 150),
          child: Text(it.wilayahLabel.isEmpty ? '-' : it.wilayahLabel,
              maxLines: 2, overflow: TextOverflow.ellipsis),
        )),
        DataCell(IconButton(
          icon: const Icon(Icons.open_in_new_rounded, size: 18),
          color: const Color(0xFF1F6FEB),
          tooltip: 'Buka di Fasih',
          visualDensity: VisualDensity.compact,
          onPressed: () => _openFasih(it.assignmentId),
        )),
        for (final k in KeluargaAsetItem.asetKeys) _asetCell(it, k),
        DataCell(ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 130),
          child: Text(it.statusText.isEmpty ? '-' : it.statusText,
              maxLines: 2, overflow: TextOverflow.ellipsis),
        )),
        DataCell(
          it.sudahAnomali
              ? TextButton.icon(
                  onPressed: () => _tandai(it),
                  icon: const Icon(Icons.check_circle, size: 16),
                  label: const Text('Edit'),
                  style: TextButton.styleFrom(foregroundColor: _accent),
                )
              : FilledButton(
                  onPressed: () => _tandai(it),
                  style: FilledButton.styleFrom(
                    backgroundColor: _accent,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    minimumSize: const Size(0, 30),
                  ),
                  child: const Text('Tandai'),
                ),
        ),
      ],
    );
  }

  DataCell _asetCell(KeluargaAsetItem it, String k) {
    final v = it.nilai[k] ?? 0;
    final over = it.lewat.contains(k);
    return DataCell(
      Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: over
            ? BoxDecoration(
                color: _warn.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(8),
              )
            : null,
        child: Text(
          '$v',
          style: TextStyle(
            fontWeight: over ? FontWeight.w800 : FontWeight.w400,
            color: over ? _warn : const Color(0xFF10243E),
          ),
        ),
      ),
    );
  }

  Widget _buildPagination() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TextButton.icon(
            onPressed:
                (_isLoading || _page == 0) ? null : () => _loadPage(_page - 1),
            icon: const Icon(Icons.chevron_left_rounded),
            label: const Text('Sebelumnya'),
          ),
          Text('Halaman ${_page + 1}',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          TextButton(
            onPressed:
                (_isLoading || !_hasNext) ? null : () => _loadPage(_page + 1),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Text('Berikutnya'),
                Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
