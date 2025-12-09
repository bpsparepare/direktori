import 'package:direktori/features/direktori/domain/usecases/get_direktori_stats.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import '../bloc/direktori_bloc.dart';
import '../bloc/direktori_event.dart';
import '../bloc/direktori_state.dart';
import '../widgets/direktori_data_grid.dart';
import '../widgets/direktori_search_bar.dart';
import '../widgets/batch_insert_dialog.dart';
import '../../domain/usecases/get_direktori_list.dart';
import '../../data/repositories/direktori_repository_impl.dart';
import '../../data/datasources/direktori_remote_datasource.dart';
import '../../../map/data/repositories/map_repository_impl.dart';
import '../../../map/data/models/direktori_model.dart';

class DirektoriListPage extends StatelessWidget {
  final void Function(String id)? onNavigateToMap;

  const DirektoriListPage({Key? key, this.onNavigateToMap}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) {
        final mapRepository = MapRepositoryImpl();
        final remoteDataSource = DirektoriRemoteDataSourceImpl(
          mapRepository: mapRepository,
        );
        final repository = DirektoriRepositoryImpl(
          remoteDataSource: remoteDataSource,
        );
        final getDirektoriList = GetDirektoriList(repository);
        final getDirektoriCount = GetDirektoriCount(repository);
        final getDirektoriStats = GetDirektoriStats(repository);

        return DirektoriBloc(
          getDirektoriList: getDirektoriList,
          getDirektoriCount: getDirektoriCount,
          getDirektoriStats: getDirektoriStats,
        );
      },
      child: _DirektoriListView(onNavigateToMap: onNavigateToMap),
    );
  }
}

class _DirektoriListView extends StatefulWidget {
  final void Function(String id)? onNavigateToMap;

  const _DirektoriListView({Key? key, this.onNavigateToMap}) : super(key: key);

  @override
  State<_DirektoriListView> createState() => _DirektoriListViewState();
}

class _DirektoriListViewState extends State<_DirektoriListView> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  String? _selectedLetter;
  bool _showStats = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // Load initial data
    context.read<DirektoriBloc>().add(
      const LoadDirektoriList(
        page: 1,
        includeCoordinates: true,
        sortColumn: 'nama',
        sortAscending: true,
        isRefresh: true,
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_isBottom) {
      context.read<DirektoriBloc>().add(const LoadMoreDirektori());
    }
  }

  bool get _isBottom {
    if (!_scrollController.hasClients) return false;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;
    return currentScroll >= (maxScroll * 0.9);
  }

  void _onSearch(String query) {
    context.read<DirektoriBloc>().add(SearchDirektori(query));
  }

  void _onRefresh() {
    context.read<DirektoriBloc>().add(const RefreshDirektori());
  }

  String _formatPercent(int part, int total) {
    if (total <= 0) return '0%';
    final pct = ((part / total) * 100).toStringAsFixed(1);
    return '$pct%';
  }

  void _showBatchInsertDialog() async {
    final textController = TextEditingController();
    bool isSaving = false;
    int successCount = 0;
    int failCount = 0;
    await showDialog<void>(
      context: context,
      barrierDismissible: !isSaving,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setState) => AlertDialog(
            title: const Text('Tambah Data (Batch)'),
            content: SizedBox(
              width: 600,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Format baris: nama\talamat\tlat,lng (opsional)\nPisah kolom dengan TAB atau koma. Contoh:\nToko A\tJl. Mawar No.1\t-4.0118, 119.6225',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: textController,
                    maxLines: 10,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Tempel data di sini atau ketik manual...',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: () async {
                          final data = await Clipboard.getData(
                            Clipboard.kTextPlain,
                          );
                          if (data?.text != null) {
                            setState(() {
                              textController.text = data!.text!;
                            });
                          }
                        },
                        icon: const Icon(Icons.content_paste),
                        label: const Text('Ambil dari Clipboard'),
                      ),
                      const Spacer(),
                      if (isSaving)
                        Row(
                          children: [
                            const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Menyimpan... (berhasil: $successCount, gagal: $failCount)',
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.of(ctx).pop(),
                child: const Text('Tutup'),
              ),
              ElevatedButton.icon(
                onPressed: isSaving
                    ? null
                    : () async {
                        setState(() {
                          isSaving = true;
                          successCount = 0;
                          failCount = 0;
                        });
                        final repo = MapRepositoryImpl();
                        final lines = textController.text
                            .split(RegExp(r'\r?\n'))
                            .where((l) => l.trim().isNotEmpty)
                            .toList();
                        for (final line in lines) {
                          try {
                            final parts = line
                                .split(RegExp(r'\t|\s*,\s*'))
                                .map((e) => e.trim())
                                .toList();
                            if (parts.isEmpty) continue;
                            final nama = parts[0];
                            final alamat = parts.length > 1 ? parts[1] : null;
                            double? lat;
                            double? lng;
                            if (parts.length > 2) {
                              final coordText = parts.sublist(2).join(',');
                              final m = RegExp(
                                r'^\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*$',
                              ).firstMatch(coordText);
                              if (m != null) {
                                lat = double.tryParse(m.group(1)!);
                                lng = double.tryParse(m.group(2)!);
                              }
                            }
                            // Buat model minimal
                            final model = DirektoriModel(
                              id: '',
                              idSbr: '0',
                              namaUsaha: nama,
                              alamat: alamat,
                              idSls: '',
                              latitude: lat,
                              longitude: lng,
                              keberadaanUsaha: 1,
                              createdAt: DateTime.now(),
                              updatedAt: DateTime.now(),
                            );
                            final newId = await repo.insertDirectoryAndGetId(
                              model,
                            );
                            if (newId == null) {
                              failCount++;
                              continue;
                            }
                            // Jika ada koordinat, perbarui regional
                            if (lat != null && lng != null) {
                              try {
                                final polygons = await repo
                                    .getAllPolygonsMetaFromGeoJson(
                                      'assets/geojson/final_sls.geojson',
                                    );
                                String idSls = '';
                                String? kodePos;
                                String? namaSls;
                                String kdProv = '';
                                String kdKab = '';
                                String kdKec = '';
                                String kdDesa = '';
                                String kdSls = '';
                                for (final polygon in polygons) {
                                  if (_isPointInPolygon(
                                    LatLng(lat, lng),
                                    polygon.points,
                                  )) {
                                    idSls = polygon.idsls ?? '';
                                    namaSls = polygon.name;
                                    kodePos = polygon.kodePos;
                                    if (idSls.isNotEmpty &&
                                        idSls.length >= 14) {
                                      kdProv = idSls.substring(0, 2);
                                      kdKab = idSls.substring(2, 4);
                                      kdKec = idSls.substring(4, 7);
                                      kdDesa = idSls.substring(7, 10);
                                      kdSls = idSls.substring(10, 14);
                                    }
                                    break;
                                  }
                                }
                                if (idSls.isNotEmpty) {
                                  await repo
                                      .updateDirectoryCoordinatesWithRegionalData(
                                        newId,
                                        lat,
                                        lng,
                                        idSls,
                                        kdProv,
                                        kdKab,
                                        kdKec,
                                        kdDesa,
                                        kdSls,
                                        kodePos,
                                        namaSls,
                                      );
                                }
                              } catch (_) {}
                            }
                            successCount++;
                            setState(() {});
                          } catch (_) {
                            failCount++;
                            setState(() {});
                          }
                        }
                        setState(() {
                          isSaving = false;
                        });
                        // Refresh list
                        _onRefresh();
                      },
                icon: const Icon(Icons.save_alt),
                label: const Text('Simpan Semua'),
              ),
            ],
          ),
        );
      },
    );
  }

  bool _isPointInPolygon(LatLng point, List<LatLng> polygon) {
    bool inside = false;
    for (int i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final xi = polygon[i].latitude;
      final yi = polygon[i].longitude;
      final xj = polygon[j].latitude;
      final yj = polygon[j].longitude;
      final intersect =
          ((yi > point.longitude) != (yj > point.longitude)) &&
          (point.latitude <
              (xj - xi) * (point.longitude - yi) / (yj - yi + 0.0) + xi);
      if (intersect) inside = !inside;
    }
    return inside;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.1),
                    spreadRadius: 1,
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.business, size: 24, color: Colors.blue),
                      const SizedBox(width: 8),
                      const Text(
                        'Direktori Usaha',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: _onRefresh,
                        icon: const Icon(Icons.refresh),
                        tooltip: 'Refresh',
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () async {
                          final res = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => const BatchInsertDialog(),
                          );
                          if (res == true) {
                            _onRefresh();
                          }
                        },
                        icon: const Icon(Icons.add_box_outlined),
                        tooltip: 'Tambah Data (batch)',
                      ),
                      const SizedBox(width: 8),
                      Tooltip(
                        message: _showStats
                            ? 'Sembunyikan Statistik'
                            : 'Tampilkan Statistik',
                        child: IconButton(
                          onPressed: () {
                            setState(() {
                              _showStats = !_showStats;
                            });
                          },
                          icon: Icon(
                            _showStats
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Tooltip(
                        message: 'Muat semua',
                        child: IconButton(
                          onPressed: () {
                            context.read<DirektoriBloc>().add(
                              const LoadAllDirektori(),
                            );
                          },
                          icon: const Icon(Icons.download),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DirektoriSearchBar(
                    controller: _searchController,
                    onSearch: _onSearch,
                  ),
                  const SizedBox(height: 8),
                  BlocBuilder<DirektoriBloc, DirektoriState>(
                    builder: (context, state) {
                      bool include = false;
                      Map<String, int>? stats;
                      if (state is DirektoriLoaded) {
                        include = state.includeCoordinates;
                        stats = state.stats;
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox.shrink(),
                          const SizedBox(height: 8),
                          if (_showStats && stats != null)
                            Row(
                              children: [
                                _StatCard(
                                  title: 'Jumlah Usaha',
                                  value: stats!['total']?.toString() ?? '0',
                                  color: Colors.blue[50]!,
                                ),
                                const SizedBox(width: 8),
                                _StatCard(
                                  title: 'Jumlah Aktif',
                                  value: stats!['aktif']?.toString() ?? '0',
                                  color: Colors.green[50]!,
                                ),
                                const SizedBox(width: 8),
                                _StatCard(
                                  title: 'Jumlah Updated',
                                  value: stats!['updated']?.toString() ?? '0',
                                  color: Colors.orange[50]!,
                                ),
                                const SizedBox(width: 8),
                                _StatCard(
                                  title: 'Aktif: Koordinat (%)',
                                  value: _formatPercent(
                                    stats!['aktif_with_coord'] ?? 0,
                                    stats!['aktif'] ?? 0,
                                  ),
                                  small:
                                      '${stats!['aktif_with_coord'] ?? 0} dari ${stats!['aktif'] ?? 0}',
                                  color: Colors.teal[50]!,
                                ),
                                const SizedBox(width: 8),
                                _StatCard(
                                  title: 'Aktif: Tanpa Koordinat (%)',
                                  value: _formatPercent(
                                    stats!['aktif_without_coord'] ?? 0,
                                    stats!['aktif'] ?? 0,
                                  ),
                                  small:
                                      '${stats!['aktif_without_coord'] ?? 0} dari ${stats!['aktif'] ?? 0}',
                                  color: Colors.red[50]!,
                                ),
                              ],
                            ),
                          const SizedBox(height: 8),
                          if (state is DirektoriLoaded &&
                              state.direktoriList.isNotEmpty)
                            Row(
                              children: [
                                Expanded(
                                  child: LayoutBuilder(
                                    builder: (ctx, constraints) {
                                      final letters =
                                          '#ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split(
                                            '',
                                          );
                                      final Map<String, int> counts = {
                                        for (final ch in letters) ch: 0,
                                      };
                                      for (final d in state.direktoriList) {
                                        final n = (d.namaUsaha).trim();
                                        if (n.isEmpty) continue;
                                        final first = n[0].toUpperCase();
                                        final isAlpha = RegExp(
                                          r'^[A-Z]',
                                        ).hasMatch(first);
                                        final key = isAlpha ? first : '#';
                                        if (counts.containsKey(key)) {
                                          counts[key] = (counts[key] ?? 0) + 1;
                                        }
                                      }
                                      return SizedBox(
                                        width: constraints.maxWidth,
                                        child: Row(
                                          children: letters
                                              .map(
                                                (ch) => Expanded(
                                                  child: Padding(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 3,
                                                        ),
                                                    child: InkWell(
                                                      onTap: () {
                                                        setState(() {
                                                          _selectedLetter = ch;
                                                        });
                                                        final idx = state
                                                            .direktoriList
                                                            .indexWhere((d) {
                                                              final n =
                                                                  (d.namaUsaha)
                                                                      .trim();
                                                              if (n.isEmpty)
                                                                return false;
                                                              final first = n[0]
                                                                  .toUpperCase();
                                                              final isAlpha =
                                                                  RegExp(
                                                                    r'^[A-Z]',
                                                                  ).hasMatch(
                                                                    first,
                                                                  );
                                                              if (ch == '#')
                                                                return !isAlpha;
                                                              return first ==
                                                                  ch;
                                                            });
                                                        if (idx >= 0) {
                                                          _scrollController.animateTo(
                                                            idx * 64.0,
                                                            duration:
                                                                const Duration(
                                                                  milliseconds:
                                                                      300,
                                                                ),
                                                            curve:
                                                                Curves.easeOut,
                                                          );
                                                        } else {
                                                          ScaffoldMessenger.of(
                                                            context,
                                                          ).showSnackBar(
                                                            SnackBar(
                                                              content: Text(
                                                                ch == '#'
                                                                    ? 'Tidak ada nama non-alfabet dalam halaman yang dimuat'
                                                                    : 'Tidak ada nama berawalan "$ch" dalam halaman yang dimuat',
                                                              ),
                                                              duration:
                                                                  const Duration(
                                                                    milliseconds:
                                                                        800,
                                                                  ),
                                                            ),
                                                          );
                                                        }
                                                      },
                                                      child: Container(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              vertical: 8,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color:
                                                              (_selectedLetter ==
                                                                  ch)
                                                              ? Colors
                                                                    .orange[300]
                                                              : Colors
                                                                    .orange[50],
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                8,
                                                              ),
                                                          border: Border.all(
                                                            color:
                                                                (_selectedLetter ==
                                                                    ch)
                                                                ? Colors.orange
                                                                : Colors
                                                                      .orangeAccent
                                                                      .withOpacity(
                                                                        0.3,
                                                                      ),
                                                          ),
                                                        ),
                                                        child: Column(
                                                          mainAxisSize:
                                                              MainAxisSize.min,
                                                          children: [
                                                            Text(
                                                              ch,
                                                              style: const TextStyle(
                                                                fontSize: 13,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                color: Colors
                                                                    .black87,
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                              height: 6,
                                                            ),
                                                            Container(
                                                              padding:
                                                                  const EdgeInsets.symmetric(
                                                                    horizontal:
                                                                        8,
                                                                    vertical: 2,
                                                                  ),
                                                              decoration: BoxDecoration(
                                                                color: Colors
                                                                    .blue[50],
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                      12,
                                                                    ),
                                                                border: Border.all(
                                                                  color: Colors
                                                                      .blueAccent
                                                                      .withOpacity(
                                                                        0.4,
                                                                      ),
                                                                ),
                                                              ),
                                                              child: Text(
                                                                (counts[ch] ??
                                                                        0)
                                                                    .toString(),
                                                                style: TextStyle(
                                                                  fontSize: 11,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                  color: Colors
                                                                      .blue[700],
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              )
                                              .toList(),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          const SizedBox(height: 8),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
            // Content
            Expanded(
              child: BlocBuilder<DirektoriBloc, DirektoriState>(
                builder: (context, state) {
                  if (state is DirektoriLoading) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (state is DirektoriError) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 64,
                            color: Colors.red[300],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Terjadi kesalahan',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[700],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            state.message,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _onRefresh,
                            child: const Text('Coba Lagi'),
                          ),
                        ],
                      ),
                    );
                  }

                  if (state is DirektoriLoaded) {
                    if (state.direktoriList.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.business_outlined,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              state.currentSearch?.isNotEmpty == true
                                  ? 'Tidak ada hasil untuk "${state.currentSearch}"'
                                  : 'Belum ada data direktori',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[600],
                              ),
                            ),
                            if (state.currentSearch?.isNotEmpty == true) ...[
                              const SizedBox(height: 8),
                              TextButton(
                                onPressed: () {
                                  _searchController.clear();
                                  _onSearch('');
                                },
                                child: const Text('Hapus pencarian'),
                              ),
                            ],
                          ],
                        ),
                      );
                    }

                    return Column(
                      children: [
                        // Results info
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              if (state.currentSearch?.isNotEmpty == true) ...[
                                const SizedBox(width: 8),
                                Chip(
                                  label: Text(
                                    'Pencarian: ${state.currentSearch}',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  onDeleted: () {
                                    _searchController.clear();
                                    _onSearch('');
                                  },
                                  deleteIcon: const Icon(Icons.close, size: 16),
                                ),
                              ],
                            ],
                          ),
                        ),
                        // Table
                        Expanded(
                          child: DirektoriDataGrid(
                            direktoriList: state.direktoriList,
                            scrollController: _scrollController,
                            isLoadingMore: state.isLoadingMore,
                            hasReachedMax: state.hasReachedMax,
                            sortColumn: state.sortColumn,
                            sortAscending: state.sortAscending,
                            onRequestSort: (column, ascending) {
                              context.read<DirektoriBloc>().add(
                                SortDirektori(
                                  column: column,
                                  ascending: ascending,
                                ),
                              );
                            },
                            onGoToMap: widget.onNavigateToMap,
                            onRowUpdated: () {
                              context.read<DirektoriBloc>().add(
                                const RefreshDirektoriHeader(),
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  }

                  return const SizedBox.shrink();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final String? small;
  final Color color;
  const _StatCard({
    required this.title,
    required this.value,
    this.small,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.black12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            if (small != null) ...[
              const SizedBox(height: 4),
              Text(
                small!,
                style: TextStyle(fontSize: 11, color: Colors.grey[700]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
