import 'package:flutter/material.dart';

import '../../data/models/revisit_reject_item.dart';
import '../../data/services/revisit_service.dart';
import 'revisit_page.dart';

/// Tab "Reject": daftar assignment (sumber terpisah, diisi ekstensi) untuk
/// ditandai "perlu di-reject". Cakupan mengikuti ALOKASI REVISIT — petugas
/// hanya melihat SLS alokasinya, admin melihat semua.
///
/// Dua tingkat agar mudah dicari: tab ini menampilkan daftar SLS (bisa
/// dicari), lalu satu SLS dibuka ke halaman isinya yang punya pencarian
/// sendiri.
class RevisitRejectTab extends StatefulWidget {
  final bool isAdmin;

  const RevisitRejectTab({super.key, required this.isAdmin});

  @override
  State<RevisitRejectTab> createState() => _RevisitRejectTabState();
}

const Color _danger = Color(0xFFC62828);

class _RevisitRejectTabState extends State<RevisitRejectTab>
    with AutomaticKeepAliveClientMixin {
  final RevisitService _service = RevisitService();
  final TextEditingController _search = TextEditingController();

  bool _loading = true;
  String? _error;
  String _query = '';

  /// Hanya SLS yang masih ada tanda reject.
  bool _hanyaDitandai = false;

  /// Ringkasan per SLS saja; isi assignment diambil saat SLS dibuka.
  List<RevisitRejectSls> _sls = [];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _sls.isEmpty;
      _error = null;
    });
    try {
      final sls = await _service.fetchRejectSls();
      if (!mounted) return;
      setState(() {
        _sls = sls;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  int get _totalAssignment =>
      _sls.fold<int>(0, (s, g) => s + g.jumlahAssignment);

  int get _totalDitandai => _sls.fold<int>(0, (s, g) => s + g.jumlahDitandai);

  List<RevisitRejectSls> get _filtered {
    final q = _query.trim().toLowerCase();
    return _sls.where((g) {
      if (_hanyaDitandai && g.jumlahDitandai == 0) return false;
      if (q.isEmpty) return true;
      return [
        g.slsLabel,
        g.kodeSls,
        g.nmDesa,
        g.nmKec,
        g.revisitNama,
      ].join(' ').toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _openSls(RevisitRejectSls g) async {
    // Halaman SLS mengembalikan jumlah tanda terbaru agar kartu di daftar
    // ikut berubah tanpa memuat ulang semuanya.
    final ditandai = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => RevisitRejectSlsPage(sls: g, isAdmin: widget.isAdmin),
      ),
    );
    if (!mounted || ditandai == null) return;
    setState(() {
      _sls = [
        for (final x in _sls)
          x.kodeSls == g.kodeSls ? x.withDitandai(ditandai) : x,
      ];
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return RevisitErrorView(error: _error!, onRetry: _load);

    final groups = _filtered;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          RevisitHeaderCard(
            title: 'Perlu Reject',
            subtitle: widget.isAdmin
                ? 'Semua SLS alokasi revisit'
                : 'SLS alokasi revisit Anda',
            stats: [
              ('${_sls.length}', 'SLS'),
              ('$_totalAssignment', 'assignment'),
              ('$_totalDitandai', 'ditandai reject'),
            ],
            trailing: IconButton(
              color: Colors.white,
              tooltip: 'Muat ulang',
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ),
          const SizedBox(height: 12),
          RevisitSearchField(
            controller: _search,
            hint: 'Cari SLS / desa / kecamatan',
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${groups.length} SLS',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF475569),
                  ),
                ),
              ),
              FilterChip(
                label: const Text('Ada tanda reject'),
                selected: _hanyaDitandai,
                onSelected: (v) => setState(() => _hanyaDitandai = v),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_sls.isEmpty)
            const RevisitEmptyView(
              message: 'Belum ada data. Daftar ini diisi lewat impor ekstensi.',
            )
          else if (groups.isEmpty)
            const RevisitEmptyView(message: 'Tidak ada SLS yang cocok.')
          else
            for (final g in groups) ...[_slsCard(g), const SizedBox(height: 8)],
        ],
      ),
    );
  }

  Widget _slsCard(RevisitRejectSls g) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openSls(g),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      g.slsLabel,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      revisitWilayahLabel(g.nmDesa, g.nmKec),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _chip(
                          '${g.jumlahAssignment} assignment',
                          const Color(0xFF475569),
                        ),
                        if (g.jumlahDitandai > 0)
                          _chip('${g.jumlahDitandai} ditandai', _danger),
                        if (widget.isAdmin && g.revisitNama.isNotEmpty)
                          _chip(g.revisitNama, revisitPrimary),
                        if (g.hariKe != null)
                          _chip('Hari ke-${g.hariKe}', revisitPrimary),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Isi satu SLS: daftar assignment dengan pencarian & filter sendiri.
class RevisitRejectSlsPage extends StatefulWidget {
  final RevisitRejectSls sls;
  final bool isAdmin;

  const RevisitRejectSlsPage({
    super.key,
    required this.sls,
    required this.isAdmin,
  });

  @override
  State<RevisitRejectSlsPage> createState() => _RevisitRejectSlsPageState();
}

enum _Filter { semua, ditandai, belum }

class _RevisitRejectSlsPageState extends State<RevisitRejectSlsPage> {
  final RevisitService _service = RevisitService();
  final TextEditingController _search = TextEditingController();

  List<RevisitRejectItem> _items = [];
  bool _loading = true;
  String? _error;
  String _query = '';
  _Filter _filter = _Filter.semua;
  String? _status;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Isi assignment SLS ini baru diambil di sini (tab hanya memuat
  /// ringkasan per SLS).
  Future<void> _load() async {
    setState(() {
      _loading = _items.isEmpty;
      _error = null;
    });
    try {
      final items = await _service.fetchRejectDetail(widget.sls.kodeSls);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  int get _ditandai => _items.where((i) => i.perluReject).length;

  Map<String, int> get _statusCounts {
    final counts = <String, int>{};
    for (final i in _items) {
      final key = i.statusAlias.isEmpty ? '-' : i.statusAlias;
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return Map.fromEntries(
      counts.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
  }

  List<RevisitRejectItem> get _filtered {
    final q = _query.trim().toLowerCase();
    return _items.where((i) {
      if (_filter == _Filter.ditandai && !i.perluReject) return false;
      if (_filter == _Filter.belum && i.perluReject) return false;
      if (_status != null &&
          (i.statusAlias.isEmpty ? '-' : i.statusAlias) != _status) {
        return false;
      }
      if (q.isEmpty) return true;
      return [
        i.nama,
        i.alamat,
        i.noBang,
        i.assignmentId,
      ].join(' ').toLowerCase().contains(q);
    }).toList();
  }

  void _replace(RevisitRejectItem updated) {
    setState(() {
      _items = [
        for (final i in _items)
          i.assignmentId == updated.assignmentId ? updated : i,
      ];
    });
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red : null,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _tandai(RevisitRejectItem item) async {
    final controller = TextEditingController(text: item.alasanReject);
    final alasan = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tandai perlu di-reject?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.nama.isEmpty ? item.assignmentId : item.nama,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            if (item.alamat.isNotEmpty)
              Text(
                item.alamat,
                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Alasan reject',
                hintText: 'mis. isian tidak sesuai, bukan usaha, ganda',
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
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            style: TextButton.styleFrom(foregroundColor: _danger),
            child: const Text('Tandai'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (alasan == null) return;

    setState(() => _busy = true);
    try {
      await _service.tandaiReject(item.assignmentId, alasan: alasan);
      if (!mounted) return;
      _replace(
        item.copyWithReject(
          perluReject: true,
          alasanReject: alasan,
          rejectOleh: 'Anda',
          rejectAt: DateTime.now(),
        ),
      );
      _snack('Ditandai perlu di-reject');
    } catch (e) {
      _snack('Gagal menandai: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _batalkan(RevisitRejectItem item) async {
    setState(() => _busy = true);
    try {
      await _service.batalkanReject(item.assignmentId);
      if (!mounted) return;
      _replace(item.copyWithReject(perluReject: false));
      _snack('Tanda reject dibatalkan');
    } catch (e) {
      _snack('Gagal membatalkan: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sls = widget.sls;
    final items = _filtered;
    // Back sistem pun mengembalikan jumlah tanda terbaru ke daftar SLS.
    return PopScope<int>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_busy) Navigator.of(context).pop(_ditandai);
      },
      child: Scaffold(
        backgroundColor: revisitBackground,
        appBar: AppBar(
          backgroundColor: revisitPrimary,
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(_ditandai),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(sls.slsLabel, style: const TextStyle(fontSize: 17)),
              Text(
                '${revisitWilayahLabel(sls.nmDesa, sls.nmKec)}'
                ' · ${sls.kodeSls}',
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Muat ulang',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? RevisitErrorView(error: _error!, onRetry: _load)
            : Stack(
                children: [
                  Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        child: RevisitSearchField(
                          controller: _search,
                          hint: 'Cari nama usaha / alamat / no. bangunan',
                          onChanged: (v) => setState(() => _query = v),
                        ),
                      ),
                      SizedBox(
                        height: 40,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          children: [
                            ChoiceChip(
                              label: Text('Semua (${_items.length})'),
                              selected:
                                  _filter == _Filter.semua && _status == null,
                              onSelected: (_) => setState(() {
                                _filter = _Filter.semua;
                                _status = null;
                              }),
                            ),
                            const SizedBox(width: 6),
                            ChoiceChip(
                              label: Text('Ditandai ($_ditandai)'),
                              selected: _filter == _Filter.ditandai,
                              selectedColor: _danger,
                              labelStyle: TextStyle(
                                color: _filter == _Filter.ditandai
                                    ? Colors.white
                                    : _danger,
                                fontWeight: FontWeight.w600,
                              ),
                              onSelected: (_) => setState(() {
                                _filter = _Filter.ditandai;
                                _status = null;
                              }),
                            ),
                            const SizedBox(width: 6),
                            ChoiceChip(
                              label: Text(
                                'Belum (${_items.length - _ditandai})',
                              ),
                              selected: _filter == _Filter.belum,
                              onSelected: (_) => setState(() {
                                _filter = _Filter.belum;
                                _status = null;
                              }),
                            ),
                            for (final e in _statusCounts.entries) ...[
                              const SizedBox(width: 6),
                              ChoiceChip(
                                label: Text('${e.key} (${e.value})'),
                                selected: _status == e.key,
                                onSelected: (_) => setState(() {
                                  _status = _status == e.key ? null : e.key;
                                  _filter = _Filter.semua;
                                }),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                        child: Row(
                          children: [
                            Text(
                              '${items.length} dari ${_items.length} assignment',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: items.isEmpty
                            ? const RevisitEmptyView(
                                message: 'Tidak ada yang cocok di SLS ini.',
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  4,
                                  16,
                                  24,
                                ),
                                itemCount: items.length,
                                itemBuilder: (context, i) =>
                                    _itemTile(items[i]),
                              ),
                      ),
                    ],
                  ),
                  if (_busy)
                    const Positioned.fill(
                      child: ColoredBox(
                        color: Color(0x22000000),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _itemTile(RevisitRejectItem i) {
    final bolehTandai = widget.isAdmin || i.revisitPetugasId.isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: i.perluReject ? const Color(0xFFFDECEC) : Colors.white,
        border: Border.all(
          color: i.perluReject
              ? _danger.withValues(alpha: 0.4)
              : const Color(0xFFE2E8F0),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
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
                    Text(
                      i.nama.isEmpty ? i.assignmentId : i.nama,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (i.alamat.isNotEmpty || i.noBang.isNotEmpty)
                      Text(
                        [
                          if (i.noBang.isNotEmpty) 'No. ${i.noBang}',
                          i.alamat,
                        ].where((e) => e.isNotEmpty).join(' · '),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                      ),
                  ],
                ),
              ),
              if (i.statusAlias.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F1FB),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    i.statusAlias,
                    style: const TextStyle(
                      fontSize: 11,
                      color: revisitPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          if (i.perluReject) ...[
            const SizedBox(height: 6),
            Text(
              [
                if (i.alasanReject.isNotEmpty) 'Alasan: ${i.alasanReject}',
                if (i.rejectOleh.isNotEmpty) 'oleh ${i.rejectOleh}',
              ].join(' · '),
              style: const TextStyle(fontSize: 12, color: _danger),
            ),
          ],
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: i.perluReject
                ? TextButton.icon(
                    onPressed: _busy ? null : () => _batalkan(i),
                    icon: const Icon(Icons.undo_rounded, size: 18),
                    label: const Text('Batalkan'),
                  )
                : TextButton.icon(
                    onPressed: _busy || !bolehTandai ? null : () => _tandai(i),
                    style: TextButton.styleFrom(foregroundColor: _danger),
                    icon: const Icon(Icons.block_rounded, size: 18),
                    label: Text(
                      bolehTandai ? 'Tandai reject' : 'Belum dialokasikan',
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
