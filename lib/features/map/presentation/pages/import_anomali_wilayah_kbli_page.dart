import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models/usaha_kbli_item.dart';
import '../../data/services/anomali_wilayah_service.dart';
import '../../data/services/kbli_master.dart';

/// Impor anomali wilayah - Salah Penentuan KBLI (UW3). Tampilan tabel yang
/// bisa di-sort, dengan filter kategori & petugas.
class ImportAnomaliWilayahKbliPage extends StatefulWidget {
  const ImportAnomaliWilayahKbliPage({super.key});

  @override
  State<ImportAnomaliWilayahKbliPage> createState() =>
      _ImportAnomaliWilayahKbliPageState();
}

class _ImportAnomaliWilayahKbliPageState
    extends State<ImportAnomaliWilayahKbliPage> {
  final AnomaliWilayahService _service = AnomaliWilayahService();
  final TextEditingController _searchController = TextEditingController();

  static const Color _accent = Color(0xFF7A3EA1);
  static const String _allKat = 'Semua kategori';
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
  List<UsahaKbliItem> _items = [];
  bool _hasSearched = false;
  int _page = 0;
  bool _hasNext = false;

  String _kategoriFilter = _allKat;
  String _petugasFilter = _allPtg;
  List<String> _katOpts = [];
  List<String> _ptgOpts = [];
  Map<String, KbliInfo> _kbli = {};
  final Set<String> _selected = {};
  bool _batchMode = false;
  int _sortColumnIndex = 1;
  bool _sortAscending = true;

  @override
  void initState() {
    super.initState();
    _loadOptions();
    _loadKbli();
  }

  Future<void> _loadKbli() async {
    final map = await KbliMaster.load();
    if (!mounted) return;
    setState(() => _kbli = map);
  }

  KbliInfo? _kbliInfo(String kode) => _kbli[kode.trim()];

  /// Dialog pencarian KBLI dari master CSV. Kembalikan yang dipilih.
  Future<KbliInfo?> _cariKbli() async {
    if (_kbli.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Master KBLI belum termuat.')),
      );
      return null;
    }
    final all = _kbli.values.toList()
      ..sort((a, b) => a.kode.compareTo(b.kode));
    final media = MediaQuery.of(context);
    var query = '';
    return showDialog<KbliInfo>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) {
          final q = query.trim().toLowerCase();
          final filtered = (q.isEmpty
                  ? all
                  : all.where((e) =>
                      e.kode.contains(q) ||
                      e.judul.toLowerCase().contains(q) ||
                      e.deskripsi.toLowerCase().contains(q)))
              .take(150)
              .toList();
          return Dialog(
            insetPadding: EdgeInsets.symmetric(
                horizontal: media.size.width * 0.05, vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text('Cari KBLI',
                            style: TextStyle(
                                fontSize: 17, fontWeight: FontWeight.w800)),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    autofocus: true,
                    onChanged: (v) => setLocal(() => query = v),
                    decoration: const InputDecoration(
                      hintText: 'Ketik kode atau kata kunci...',
                      prefixIcon: Icon(Icons.search_rounded),
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                Flexible(
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(maxHeight: media.size.height * 0.55),
                    child: filtered.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(24),
                            child: Text('Tidak ditemukan.'),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final e = filtered[index];
                              return ListTile(
                                dense: true,
                                title: Text('${e.kode} · ${e.judul}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13)),
                                subtitle: e.deskripsi.isEmpty
                                    ? null
                                    : Text(e.deskripsi,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 11)),
                                onTap: () =>
                                    Navigator.of(dialogContext).pop(e),
                              );
                            },
                          ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _cariKbliReferensi() async {
    final picked = await _cariKbli();
    if (picked == null || !mounted) return;
    await Clipboard.setData(
        ClipboardData(text: '${picked.kode} - ${picked.judul}'));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Disalin: ${picked.kode} - ${picked.judul}')),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    try {
      final opts = await _service.fetchKbliFilterOptions();
      if (!mounted) return;
      setState(() {
        _katOpts = opts['kategori'] ?? [];
        _ptgOpts = opts['petugas'] ?? [];
      });
    } catch (_) {
      // opsi filter opsional; abaikan bila gagal.
    }
  }

  List<String> get _kategoriOptions => [_allKat, ..._katOpts];
  List<String> get _petugasOptions => [_allPtg, ..._ptgOpts];

  String _sortKey(UsahaKbliItem it, int col) {
    switch (col) {
      case 1:
        return it.namaSubjek.toLowerCase();
      case 2:
        return it.namaPetugas.toLowerCase();
      case 3:
        return it.wilayahLabel.toLowerCase();
      case 4:
        return it.kategori.toLowerCase();
      case 5:
        return it.kbli.toLowerCase();
      case 8:
        return it.statusText.toLowerCase();
      default:
        return '';
    }
  }

  List<UsahaKbliItem> get _viewItems {
    final list = [..._items];
    list.sort((a, b) =>
        _sortKey(a, _sortColumnIndex).compareTo(_sortKey(b, _sortColumnIndex)));
    if (!_sortAscending) {
      return list.reversed.toList();
    }
    return list;
  }

  /// Cari dari halaman awal (tombol Cari / submit).
  Future<void> _cari() => _loadPage(0);

  Future<void> _loadPage(int page) async {
    setState(() {
      _isLoading = true;
      _error = null;
      _hasSearched = true;
    });
    try {
      final items = await _service.fetchUsahaKbli(
        query: _searchController.text.trim().isEmpty
            ? null
            : _searchController.text.trim(),
        kategori: _kategoriFilter == _allKat ? null : _kategoriFilter,
        petugas: _petugasFilter == _allPtg ? null : _petugasFilter,
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

  void _onSort(int col, bool asc) {
    setState(() {
      _sortColumnIndex = col;
      _sortAscending = asc;
    });
  }

  Future<void> _tandai(UsahaKbliItem item) async {
    final controller = TextEditingController(text: item.komentarAdmin);
    final komentar = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Tandai Salah KBLI'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.namaSubjek,
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              _kv('Petugas', item.namaPetugas),
              _kv('Wilayah', item.wilayahLabel),
              _kv('KBLI',
                  '${item.kbli}${_kbliInfo(item.kbli) != null ? ' - ${_kbliInfo(item.kbli)!.judul}' : ''}'),
              if (_kbliInfo(item.kbli)?.deskripsi.isNotEmpty ?? false)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    _kbliInfo(item.kbli)!.deskripsi,
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.blueGrey[600],
                        height: 1.4),
                  ),
                ),
              _kv('Kategori', item.kategori),
              _kv('Keg. utama', item.kegUtama),
              _kv('Produk', item.produk),
              _kv('Status', item.statusText),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: _accent),
                  icon: const Icon(Icons.manage_search_rounded, size: 18),
                  label: const Text('Cari KBLI yang benar'),
                  onPressed: () async {
                    final picked = await _cariKbli();
                    if (picked == null) return;
                    final add = 'KBLI seharusnya ${picked.kode} '
                        '(${picked.judul})';
                    final cur = controller.text.trim();
                    controller.text = cur.isEmpty ? add : '$cur\n$add';
                  },
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Catatan koreksi KBLI (wajib)',
                  hintText: 'Contoh: KBLI seharusnya 47111 (toko kelontong).',
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
      await _service.insertAnomaliKbli(
        assignmentId: item.assignmentId,
        noUsaha: item.noUsaha,
        komentar: komentar,
      );
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
            content: Text('Anomali KBLI ditandai & catatan dikirim.')),
      );
      await _loadPage(_page);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Gagal menandai: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
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
            heroTag: 'kbli-tandai',
            backgroundColor: _accent,
            foregroundColor: Colors.white,
            onPressed: _tandaiBatch,
            icon: const Icon(Icons.playlist_add_check_rounded),
            label: Text('Tandai (${_selected.length})'),
          ),
          const SizedBox(height: 10),
        ],
        FloatingActionButton.extended(
          heroTag: 'kbli-keluar',
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

  Future<void> _tandaiBatch() async {
    final chosen = _items.where((e) => _selected.contains(e.key)).toList();
    if (chosen.isEmpty) return;
    final controller = TextEditingController();
    final komentar = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Tandai ${chosen.length} usaha'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Catatan yang sama akan diterapkan ke semua usaha terpilih.',
              style: TextStyle(fontSize: 12, color: Colors.blueGrey[600]),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 3,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Catatan koreksi KBLI (wajib)',
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
      final n = await _service.insertAnomaliKbliBatch(
        items: chosen,
        komentar: komentar,
      );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('$n usaha ditandai anomali KBLI.')),
      );
      await _loadPage(_page);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Gagal menandai: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _kv(String k, String v) {
    return Padding(
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FB),
      appBar: AppBar(
        title: const Text('Salah Penentuan KBLI'),
        backgroundColor: _accent,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Cari KBLI',
            icon: const Icon(Icons.manage_search_rounded),
            onPressed: _cariKbliReferensi,
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
                    hintText: 'Cari nama, KBLI, kegiatan, produk...',
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
          if (_katOpts.isNotEmpty || _ptgOpts.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _buildDropdown(
                    label: 'Kategori',
                    value: _kategoriFilter,
                    options: _kategoriOptions,
                    onChanged: (v) {
                      setState(() => _kategoriFilter = v);
                      _loadPage(0);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildDropdown(
                    label: 'Petugas',
                    value: _petugasFilter,
                    options: _petugasOptions,
                    onChanged: (v) {
                      setState(() => _petugasFilter = v);
                      _loadPage(0);
                    },
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required String value,
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
                child: Text(o, overflow: TextOverflow.ellipsis),
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
            'Cari usaha untuk memeriksa KBLI. Kosongkan lalu tekan Cari '
            'untuk menampilkan sebagian daftar.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.blueGrey[600], height: 1.5),
          ),
        ),
      );
    }
    final rows = _viewItems;
    if (rows.isEmpty) {
      return Center(
        child: Text('Tidak ada usaha ditemukan.',
            style: TextStyle(color: Colors.blueGrey[600])),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${rows.length} usaha di halaman ini'
              '${rows.length != _items.length ? ' (dari ${_items.length})' : ''}',
              style: TextStyle(color: Colors.blueGrey[600], fontSize: 12),
            ),
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

  Widget _buildPagination() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TextButton.icon(
            onPressed: (_isLoading || _page == 0)
                ? null
                : () => _loadPage(_page - 1),
            icon: const Icon(Icons.chevron_left_rounded),
            label: const Text('Sebelumnya'),
          ),
          Text(
            'Halaman ${_page + 1}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          TextButton(
            onPressed: (_isLoading || !_hasNext)
                ? null
                : () => _loadPage(_page + 1),
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

  Widget _buildTable(List<UsahaKbliItem> rows) {
    return DataTable(
      sortColumnIndex: _sortColumnIndex,
      sortAscending: _sortAscending,
      showCheckboxColumn: _batchMode,
      dataRowMinHeight: 48,
      dataRowMaxHeight: 92,
      headingRowColor:
          WidgetStatePropertyAll(_accent.withValues(alpha: 0.08)),
      columnSpacing: 22,
      columns: [
        const DataColumn(label: Text('No')),
        DataColumn(label: const Text('Nama Usaha'), onSort: _onSort),
        DataColumn(label: const Text('Petugas'), onSort: _onSort),
        DataColumn(label: const Text('Wilayah'), onSort: _onSort),
        DataColumn(label: const Text('Kat.'), onSort: _onSort),
        DataColumn(label: const Text('KBLI'), onSort: _onSort),
        const DataColumn(label: Text('Keg. Utama')),
        const DataColumn(label: Text('Produk')),
        DataColumn(label: const Text('Status'), onSort: _onSort),
        const DataColumn(label: Text('Fasih')),
        const DataColumn(label: Text('Aksi')),
      ],
      rows: [
        for (var i = 0; i < rows.length; i++) _buildDataRow(rows[i], i),
      ],
    );
  }

  DataRow _buildDataRow(UsahaKbliItem it, int index) {
    final info = _kbliInfo(it.kbli);
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
          _tandai(it); // klik baris = lihat detail (+ opsi tandai)
        }
      },
      color: it.sudahAnomali
          ? WidgetStatePropertyAll(_accent.withValues(alpha: 0.06))
          : null,
      cells: [
        DataCell(Text('${index + 1}')),
        DataCell(_cell(it.namaSubjek, width: 170, bold: true)),
        DataCell(_cell(it.namaPetugas, width: 120)),
        DataCell(_cell(it.wilayahLabel, width: 150)),
        DataCell(Text(it.kategori.isEmpty ? '-' : it.kategori)),
        DataCell(
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 190),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(it.kbli.isEmpty ? '-' : it.kbli,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13)),
                if (info != null && info.judul.isNotEmpty)
                  Text(
                    info.judul,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11, color: Colors.blueGrey[600]),
                  ),
              ],
            ),
          ),
        ),
        DataCell(_cell(it.kegUtama, width: 170)),
        DataCell(_cell(it.produk, width: 170)),
        DataCell(_cell(it.statusText, width: 130)),
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
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
}
