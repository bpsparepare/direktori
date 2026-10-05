import 'package:flutter/material.dart';

import '../../data/models/tindak_lanjut_item.dart';
import '../../data/services/tindak_lanjut_service.dart';

/// Halaman "Submit": daftar assignment yang belum submit (REJECTED/DRAFT/OPEN)
/// hasil impor ekstensi ke `se2026_tindak_lanjut`. Petugas dapat menandai
/// assignment sebagai "Perlu Dihapus" beserta alasannya. Tanda disimpan di
/// tabel terpisah sehingga tetap ada walau daftar di-replace tiap impor.
class SubmitPage extends StatefulWidget {
  const SubmitPage({super.key});

  @override
  State<SubmitPage> createState() => _SubmitPageState();
}

/// Filter khusus di samping filter per status alias.
const String _filterSemua = '__semua__';
const String _filterHapus = '__hapus__';

class _SubmitPageState extends State<SubmitPage> {
  static const Color _primary = Color(0xFF0F4C81);
  static const Color _danger = Color(0xFFC62828);
  static const Color _rekapBg = Color(0xFFFFE8C7);
  static const Color _rekapAccent = Color(0xFFE67700);
  static const Color _rekapText = Color(0xFF7A3E00);

  final TindakLanjutService _service = TindakLanjutService();
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  String? _error;
  String _query = '';
  String _filter = _filterSemua;
  List<TindakLanjutItem> _items = [];

  /// Kode SLS yang sedang dibuka. Default kosong = semua wilayah tertutup.
  final Set<String> _expanded = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = _items.isEmpty;
      _error = null;
    });
    try {
      final items = await _service.fetchList();
      if (!mounted) return;
      setState(() {
        _items = items;
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

  /// Hitungan per status alias (urut nama) untuk chip filter.
  Map<String, int> get _statusCounts {
    final counts = <String, int>{};
    for (final item in _items) {
      final key = item.statusAlias.isEmpty ? '-' : item.statusAlias;
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return Map.fromEntries(
      counts.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
  }

  int get _hapusCount => _items.where((i) => i.perluHapus).length;

  List<TindakLanjutItem> get _filtered {
    final q = _query.trim().toLowerCase();
    return _items.where((item) {
      if (_filter == _filterHapus && !item.perluHapus) return false;
      if (_filter != _filterSemua &&
          _filter != _filterHapus &&
          (item.statusAlias.isEmpty ? '-' : item.statusAlias) != _filter) {
        return false;
      }
      if (q.isEmpty) return true;
      return [
        item.nama,
        item.alamat,
        item.noBang,
        item.slsLabel,
        item.nmDesa,
        item.nmKec,
        item.pplNama,
      ].join(' ').toLowerCase().contains(q);
    }).toList();
  }

  /// Kelompokkan per SLS (kode 16 digit), urutan mengikuti RPC.
  List<MapEntry<String, List<TindakLanjutItem>>> get _groups {
    final map = <String, List<TindakLanjutItem>>{};
    for (final item in _filtered) {
      map.putIfAbsent(item.kodeWilayah, () => []).add(item);
    }
    return map.entries.toList();
  }

  Color _statusColor(String alias) {
    final upper = alias.toUpperCase();
    if (upper.contains('REJECT')) return _danger;
    if (upper.contains('DRAFT')) return const Color(0xFFEA8600);
    if (upper.contains('OPEN')) return const Color(0xFF5B6B7B);
    return _primary;
  }

  void _showSnack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red : null,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _replaceItem(TindakLanjutItem updated) {
    setState(() {
      _items = [
        for (final i in _items)
          i.assignmentId == updated.assignmentId ? updated : i,
      ];
    });
  }

  Future<void> _tandaiHapus(TindakLanjutItem item) async {
    final alasanController = TextEditingController(text: item.alasanHapus);
    final alasan = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tandai perlu dihapus?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.nama.isEmpty ? item.assignmentId : item.nama,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: alasanController,
              autofocus: true,
              maxLines: 3,
              minLines: 2,
              decoration: const InputDecoration(
                labelText:
                    'Alasan (mis. ganda, tidak ditemukan, di luar wilayah)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, alasanController.text.trim()),
            style: TextButton.styleFrom(foregroundColor: _danger),
            child: const Text('Tandai'),
          ),
        ],
      ),
    );
    alasanController.dispose();
    if (alasan == null) return;

    try {
      await _service.tandaiHapus(item.assignmentId, alasan: alasan);
      if (!mounted) return;
      _replaceItem(
        item.copyWithHapus(
          perluHapus: true,
          alasanHapus: alasan,
          hapusOleh: 'Anda',
          hapusAt: DateTime.now(),
        ),
      );
      _showSnack('Ditandai perlu dihapus');
    } catch (e) {
      if (!mounted) return;
      _showSnack('Gagal menandai: $e', error: true);
    }
  }

  Future<void> _batalkanHapus(TindakLanjutItem item) async {
    try {
      await _service.batalkanHapus(item.assignmentId);
      if (!mounted) return;
      _replaceItem(item.copyWithHapus(perluHapus: false));
      _showSnack('Tanda hapus dibatalkan');
    } catch (e) {
      if (!mounted) return;
      _showSnack('Gagal membatalkan: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FB),
      appBar: AppBar(
        title: const Text('Submit'),
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        actions: [
          Builder(
            builder: (context) {
              final keys = _groups.map((g) => g.key).toSet();
              final allOpen = keys.isNotEmpty && _expanded.containsAll(keys);
              return IconButton(
                tooltip: allOpen ? 'Tutup semua' : 'Buka semua',
                onPressed: keys.isEmpty
                    ? null
                    : () => setState(() {
                        allOpen ? _expanded.clear() : _expanded.addAll(keys);
                      }),
                icon: Icon(
                  allOpen
                      ? Icons.unfold_less_rounded
                      : Icons.unfold_more_rounded,
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'Muat ulang',
            onPressed: _isLoading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? _buildError()
            : RefreshIndicator(
                onRefresh: _load,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(child: _buildHeader()),
                    SliverToBoxAdapter(child: _buildSearch()),
                    SliverToBoxAdapter(child: _buildFilterChips()),
                    if (_filtered.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _buildEmpty(),
                      )
                    else
                      ..._buildGroupSlivers(),
                    const SliverToBoxAdapter(child: SizedBox(height: 32)),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F4C81), Color(0xFF2D77D0)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Belum Submit',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Assignment berstatus REJECTED / DRAFT / OPEN yang perlu ditindaklanjuti. '
            'Tandai "Perlu Dihapus" bila assignment memang harus dihapus.',
            style: TextStyle(color: Colors.white, height: 1.4),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _headerStat('${_items.length}', 'belum submit'),
              const SizedBox(width: 10),
              _headerStat('$_hapusCount', 'perlu dihapus'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _headerStat(String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(12),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(color: Colors.white, fontSize: 12.5),
          children: [
            TextSpan(
              text: '$value ',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            TextSpan(text: label),
          ],
        ),
      ),
    );
  }

  Widget _buildSearch() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: TextField(
          controller: _searchController,
          onChanged: (value) => setState(() => _query = value),
          decoration: InputDecoration(
            hintText: 'Cari nama, alamat, no. bangunan, atau SLS',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _query = '');
                    },
                  ),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 16,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChips() {
    Widget chip(String key, String label, int count, Color color) {
      final selected = _filter == key;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text('$label ($count)'),
          selected: selected,
          onSelected: (_) => setState(() => _filter = key),
          selectedColor: color.withValues(alpha: 0.15),
          labelStyle: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: selected ? color : Colors.blueGrey[600],
          ),
          side: BorderSide(
            color: selected ? color : Colors.blueGrey.withValues(alpha: 0.2),
          ),
          backgroundColor: Colors.white,
          showCheckmark: false,
        ),
      );
    }

    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        children: [
          chip(_filterSemua, 'Semua', _items.length, _primary),
          for (final entry in _statusCounts.entries)
            chip(entry.key, entry.key, entry.value, _statusColor(entry.key)),
          chip(_filterHapus, 'Perlu Dihapus', _hapusCount, _danger),
        ],
      ),
    );
  }

  List<Widget> _buildGroupSlivers() {
    // Saat mencari, semua wilayah dibuka agar hasil langsung terlihat.
    final searching = _query.trim().isNotEmpty;
    final slivers = <Widget>[];
    for (final group in _groups) {
      final expanded = searching || _expanded.contains(group.key);
      slivers.add(
        SliverToBoxAdapter(
          child: _buildSlsHeader(group.key, group.value, expanded: expanded),
        ),
      );
      if (!expanded) continue;
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(28, 0, 16, 8),
          sliver: SliverList.separated(
            itemCount: group.value.length,
            itemBuilder: (context, index) => _buildCard(group.value[index]),
            separatorBuilder: (_, __) => const SizedBox(height: 8),
          ),
        ),
      );
    }
    return slivers;
  }

  Widget _buildSlsHeader(
    String key,
    List<TindakLanjutItem> items, {
    required bool expanded,
  }) {
    final first = items.first;
    final lokasi = [
      first.nmDesa,
      first.nmKec,
    ].where((v) => v.isNotEmpty).join(' · ');

    int countWhere(bool Function(String status) test) =>
        items.where((i) => test(i.statusAlias.toUpperCase())).length;
    final open = countWhere((s) => s.contains('OPEN'));
    final draft = countWhere((s) => s.contains('DRAFT'));
    final reject = countWhere((s) => s.contains('REJECT'));
    final lainnya = items.length - open - draft - reject;
    final hapus = items.where((i) => i.perluHapus).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Material(
        // Kartu rekap wilayah berwarna oranye agar kontras dgn kartu list (putih).
        color: _rekapBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: _rekapAccent.withValues(alpha: 0.45)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => setState(() {
            if (!_expanded.remove(key)) _expanded.add(key);
          }),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.map_outlined,
                      size: 18,
                      color: _rekapAccent,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            first.slsLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: _rekapText,
                            ),
                          ),
                          if (lokasi.isNotEmpty)
                            Text(
                              lokasi,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: _rekapText.withValues(alpha: 0.75),
                              ),
                            ),
                        ],
                      ),
                    ),
                    _tag('${items.length}', _rekapAccent, solid: true),
                    const SizedBox(width: 4),
                    Icon(
                      expanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: _rekapAccent,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 28),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      _tag('Open $open', _statusColor('OPEN'), solid: true),
                      _tag('Draft $draft', _statusColor('DRAFT'), solid: true),
                      _tag(
                        'Reject $reject',
                        _statusColor('REJECTED'),
                        solid: true,
                      ),
                      if (lainnya > 0)
                        _tag('Lainnya $lainnya', _primary, solid: true),
                      if (hapus > 0)
                        _tag('Perlu Dihapus $hapus', _danger, solid: true),
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

  Widget _buildCard(TindakLanjutItem item) {
    final subtitle = [
      if (item.noBang.isNotEmpty) 'No. Bang ${item.noBang}',
      if (item.alamat.isNotEmpty) item.alamat,
    ].join(' · ');
    return Material(
      color: item.perluHapus ? const Color(0xFFFFF1F1) : Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showDetail(item),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(
                item.perluHapus
                    ? Icons.delete_sweep_outlined
                    : Icons.pending_actions_outlined,
                size: 22,
                color: item.perluHapus ? _danger : _primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.nama.isEmpty ? '(tanpa nama)' : item.nama,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF10243E),
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.blueGrey[500],
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (item.statusAlias.isNotEmpty)
                          _tag(
                            item.statusAlias,
                            _statusColor(item.statusAlias),
                          ),
                        if (item.perluHapus) _tag('Perlu Dihapus', _danger),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: Colors.blueGrey[300]),
            ],
          ),
        ),
      ),
    );
  }

  void _showDetail(TindakLanjutItem item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  item.nama.isEmpty ? '(tanpa nama)' : item.nama,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF10243E),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (item.statusAlias.isNotEmpty)
                      _tag(item.statusAlias, _statusColor(item.statusAlias)),
                    if (item.pplNama.isNotEmpty)
                      _tag('PPL: ${item.pplNama}', const Color(0xFF1D8F5A)),
                  ],
                ),
                const SizedBox(height: 14),
                _infoRow(
                  Icons.map_outlined,
                  'SLS',
                  [
                    item.slsLabel,
                    item.nmDesa,
                    item.nmKec,
                  ].where((v) => v.isNotEmpty).join(' · '),
                ),
                if (item.noBang.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _infoRow(
                    Icons.home_work_outlined,
                    'No. Bangunan',
                    item.noBang,
                  ),
                ],
                if (item.alamat.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _infoRow(Icons.location_on_outlined, 'Alamat', item.alamat),
                ],
                const SizedBox(height: 12),
                _infoRow(Icons.tag_rounded, 'Assignment ID', item.assignmentId),
                if (item.perluHapus) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _danger.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'PERLU DIHAPUS',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: _danger,
                            letterSpacing: 0.4,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.alasanHapus.isEmpty
                              ? 'Tanpa alasan'
                              : item.alasanHapus,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.blueGrey[800],
                          ),
                        ),
                        if (item.hapusOleh.isNotEmpty || item.hapusAt != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              [
                                if (item.hapusOleh.isNotEmpty)
                                  'oleh ${item.hapusOleh}',
                                if (item.hapusAt != null)
                                  _formatDate(item.hapusAt!),
                              ].join(' · '),
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blueGrey[500],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: item.perluHapus
                      ? OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(sheetContext);
                            _batalkanHapus(item);
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _primary,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          icon: const Icon(Icons.undo_rounded),
                          label: const Text('Batalkan Tanda Hapus'),
                        )
                      : ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(sheetContext);
                            _tandaiHapus(item);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _danger,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          icon: const Icon(Icons.delete_outline_rounded),
                          label: const Text('Tandai Perlu Dihapus'),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  Widget _infoRow(IconData icon, String label, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: const Color(0xFF2D77D0)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.blueGrey[400],
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 2),
              SelectableText(
                text,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.blueGrey[800],
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tag(String text, Color color, {bool solid = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        // solid: latar putih agar tag tetap terbaca di atas kartu rekap oranye.
        color: solid ? Colors.white : color.withValues(alpha: 0.1),
        border: solid ? Border.all(color: color.withValues(alpha: 0.35)) : null,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    final filtering = _query.trim().isNotEmpty || _filter != _filterSemua;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              filtering ? Icons.search_off_rounded : Icons.task_alt_rounded,
              size: 64,
              color: Colors.blueGrey[200],
            ),
            const SizedBox(height: 12),
            Text(
              filtering
                  ? 'Tidak ada data yang cocok'
                  : 'Semua assignment sudah submit',
              style: TextStyle(fontSize: 15, color: Colors.blueGrey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 56,
              color: Colors.red,
            ),
            const SizedBox(height: 12),
            Text(
              'Gagal memuat data:\n$_error',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.blueGrey[700]),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Coba lagi'),
            ),
          ],
        ),
      ),
    );
  }
}
