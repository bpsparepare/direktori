import 'package:flutter/material.dart';

import '../../data/models/status_alias_stat.dart';
import '../../data/services/analisis_service.dart';

/// Tab "Analisis" (khusus admin).
///
/// Menampilkan statistik jumlah dokumen se2026_keterangan_umum yang
/// dikelompokkan berdasarkan assignment_status_alias dalam bentuk tabel.
class AnalisisPage extends StatefulWidget {
  const AnalisisPage({super.key});

  @override
  State<AnalisisPage> createState() => _AnalisisPageState();
}

class _AnalisisPageState extends State<AnalisisPage> {
  final AnalisisService _service = AnalisisService();

  bool _isLoading = true;
  String? _error;
  DateTime? _lastUpdatedAt;
  // 0 = Status, 1 = Kode Bangunan, 2 = Pivot Status × Bangunan,
  // 3 = Pivot Petugas × Bangunan, 4 = Pivot Petugas × Usaha,
  // 5 = Pivot Petugas × Ringkasan (Usaha/Keluarga/Anggota)
  int _view = 0;
  List<StatusAliasStat> _statusStats = [];
  List<StatusAliasStat> _kodeBangStats = [];
  List<StatusKodeBangGroup> _crossStats = [];
  List<StatusKodeBangGroup> _petugasStats = [];
  List<StatusKodeBangGroup> _usahaStats = [];
  List<StatusKodeBangGroup> _ringkasanStats = [];

  // Sort tabel biasa (view 0/1): key 'label' | 'jumlah'.
  String _tableSortKey = 'jumlah';
  bool _tableSortAsc = false;

  // Sort pivot (view 2/3): key '__row__' | 'total' | 'ditemukan' | 'lainnya'
  // | <label kode bangunan>.
  String _pivotSortKey = 'total';
  bool _pivotSortAsc = false;

  void _setTableSort(String key) {
    setState(() {
      if (_tableSortKey == key) {
        _tableSortAsc = !_tableSortAsc;
      } else {
        _tableSortKey = key;
        _tableSortAsc =
            key == 'label'; // teks default A→Z, angka default besar→kecil
      }
    });
  }

  void _setPivotSort(String key, {required bool numeric}) {
    setState(() {
      if (_pivotSortKey == key) {
        _pivotSortAsc = !_pivotSortAsc;
      } else {
        _pivotSortKey = key;
        _pivotSortAsc = !numeric; // teks default A→Z, angka default besar→kecil
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _service.fetchStatusAliasStats(),
        _service.fetchKodeBangStats(),
        _service.fetchStatusKodeBangStats(),
        _service.fetchPetugasKodeBangStats(),
        _service.fetchPetugasUsahaStats(),
        _service.fetchPetugasRingkasanStats(),
      ]);
      if (!mounted) return;
      setState(() {
        _statusStats = results[0] as List<StatusAliasStat>;
        _kodeBangStats = results[1] as List<StatusAliasStat>;
        _crossStats = results[2] as List<StatusKodeBangGroup>;
        _petugasStats = results[3] as List<StatusKodeBangGroup>;
        _usahaStats = results[4] as List<StatusKodeBangGroup>;
        _ringkasanStats = results[5] as List<StatusKodeBangGroup>;
        _isLoading = false;
        _lastUpdatedAt = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  List<StatusAliasStat> get _stats =>
      _view == 0 ? _statusStats : _kodeBangStats;

  List<StatusAliasStat> get _sortedStats {
    final list = [..._stats];
    list.sort((a, b) {
      final cmp = _tableSortKey == 'label'
          ? a.alias.toLowerCase().compareTo(b.alias.toLowerCase())
          : a.jumlah.compareTo(b.jumlah);
      return _tableSortAsc ? cmp : -cmp;
    });
    return list;
  }

  String get _firstColumnLabel =>
      _view == 0 ? 'Status Assignment' : 'Kode Bangunan';

  bool get _isPivot => _view >= 2 && _view <= 5;

  List<StatusKodeBangGroup> get _pivotGroups => switch (_view) {
    5 => _ringkasanStats,
    4 => _usahaStats,
    3 => _petugasStats,
    _ => _crossStats,
  };

  int get _total => _isPivot
      ? _pivotGroups.fold(0, (sum, g) => sum + g.total)
      : _stats.fold(0, (sum, s) => sum + s.jumlah);

  int get _categoryCount => _isPivot ? _pivotGroups.length : _stats.length;

  @override
  Widget build(BuildContext context) {
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
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
                    children: [
                      _buildHero(),
                      const SizedBox(height: 12),
                      _buildViewSelector(),
                      const SizedBox(height: 12),
                      if (_isPivot)
                        if (_pivotGroups.isEmpty)
                          _buildEmpty()
                        else
                          _buildPivotForView()
                      else if (_stats.isEmpty)
                        _buildEmpty()
                      else
                        _buildTable(),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildHero() {
    final updated = _lastUpdatedAt;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFF3B2C86), Color(0xFF5B3FB5), Color(0xFF8A6FE0)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF5B3FB5).withValues(alpha: 0.25),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.query_stats_rounded, color: Colors.white, size: 32),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Analisis',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                Text(
                  'Total ${_formatNumber(_total)} dokumen · '
                  '$_categoryCount kategori'
                  '${updated != null ? ' · diperbarui ${_formatTime(updated)}' : ''}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildViewSelector() {
    Widget chip(int index, String label) {
      final selected = _view == index;
      return GestureDetector(
        onTap: () => setState(() => _view = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF5B3FB5) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? const Color(0xFF5B3FB5)
                  : const Color(0xFFE0E0E0),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : const Color(0xFF6B7280),
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          chip(0, 'Status Assignment'),
          const SizedBox(width: 8),
          chip(1, 'Kode Bangunan'),
          const SizedBox(width: 8),
          chip(2, 'Pivot Status × Bangunan'),
          const SizedBox(width: 8),
          chip(3, 'Pivot Petugas × Bangunan'),
          const SizedBox(width: 8),
          chip(4, 'Pivot Petugas × Usaha'),
          const SizedBox(width: 8),
          chip(5, 'Pivot Petugas × Ringkasan'),
        ],
      ),
    );
  }

  /// Urutan kolom untuk pivot dengan [labelMap]: ikuti urutan map (yang muncul
  /// di data), lalu label lain (alfabet), dan "Tidak Diketahui" paling akhir.
  List<String> _pivotColumns(
    List<StatusKodeBangGroup> groups,
    Map<String, String> labelMap,
  ) {
    final present = <String>{};
    for (final g in groups) {
      for (final b in g.breakdown) {
        present.add(b.alias);
      }
    }
    final result = <String>[];
    for (final label in labelMap.values) {
      if (present.contains(label)) result.add(label);
    }
    final extras =
        present
            .where((l) => !labelMap.containsValue(l) && l != 'Tidak Diketahui')
            .toList()
          ..sort();
    result.addAll(extras);
    if (present.contains('Tidak Diketahui')) result.add('Tidak Diketahui');
    return result;
  }

  /// Pilih konfigurasi kolom pivot sesuai view aktif lalu render.
  Widget _buildPivotForView() {
    final groups = _pivotGroups;
    final firstCol = _view == 2 ? 'Status' : 'Petugas';
    // Ringkasan: kolom metrik tetap, tanpa kolom Total (satuan berbeda-beda).
    if (_view == 5) {
      return _buildCrossPivot(
        groups,
        firstCol,
        columns: const [
          'Usaha',
          'Usaha Pertanian',
          'Usaha Non Pertanian',
          'Keluarga',
          'Anggota Keluarga',
          'Rata-rata Anggota Keluarga',
        ],
        derived: {
          'Rata-rata Anggota Keluarga': (m) {
            final kk = m['Keluarga'] ?? 0;
            final ak = m['Anggota Keluarga'] ?? 0;
            return kk == 0 ? 0 : ak / kk;
          },
        },
        showTotalColumn: false,
      );
    }
    final labelMap = _view == 4
        ? AnalisisService.keberadaanUsahaLabels
        : AnalisisService.kodeBangLabels;
    // "Ditemukan" hanya untuk pivot kode bangunan (kode 1, 2, 3).
    final ditemukanLabels = _view == 4
        ? const <String>{}
        : {
            for (final c in ['1', '2', '3']) AnalisisService.kodeBangLabels[c]!,
          };
    return _buildCrossPivot(
      groups,
      firstCol,
      columns: _pivotColumns(groups, labelMap),
      ditemukanLabels: ditemukanLabels,
    );
  }

  Widget _buildCrossPivot(
    List<StatusKodeBangGroup> groups,
    String firstColLabel, {
    required List<String> columns,
    Set<String> ditemukanLabels = const {},
    bool showTotalColumn = true,
    Map<String, double Function(Map<String, int>)> derived = const {},
  }) {
    // Peta jumlah per (baris, label) dan total per kolom.
    final columnTotals = {for (final c in columns) c: 0};
    var grandTotal = 0;
    final rowMaps = <Map<String, int>>[];
    for (final g in groups) {
      final map = {for (final b in g.breakdown) b.alias: b.jumlah};
      rowMaps.add(map);
      for (final c in columns) {
        columnTotals[c] = columnTotals[c]! + (map[c] ?? 0);
      }
      grandTotal += g.total;
    }

    // Kolom rekap "Ditemukan"/"Lainnya" (hanya bila ditemukanLabels diisi,
    // mis. pivot kode bangunan: 1, 2, 3).
    final showSummary = ditemukanLabels.isNotEmpty;
    final ditemukanColumns = columns
        .where((c) => ditemukanLabels.contains(c))
        .toList();
    final ditemukanTotal = ditemukanColumns.fold(
      0,
      (sum, c) => sum + columnTotals[c]!,
    );
    final lainnyaTotal = grandTotal - ditemukanTotal;

    // Urutan baris sesuai kolom sort aktif.
    int rowDitemukan(int i) =>
        ditemukanColumns.fold(0, (sum, c) => sum + (rowMaps[i][c] ?? 0));
    double sortValue(int i) {
      switch (_pivotSortKey) {
        case 'total':
          return groups[i].total.toDouble();
        case 'ditemukan':
          return rowDitemukan(i).toDouble();
        case 'lainnya':
          return (groups[i].total - rowDitemukan(i)).toDouble();
        default:
          final d = derived[_pivotSortKey];
          if (d != null) return d(rowMaps[i]);
          return (rowMaps[i][_pivotSortKey] ?? 0).toDouble();
      }
    }

    final order = [for (var i = 0; i < groups.length; i++) i];
    order.sort((a, b) {
      final cmp = _pivotSortKey == '__row__'
          ? groups[a].status.toLowerCase().compareTo(
              groups[b].status.toLowerCase(),
            )
          : sortValue(a).compareTo(sortValue(b));
      return _pivotSortAsc ? cmp : -cmp;
    });

    const summaryWidth = 84.0;
    const categoryWidth = 108.0;

    const headerBg = Color(0xFF3B2C86);
    const totalBg = Color(0xFFEDE9F9);
    const fg = Color(0xFF1F2544);

    // Faktor skala kolom: >1 saat tabel lebih sempit dari layar (mengisi
    // ruang kosong), 1 saat perlu scroll horizontal.
    var pivotScale = 1.0;

    Widget cell(
      String text, {
      required bool isHeader,
      bool isTotal = false,
      bool isStatusCol = false,
      bool striped = false,
      Color? bg,
      Color? textColor,
      double? colWidth,
      VoidCallback? onTap,
    }) {
      final container = Container(
        width: (isStatusCol ? 190.0 : (colWidth ?? 56)) * pivotScale,
        color:
            bg ??
            (isHeader
                ? headerBg
                : isTotal
                ? totalBg
                : striped
                ? const Color(0xFFF8F9FC)
                : Colors.white),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        alignment: isStatusCol ? Alignment.centerLeft : Alignment.center,
        child: Text(
          text,
          textAlign: isStatusCol ? TextAlign.left : TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            fontWeight: (isHeader || isTotal)
                ? FontWeight.w700
                : FontWeight.w500,
            color: textColor ?? (isHeader ? Colors.white : fg),
          ),
        ),
      );
      if (onTap == null) return container;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: container,
      );
    }

    Widget headerCell(
      String label,
      String key, {
      bool isStatusCol = false,
      double? colWidth,
    }) {
      final active = _pivotSortKey == key;
      final arrow = active ? (_pivotSortAsc ? ' ▲' : ' ▼') : '';
      return cell(
        '$label$arrow',
        isHeader: true,
        isStatusCol: isStatusCol,
        colWidth: colWidth,
        onTap: () => _setPivotSort(key, numeric: key != '__row__'),
      );
    }

    // Nilai sel kategori: kolom turunan (derived) dihitung & diformat desimal,
    // selain itu jumlah biasa. Mengembalikan (teks, apakah nol).
    (String, bool) cellValue(Map<String, int> m, String c) {
      final d = derived[c];
      if (d != null) {
        final v = d(m);
        return v <= 0 ? ('·', true) : (v.toStringAsFixed(1), false);
      }
      final n = m[c] ?? 0;
      return n == 0 ? ('·', true) : (_formatNumber(n), false);
    }

    Widget dataRow(int index, int pos) {
      final g = groups[index];
      final map = rowMaps[index];
      final striped = pos.isOdd;
      final ditemukan = ditemukanColumns.fold(
        0,
        (sum, c) => sum + (map[c] ?? 0),
      );
      final lainnya = g.total - ditemukan;
      return Row(
        children: [
          cell(g.status, isHeader: false, isStatusCol: true, striped: striped),
          for (final c in columns)
            () {
              final (text, isZero) = cellValue(map, c);
              return cell(
                text,
                isHeader: false,
                striped: striped,
                colWidth: categoryWidth,
                textColor: isZero ? const Color(0xFFB6BCCC) : fg,
              );
            }(),
          if (showSummary) ...[
            cell(
              _formatNumber(ditemukan),
              isHeader: false,
              striped: striped,
              colWidth: summaryWidth,
            ),
            cell(
              _formatNumber(lainnya),
              isHeader: false,
              striped: striped,
              colWidth: summaryWidth,
            ),
          ],
          if (showTotalColumn)
            cell(
              _formatNumber(g.total),
              isHeader: false,
              isTotal: true,
              striped: striped,
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final natural =
                190.0 +
                columns.length * categoryWidth +
                (showSummary ? summaryWidth * 2 : 0.0) +
                (showTotalColumn ? 56.0 : 0.0);
            pivotScale = natural < constraints.maxWidth
                ? constraints.maxWidth / natural
                : 1.0;
            return Container(
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
              clipBehavior: Clip.antiAlias,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Column(
                  children: [
                    // Header (klik untuk sort). IntrinsicHeight+stretch agar
                    // sel yang labelnya membungkus tetap sama tinggi.
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          headerCell(
                            firstColLabel,
                            '__row__',
                            isStatusCol: true,
                          ),
                          for (final c in columns)
                            headerCell(c, c, colWidth: categoryWidth),
                          if (showSummary) ...[
                            headerCell(
                              'Ditemukan',
                              'ditemukan',
                              colWidth: summaryWidth,
                            ),
                            headerCell(
                              'Lainnya',
                              'lainnya',
                              colWidth: summaryWidth,
                            ),
                          ],
                          if (showTotalColumn) headerCell('Total', 'total'),
                        ],
                      ),
                    ),
                    for (var pos = 0; pos < order.length; pos++)
                      dataRow(order[pos], pos),
                    // Total row
                    Row(
                      children: [
                        cell(
                          'Total',
                          isHeader: false,
                          isTotal: true,
                          isStatusCol: true,
                        ),
                        for (final c in columns)
                          cell(
                            cellValue(columnTotals, c).$1,
                            isHeader: false,
                            isTotal: true,
                            colWidth: categoryWidth,
                          ),
                        if (showSummary) ...[
                          cell(
                            _formatNumber(ditemukanTotal),
                            isHeader: false,
                            isTotal: true,
                            colWidth: summaryWidth,
                          ),
                          cell(
                            _formatNumber(lainnyaTotal),
                            isHeader: false,
                            isTotal: true,
                            colWidth: summaryWidth,
                          ),
                        ],
                        if (showTotalColumn)
                          cell(
                            _formatNumber(grandTotal),
                            isHeader: false,
                            isTotal: true,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildTable() {
    final total = _total;
    final rows = _sortedStats;
    String arrow(String key) =>
        _tableSortKey == key ? (_tableSortAsc ? ' ▲' : ' ▼') : '';
    return Container(
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
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _buildRow(
            alias: '$_firstColumnLabel${arrow('label')}',
            jumlah: 'Jumlah${arrow('jumlah')}',
            persen: '%',
            isHeader: true,
            onTapAlias: () => _setTableSort('label'),
            onTapJumlah: () => _setTableSort('jumlah'),
          ),
          for (var i = 0; i < rows.length; i++)
            _buildRow(
              alias: rows[i].alias,
              jumlah: _formatNumber(rows[i].jumlah),
              persen: total == 0
                  ? '-'
                  : '${(rows[i].jumlah * 100 / total).toStringAsFixed(1)}%',
              striped: i.isOdd,
            ),
          _buildRow(
            alias: 'Total',
            jumlah: _formatNumber(total),
            persen: '100%',
            isTotal: true,
          ),
        ],
      ),
    );
  }

  Widget _buildRow({
    required String alias,
    required String jumlah,
    required String persen,
    bool isHeader = false,
    bool isTotal = false,
    bool striped = false,
    VoidCallback? onTapAlias,
    VoidCallback? onTapJumlah,
  }) {
    final Color bg = isHeader
        ? const Color(0xFF3B2C86)
        : isTotal
        ? const Color(0xFFEDE9F9)
        : striped
        ? const Color(0xFFF8F9FC)
        : Colors.white;
    final Color fg = isHeader ? Colors.white : const Color(0xFF1F2544);
    final FontWeight weight = (isHeader || isTotal)
        ? FontWeight.w700
        : FontWeight.w500;

    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTapAlias,
              child: Text(
                alias,
                style: TextStyle(fontSize: 13, color: fg, fontWeight: weight),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTapJumlah,
              child: Text(
                jumlah,
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 13, color: fg, fontWeight: weight),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              persen,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                color: isHeader ? Colors.white70 : const Color(0xFF6B7280),
                fontWeight: weight,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 16),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(Icons.inbox_rounded, size: 56, color: Colors.blueGrey[300]),
          const SizedBox(height: 12),
          Text(
            'Belum ada data statistik',
            style: TextStyle(color: Colors.blueGrey[600], fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 56, color: Colors.redAccent),
            const SizedBox(height: 12),
            Text(
              'Gagal memuat data',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.blueGrey[800],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _error ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.blueGrey[500]),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh),
              label: const Text('Coba lagi'),
            ),
          ],
        ),
      ),
    );
  }

  String _formatNumber(int value) {
    final s = value.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  String _formatTime(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(dt.hour)}:${two(dt.minute)}';
  }
}
