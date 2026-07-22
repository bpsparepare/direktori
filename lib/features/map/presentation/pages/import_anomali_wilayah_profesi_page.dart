import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models/anggota_profesi_item.dart';
import '../../data/services/anomali_wilayah_service.dart';
import '../../data/services/profesi_lookup.dart';

/// Impor anomali wilayah - Profesi Tanpa Usaha (UW4). Admin melihat anggota
/// berprofesi + daftar usaha di assignment yang sama; bila profesi tapi belum
/// ada usaha, bisa ditandai.
class ImportAnomaliWilayahProfesiPage extends StatefulWidget {
  const ImportAnomaliWilayahProfesiPage({super.key});

  @override
  State<ImportAnomaliWilayahProfesiPage> createState() =>
      _ImportAnomaliWilayahProfesiPageState();
}

class _ImportAnomaliWilayahProfesiPageState
    extends State<ImportAnomaliWilayahProfesiPage> {
  final AnomaliWilayahService _service = AnomaliWilayahService();
  final TextEditingController _searchController = TextEditingController();

  static const Color _accent = Color(0xFF0E7C86);
  static const String _allPtg = 'Semua petugas';
  static const String _allProf = 'Semua profesi';
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
  List<AnggotaProfesiItem> _items = [];
  bool _hasSearched = false;
  int _page = 0;
  bool _hasNext = false;

  Map<String, String> _profMap = {};
  List<String> _ptgOpts = [];
  List<String> _profOpts = []; // kode profesi yang ada di data
  String _petugasFilter = _allPtg;
  String _profesiFilter = _allProf; // kode, atau _allProf
  bool _tanpaUsaha = false;

  final Set<String> _selected = {};
  bool _batchMode = false;
  int _sortColumnIndex = 1;
  bool _sortAscending = true;

  @override
  void initState() {
    super.initState();
    _loadOptions();
    _loadProfesi();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadProfesi() async {
    final map = await ProfesiLookup.load();
    if (!mounted) return;
    setState(() => _profMap = map);
  }

  Future<void> _loadOptions() async {
    try {
      final opts = await _service.fetchProfesiFilterOptions();
      if (!mounted) return;
      setState(() {
        _ptgOpts = opts['petugas'] ?? [];
        _profOpts = opts['profesi'] ?? [];
      });
    } catch (_) {}
  }

  String _profNama(String kode) => ProfesiLookup.name(_profMap, kode);

  String _sortKey(AnggotaProfesiItem it, int col) {
    switch (col) {
      case 1: // Nama KK -> kelompokkan per assignment, urut no_urut di dalamnya.
        return '${it.assignmentId}#${it.noUrut.toString().padLeft(4, '0')}';
      case 2:
        return it.namaSubjek.toLowerCase();
      case 3:
        return _profNama(it.profesi).toLowerCase();
      case 4:
        return it.wilayahLabel.toLowerCase();
      case 5:
        return it.namaPetugas.toLowerCase();
      case 6:
        return it.jumlahUsaha.toString().padLeft(6, '0');
      default:
        return '';
    }
  }

  List<AnggotaProfesiItem> get _viewItems {
    final list = [..._items];
    list.sort((a, b) =>
        _sortKey(a, _sortColumnIndex).compareTo(_sortKey(b, _sortColumnIndex)));
    return _sortAscending ? list : list.reversed.toList();
  }

  Future<void> _cari() => _loadPage(0);

  Future<void> _loadPage(int page) async {
    setState(() {
      _isLoading = true;
      _error = null;
      _hasSearched = true;
    });
    try {
      final items = await _service.fetchAnggotaProfesi(
        query: _searchController.text.trim().isEmpty
            ? null
            : _searchController.text.trim(),
        petugas: _petugasFilter == _allPtg ? null : _petugasFilter,
        profesi: _profesiFilter == _allProf ? null : _profesiFilter,
        tanpaUsaha: _tanpaUsaha,
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

  void _onSort(int col, bool asc) =>
      setState(() {
        _sortColumnIndex = col;
        _sortAscending = asc;
      });

  Future<void> _tandai(AnggotaProfesiItem item) async {
    final controller = TextEditingController(text: item.komentarAdmin);
    final komentar = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Tandai Profesi Tanpa Usaha'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.namaSubjek,
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              _kv('KK', item.namaKk),
              _kv('Profesi', _profNama(item.profesi)),
              _kv('Petugas', item.namaPetugas),
              _kv('Wilayah', item.wilayahLabel),
              _kv('Status', item.statusText),
              _kv('Usaha (${item.jumlahUsaha})',
                  item.daftarUsaha.isEmpty ? 'belum ada usaha' : item.daftarUsaha),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                maxLines: 3,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Catatan (wajib)',
                  hintText: 'Contoh: Profesi pedagang tapi usaha belum dicacah.',
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
      await _service.insertAnomaliProfesi(
        assignmentId: item.assignmentId,
        noUrut: item.noUrut,
        profesiNama: _profNama(item.profesi),
        komentar: komentar,
      );
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Anomali profesi ditandai.')),
      );
      await _loadPage(_page);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
            content: Text('Gagal menandai: $e'),
            backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _tandaiBatch() async {
    final chosen = _items.where((e) => _selected.contains(e.key)).toList();
    if (chosen.isEmpty) return;
    final controller = TextEditingController();
    final komentar = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Tandai ${chosen.length} anggota'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Catatan yang sama untuk semua terpilih.',
                style: TextStyle(fontSize: 12, color: Colors.blueGrey[600])),
            const SizedBox(height: 12),
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
      final n = await _service.insertAnomaliProfesiBatch(
        items: chosen
            .map((e) => {
                  'assignment_id': e.assignmentId,
                  'no_urut': e.noUrut,
                  'profesi_nama': _profNama(e.profesi),
                })
            .toList(),
        komentar: komentar,
      );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('$n anggota ditandai anomali.')),
      );
      await _loadPage(_page);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
            content: Text('Gagal menandai: $e'),
            backgroundColor: Colors.red),
      );
    }
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: RichText(
          text: TextSpan(
            style: const TextStyle(fontSize: 13, color: Color(0xFF10243E)),
            children: [
              TextSpan(
                  text: '$k: ',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              TextSpan(text: v.isEmpty ? '-' : v),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FB),
      appBar: AppBar(
        title: const Text('Pengecekan Profesi'),
        backgroundColor: _accent,
        foregroundColor: Colors.white,
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
    // Angkat di atas bar pagination supaya tidak menabrak tombol Berikutnya.
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
            heroTag: 'prof-tandai',
            backgroundColor: _accent,
            foregroundColor: Colors.white,
            onPressed: _tandaiBatch,
            icon: const Icon(Icons.playlist_add_check_rounded),
            label: Text('Tandai (${_selected.length})'),
          ),
          const SizedBox(height: 10),
        ],
        FloatingActionButton.extended(
          heroTag: 'prof-keluar',
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
                    hintText: 'Cari nama anggota / kode profesi...',
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
                child: _buildDropdown(
                  label: 'Profesi',
                  value: _profesiFilter,
                  display: (v) => v == _allProf ? _allProf : _profNama(v),
                  options: [_allProf, ..._profOpts],
                  onChanged: (v) {
                    setState(() => _profesiFilter = v);
                    _loadPage(0);
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildDropdown(
                  label: 'Petugas',
                  value: _petugasFilter,
                  display: (v) => v,
                  options: [_allPtg, ..._ptgOpts],
                  onChanged: (v) {
                    setState(() => _petugasFilter = v);
                    _loadPage(0);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: FilterChip(
              selected: _tanpaUsaha,
              label: const Text('Hanya yang belum ada usaha'),
              selectedColor: _accent.withValues(alpha: 0.16),
              checkmarkColor: _accent,
              onSelected: (v) {
                setState(() => _tanpaUsaha = v);
                _loadPage(0);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required String value,
    required String Function(String) display,
    required List<String> options,
    required ValueChanged<String> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      key: ValueKey('$label-$value'),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      items: options
          .map((o) => DropdownMenuItem(
                value: o,
                child: Text(display(o), overflow: TextOverflow.ellipsis),
              ))
          .toList(),
      onChanged: (v) => onChanged(v ?? value),
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
            'Tekan Cari untuk menampilkan anggota berprofesi beserta usaha '
            'di assignment-nya.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.blueGrey[600], height: 1.5),
          ),
        ),
      );
    }
    final rows = _viewItems;
    if (rows.isEmpty) {
      return Center(
        child: Text('Tidak ada data.',
            style: TextStyle(color: Colors.blueGrey[600])),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('${rows.length} anggota di halaman ini',
                style: TextStyle(color: Colors.blueGrey[600], fontSize: 12)),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: _buildTable(rows),
              ),
            ),
          ),
        ),
        _buildPagination(),
      ],
    );
  }

  Widget _buildTable(List<AnggotaProfesiItem> rows) {
    return DataTable(
      sortColumnIndex: _sortColumnIndex,
      sortAscending: _sortAscending,
      showCheckboxColumn: _batchMode,
      dataRowMinHeight: 48,
      dataRowMaxHeight: 96,
      headingRowColor:
          WidgetStatePropertyAll(_accent.withValues(alpha: 0.08)),
      columnSpacing: 20,
      columns: [
        const DataColumn(label: Text('No')),
        DataColumn(label: const Text('Nama KK'), onSort: _onSort),
        DataColumn(label: const Text('Nama Anggota'), onSort: _onSort),
        DataColumn(label: const Text('Profesi'), onSort: _onSort),
        DataColumn(label: const Text('Wilayah'), onSort: _onSort),
        DataColumn(label: const Text('Petugas'), onSort: _onSort),
        DataColumn(label: const Text('Usaha'), numeric: true, onSort: _onSort),
        const DataColumn(label: Text('Daftar Usaha')),
        const DataColumn(label: Text('Status')),
        const DataColumn(label: Text('Fasih')),
        const DataColumn(label: Text('Aksi')),
      ],
      rows: [for (var i = 0; i < rows.length; i++) _row(rows[i], i)],
    );
  }

  DataRow _row(AnggotaProfesiItem it, int index) {
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
      color: it.tanpaUsaha
          ? WidgetStatePropertyAll(const Color(0xFFD97706).withValues(alpha: 0.06))
          : (it.sudahAnomali
              ? WidgetStatePropertyAll(_accent.withValues(alpha: 0.06))
              : null),
      cells: [
        DataCell(Text('${index + 1}')),
        DataCell(_cell(it.namaKk.isEmpty ? '-' : it.namaKk,
            width: 150, bold: true)),
        DataCell(_cell(it.namaSubjek, width: 150)),
        DataCell(_cell(_profNama(it.profesi), width: 150)),
        DataCell(_cell(it.wilayahLabel, width: 140)),
        DataCell(_cell(it.namaPetugas, width: 110)),
        DataCell(
          it.tanpaUsaha
              ? const Text('0',
                  style: TextStyle(
                      color: Color(0xFFB45309), fontWeight: FontWeight.w800))
              : Text('${it.jumlahUsaha}'),
        ),
        DataCell(_cell(
            it.daftarUsaha.isEmpty ? '— belum ada usaha —' : it.daftarUsaha,
            width: 200)),
        DataCell(_cell(it.statusText, width: 120)),
        DataCell(IconButton(
          icon: const Icon(Icons.open_in_new_rounded, size: 18),
          color: const Color(0xFF1F6FEB),
          tooltip: 'Buka di Fasih',
          visualDensity: VisualDensity.compact,
          onPressed: () => _openFasih(it.assignmentId),
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
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    minimumSize: const Size(0, 32),
                  ),
                  child: const Text('Tandai'),
                ),
        ),
      ],
    );
  }

  Widget _cell(String text, {double width = 140, bool bold = false}) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: width),
      child: Text(
        text.isEmpty ? '-' : text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
          color: const Color(0xFF10243E),
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
