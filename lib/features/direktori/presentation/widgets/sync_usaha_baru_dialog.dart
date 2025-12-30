import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:latlong2/latlong.dart';
import '../../../../core/config/supabase_config.dart';
import '../../../map/data/repositories/map_repository_impl.dart';
import '../../../map/data/models/direktori_model.dart';

// Singleton untuk menyimpan state dialog
class SyncDataManager {
  static final SyncDataManager _instance = SyncDataManager._internal();
  factory SyncDataManager() => _instance;
  SyncDataManager._internal();

  List<_SyncRow> rowsData = [];

  void clear() {
    rowsData.clear();
  }
}

class SyncUsahaBaruDialog extends StatefulWidget {
  const SyncUsahaBaruDialog({Key? key}) : super(key: key);

  @override
  State<SyncUsahaBaruDialog> createState() => _SyncUsahaBaruDialogState();
}

class _SyncUsahaBaruDialogState extends State<SyncUsahaBaruDialog> {
  late final _SyncDataSource _source;
  final SupabaseClient _supabaseClient = SupabaseConfig.client;

  bool _isProcessing = false;
  bool _isMatching = false;
  bool _isSyncing = false;
  bool _isInserting = false;
  int _successCount = 0;
  int _failCount = 0;
  int _notFoundCount = 0;
  int _matchedCount = 0;
  int _duplicateCount = 0;
  _FilterMode _filterMode = _FilterMode.all;

  @override
  void initState() {
    super.initState();
    // Gunakan data dari Singleton
    _source = _SyncDataSource(
      rowsData: SyncDataManager().rowsData,
      onRemove: _removeSingleByNo,
      onResync: _resyncSingleByNo,
      onReview: _reviewSingleByNo,
      onInsertNotFound: _insertSingleNotFound,
      onSetCoords: _inputCoordinatesForRow,
    );
    _recalculateCounts();
  }

  void _recalculateCounts() {
    _successCount = 0;
    _failCount = 0;
    _notFoundCount = 0;
    _matchedCount = 0;
    _duplicateCount = 0;
    for (final r in _source.rowsData) {
      if (r.status == _SyncStatus.success) _successCount++;
      if (r.status == _SyncStatus.error) _failCount++;
      if (r.status == _SyncStatus.notFound) _notFoundCount++;
      if (r.status == _SyncStatus.matched) _matchedCount++;
      if (r.status == _SyncStatus.duplicate) _duplicateCount++;
    }
  }

  Future<void> _runMatching() async {
    setState(() {
      _isMatching = true;
      _matchedCount = 0;
      _notFoundCount = 0;
    });
    _source.isBusy = true;
    _source.updateDataGrid();

    final rows = _source.rowsData;
    for (final row in rows) {
      if (row.status == _SyncStatus.success) continue;

      row.status = _SyncStatus.processing;
      row.message = 'Matching...';
      _source.updateDataGrid();

      try {
        final responses = await _supabaseClient
            .from('direktori')
            .select('id, nama_usaha, alamat, id_sbr')
            .ilike('nama_usaha', row.namaUsaha);

        if (responses.isEmpty) {
          row.status = _SyncStatus.notFound;
          row.message = 'Tidak ditemukan';
          row.foundIdSbr = '-';
          _notFoundCount++;
        } else if (responses.length == 1) {
          row.status = _SyncStatus.matched;
          row.message = 'Cocok';
          try {
            final v = responses.first['id_sbr'];
            row.foundIdSbr = (v == null) ? '-' : v.toString();
          } catch (_) {
            row.foundIdSbr = '-';
          }
          _matchedCount++;
        } else {
          row.status = _SyncStatus.duplicate;
          row.message = 'Duplikat nama usaha: ${responses.length} hasil';
          row.foundIdSbr = 'MULTI';
          _duplicateCount++;
        }
      } catch (e) {
        row.status = _SyncStatus.error;
        row.message = 'Error: $e';
        _failCount++;
      }
      _source.updateDataGrid();
    }

    setState(() {
      _isMatching = false;
    });
    _source.isBusy = false;
    _source.updateDataGrid();
  }

  Future<void> _startSync() async {
    setState(() {
      _isSyncing = true;
      _successCount = 0;
      _failCount = 0;
    });
    _source.isBusy = true;
    _source.updateDataGrid();

    final rows = _source.rowsData
        .where((r) => r.status == _SyncStatus.matched)
        .toList();
    for (final row in rows) {
      row.status = _SyncStatus.processing;
      row.message = 'Mengubah ID SBR...';
      _source.updateDataGrid();
      try {
        final selectedId = row.selectedId;
        if (selectedId != null) {
          final id = selectedId;
          await _supabaseClient
              .from('direktori')
              .update({
                'id_sbr': row.newIdSbr,
                'updated_at': DateTime.now().toIso8601String(),
              })
              .eq('id', id);
          row.status = _SyncStatus.success;
          row.message = 'Berhasil update';
          row.foundIdSbr = row.newIdSbr;
          _successCount++;
        } else {
          final responses = await _supabaseClient
              .from('direktori')
              .select('id, nama_usaha, alamat')
              .ilike('nama_usaha', row.namaUsaha);
          if (responses.isEmpty) {
            row.status = _SyncStatus.notFound;
            row.message = 'Tidak ditemukan saat sync';
            row.foundIdSbr = '-';
            _notFoundCount++;
          } else if (responses.length == 1) {
            final id = responses.first['id'];
            await _supabaseClient
                .from('direktori')
                .update({
                  'id_sbr': row.newIdSbr,
                  'updated_at': DateTime.now().toIso8601String(),
                })
                .eq('id', id);
            row.status = _SyncStatus.success;
            row.message = 'Berhasil update';
            row.foundIdSbr = row.newIdSbr;
            _successCount++;
          } else {
            row.status = _SyncStatus.duplicate;
            row.message = 'Duplikat saat sync: ${responses.length} hasil';
            row.foundIdSbr = 'MULTI';
            _duplicateCount++;
          }
        }
      } catch (e) {
        row.status = _SyncStatus.error;
        row.message = 'Error: $e';
        _failCount++;
      }
      _source.updateDataGrid();
    }

    setState(() {
      _isSyncing = false;
    });
    _source.isBusy = false;
    _source.updateDataGrid();
  }

  void _removeSingleByNo(int no) {
    final removed = _source.removeByNo(no);
    if (removed == null) return;
    _recalculateCounts();
    setState(() {});
  }

  Future<void> _resyncSingleByNo(int no) async {
    final row = _source.findByNo(no);
    if (row == null) return;

    // Decrement counts temporarily
    if (row.status == _SyncStatus.matched) _matchedCount--;
    if (row.status == _SyncStatus.success) _successCount--;
    if (row.status == _SyncStatus.error) _failCount--;
    if (row.status == _SyncStatus.notFound) _notFoundCount--;
    if (row.status == _SyncStatus.duplicate) _duplicateCount--;

    row.status = _SyncStatus.processing;
    row.message = 'Matching & sinkron ulang...';
    _source.updateDataGrid();
    try {
      final selectedId = row.selectedId;
      if (selectedId != null) {
        final id = selectedId;
        await _supabaseClient
            .from('direktori')
            .update({
              'id_sbr': row.newIdSbr,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', id);
        row.status = _SyncStatus.success;
        row.message = 'Berhasil update';
        row.foundIdSbr = row.newIdSbr;
        _successCount++;
      } else {
        final responses = await _supabaseClient
            .from('direktori')
            .select('id, nama_usaha, alamat, id_sbr')
            .ilike('nama_usaha', row.namaUsaha);
        if (responses.isEmpty) {
          row.status = _SyncStatus.notFound;
          row.message = 'Tidak ditemukan';
          row.foundIdSbr = '-';
          _notFoundCount++;
        } else if (responses.length == 1) {
          final id = responses.first['id'];
          await _supabaseClient
              .from('direktori')
              .update({
                'id_sbr': row.newIdSbr,
                'updated_at': DateTime.now().toIso8601String(),
              })
              .eq('id', id);
          row.status = _SyncStatus.success;
          row.message = 'Berhasil update';
          row.foundIdSbr = row.newIdSbr;
          _successCount++;
        } else {
          row.status = _SyncStatus.duplicate;
          row.message = 'Duplikat nama usaha: ${responses.length} hasil';
          row.foundIdSbr = 'MULTI';
          _duplicateCount++;
        }
      }
    } catch (e) {
      row.status = _SyncStatus.error;
      row.message = 'Error: $e';
      _failCount++;
    }
    _source.updateDataGrid();
    setState(() {});
  }

  Future<void> _insertNotFound() async {
    setState(() {
      _isInserting = true;
    });
    _source.isBusy = true;
    _source.updateDataGrid();
    final rows = _source.rowsData
        .where((r) => r.status == _SyncStatus.notFound)
        .toList();
    for (final row in rows) {
      row.status = _SyncStatus.processing;
      row.message = 'Menambahkan ke direktori...';
      _source.updateDataGrid();
      try {
        double? lat = row.lat;
        double? lng = row.lng;
        String idSls = '';
        String? kodePos;
        String? namaSls;
        String kdProv = '';
        String kdKab = '';
        String kdKec = '';
        String kdDesa = '';
        String kdSls = '';
        if (lat != null && lng != null) {
          try {
            final repo = MapRepositoryImpl();
            final polygons = await repo.getAllPolygonsMetaFromGeoJson(
              'assets/geojson/final_sls.geojson',
            );
            for (final polygon in polygons) {
              if (_isPointInPolygon(LatLng(lat, lng), polygon.points)) {
                idSls = polygon.idsls ?? '';
                namaSls = polygon.name;
                kodePos = polygon.kodePos;
                if (idSls.isNotEmpty && idSls.length >= 14) {
                  kdProv = idSls.substring(0, 2);
                  kdKab = idSls.substring(2, 4);
                  kdKec = idSls.substring(4, 7);
                  kdDesa = idSls.substring(7, 10);
                  kdSls = idSls.substring(10, 14);
                }
                break;
              }
            }
          } catch (_) {}
        }
        final newId = await MapRepositoryImpl().insertDirectoryAndGetId(
          DirektoriModel(
            id: '',
            idSbr: row.newIdSbr,
            namaUsaha: row.namaUsaha,
            alamat: row.alamat,
            idSls: idSls,
            latitude: idSls.isNotEmpty ? lat : null,
            longitude: idSls.isNotEmpty ? lng : null,
            kdProv: kdProv.isNotEmpty ? kdProv : null,
            kdKab: kdKab.isNotEmpty ? kdKab : null,
            kdKec: kdKec.isNotEmpty ? kdKec : null,
            kdDesa: kdDesa.isNotEmpty ? kdDesa : null,
            kdSls: kdSls.isNotEmpty ? kdSls : null,
            kodePos: kodePos,
            nmSls: namaSls,
            keberadaanUsaha: 1,
            createdAt: DateTime.now().toUtc(),
            updatedAt: DateTime.now().toUtc(),
          ),
        );
        if (newId == null) {
          throw Exception('Insert gagal (ID tidak diperoleh)');
        }
        row.status = _SyncStatus.success;
        row.message = 'Ditambahkan ke direktori (ID: $newId)';
        row.foundIdSbr = row.newIdSbr;
        _successCount++;
        _notFoundCount--;
      } catch (e) {
        row.status = _SyncStatus.error;
        row.message = 'Error tambah: $e';
        _failCount++;
      }
      _source.updateDataGrid();
    }
    setState(() {
      _isInserting = false;
    });
    _source.isBusy = false;
    _recalculateCounts();
    _source.updateDataGrid();
  }

  Future<void> _insertSingleNotFound(int no) async {
    final row = _source.findByNo(no);
    if (row == null || row.status != _SyncStatus.notFound) return;
    _source.isBusy = true;
    _source.updateDataGrid();
    row.status = _SyncStatus.processing;
    row.message = 'Menambahkan ke direktori...';
    _source.updateDataGrid();
    try {
      double? lat = row.lat;
      double? lng = row.lng;
      String idSls = '';
      String? kodePos;
      String? namaSls;
      String kdProv = '';
      String kdKab = '';
      String kdKec = '';
      String kdDesa = '';
      String kdSls = '';
      if (lat != null && lng != null) {
        try {
          final repo = MapRepositoryImpl();
          final polygons = await repo.getAllPolygonsMetaFromGeoJson(
            'assets/geojson/final_sls.geojson',
          );
          for (final polygon in polygons) {
            if (_isPointInPolygon(LatLng(lat, lng), polygon.points)) {
              idSls = polygon.idsls ?? '';
              namaSls = polygon.name;
              kodePos = polygon.kodePos;
              if (idSls.isNotEmpty && idSls.length >= 14) {
                kdProv = idSls.substring(0, 2);
                kdKab = idSls.substring(2, 4);
                kdKec = idSls.substring(4, 7);
                kdDesa = idSls.substring(7, 10);
                kdSls = idSls.substring(10, 14);
              }
              break;
            }
          }
        } catch (_) {}
      }
      final newId = await MapRepositoryImpl().insertDirectoryAndGetId(
        DirektoriModel(
          id: '',
          idSbr: row.newIdSbr,
          namaUsaha: row.namaUsaha,
          alamat: row.alamat,
          idSls: idSls,
          latitude: idSls.isNotEmpty ? lat : null,
          longitude: idSls.isNotEmpty ? lng : null,
          kdProv: kdProv.isNotEmpty ? kdProv : null,
          kdKab: kdKab.isNotEmpty ? kdKab : null,
          kdKec: kdKec.isNotEmpty ? kdKec : null,
          kdDesa: kdDesa.isNotEmpty ? kdDesa : null,
          kdSls: kdSls.isNotEmpty ? kdSls : null,
          kodePos: kodePos,
          nmSls: namaSls,
          keberadaanUsaha: 1,
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
        ),
      );
      if (newId == null) {
        throw Exception('Insert gagal (ID tidak diperoleh)');
      }
      row.status = _SyncStatus.success;
      row.message = 'Ditambahkan ke direktori (ID: $newId)';
      row.foundIdSbr = row.newIdSbr;
      _successCount++;
      _notFoundCount--;
    } catch (e) {
      row.status = _SyncStatus.error;
      row.message = 'Error tambah: $e';
      _failCount++;
    }
    _source.isBusy = false;
    _recalculateCounts();
    _source.updateDataGrid();
    setState(() {});
  }

  Future<void> _inputCoordinatesForRow(int no) async {
    final row = _source.findByNo(no);
    if (row == null) return;
    final latController = TextEditingController(
      text: row.lat?.toString() ?? '',
    );
    final lngController = TextEditingController(
      text: row.lng?.toString() ?? '',
    );
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Masukkan Koordinat'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: latController,
                  decoration: const InputDecoration(
                    labelText: 'Latitude (-90..90)',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: lngController,
                  decoration: const InputDecoration(
                    labelText: 'Longitude (-180..180)',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Simpan'),
            ),
          ],
        );
      },
    );
    if (result == true) {
      final lat = double.tryParse(latController.text.trim());
      final lng = double.tryParse(lngController.text.trim());
      if (lat == null ||
          lng == null ||
          lat < -90 ||
          lat > 90 ||
          lng < -180 ||
          lng > 180) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Koordinat tidak valid')));
        return;
      }
      row.lat = lat;
      row.lng = lng;
      row.message = 'Koordinat diset';
      _source.updateDataGrid();
      setState(() {});
    }
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

  Future<void> _reviewSingleByNo(int no) async {
    final row = _source.findByNo(no);
    if (row == null) return;
    _source.isBusy = true;
    _source.updateDataGrid();
    try {
      final responses = await _supabaseClient
          .from('direktori')
          .select('id, nama_usaha, alamat, id_sbr')
          .eq('id_sbr', '0')
          .ilike('nama_usaha', row.namaUsaha);
      if (!mounted) return;
      var items = List<Map<String, dynamic>>.from(responses);
      final selectedId = await showDialog<Object>(
        context: context,
        builder: (ctx) {
          return StatefulBuilder(
            builder: (ctx, setStateDialog) {
              return AlertDialog(
                title: const Text('Pilih kandidat'),
                content: SizedBox(
                  width: 500,
                  height: 300,
                  child: ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (c, i) {
                      final item = items[i];
                      final nama = item['nama_usaha']?.toString() ?? '';
                      final alamat = item['alamat']?.toString() ?? '';
                      return ListTile(
                        title: Text(nama),
                        subtitle: Text(alamat),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(
                              onPressed: () {
                                final rawId = item['id'];
                                Navigator.of(ctx).pop(rawId);
                              },
                              child: const Text('Pilih'),
                            ),
                            IconButton(
                              tooltip: 'Hapus data',
                              onPressed: () async {
                                final rawId = item['id'];
                                try {
                                  if (rawId == null) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'ID kandidat tidak valid',
                                        ),
                                      ),
                                    );
                                    return;
                                  }
                                  await _supabaseClient
                                      .from('direktori')
                                      .delete()
                                      .eq('id', rawId);
                                  setStateDialog(() {
                                    items.removeAt(i);
                                  });
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Data kandidat dihapus'),
                                    ),
                                  );
                                } catch (_) {}
                              },
                              icon: const Icon(Icons.delete, color: Colors.red),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Batal'),
                  ),
                ],
              );
            },
          );
        },
      );
      if (selectedId != null) {
        if (row.status == _SyncStatus.duplicate) {
          _duplicateCount--;
        }
        row.selectedId = selectedId;
        row.status = _SyncStatus.matched;
        row.message = 'Dipilih manual (ID: ${selectedId.toString()})';
        try {
          final matched = items.firstWhere(
            (it) => it['id'] == selectedId,
            orElse: () => {},
          );
          final v = matched['id_sbr'];
          row.foundIdSbr = (v == null) ? '-' : v.toString();
        } catch (_) {
          row.foundIdSbr = '-';
        }
        _matchedCount++;
        _recalculateCounts();
        _source.updateDataGrid();
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kandidat dipilih: ID $selectedId')),
        );
      }
    } catch (_) {}
    _source.isBusy = false;
    _source.updateDataGrid();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Sinkronisasi ID SBR (Batch)'),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.95,
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Row(
              children: [
                TextButton.icon(
                  onPressed: _isProcessing
                      ? null
                      : () async {
                          final data = await Clipboard.getData(
                            Clipboard.kTextPlain,
                          );
                          if (data?.text != null) {
                            _source.parseClipboard(data!.text!);
                            _recalculateCounts(); // Update counts for new rows (usually 0 but good practice)
                            setState(() {});
                          }
                        },
                  icon: const Icon(Icons.paste),
                  label: const Text('Ambil dari Clipboard'),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _isProcessing
                      ? null
                      : () {
                          _source.clear();
                          SyncDataManager().clear(); // Clear singleton too
                          _recalculateCounts();
                          setState(() {});
                        },
                  icon: const Icon(Icons.clear_all),
                  label: const Text('Bersihkan'),
                ),
                const Spacer(),
                DropdownButton<_FilterMode>(
                  value: _filterMode,
                  onChanged:
                      (_isProcessing ||
                          _isMatching ||
                          _isSyncing ||
                          _isInserting)
                      ? null
                      : (v) {
                          if (v == null) return;
                          _filterMode = v;
                          _source.setFilter(v);
                          _source.updateDataGrid();
                          setState(() {});
                        },
                  items: const [
                    DropdownMenuItem(
                      value: _FilterMode.all,
                      child: Text('Semua'),
                    ),
                    DropdownMenuItem(
                      value: _FilterMode.nonMatched,
                      child: Text('Selain Cocok'),
                    ),
                    DropdownMenuItem(
                      value: _FilterMode.duplicate,
                      child: Text('Duplikat'),
                    ),
                    DropdownMenuItem(
                      value: _FilterMode.notFound,
                      child: Text('Tidak Ada'),
                    ),
                    DropdownMenuItem(
                      value: _FilterMode.error,
                      child: Text('Error'),
                    ),
                    DropdownMenuItem(
                      value: _FilterMode.success,
                      child: Text('Sukses'),
                    ),
                  ],
                ),
                if (_source.rowsData.isNotEmpty)
                  Text(
                    'Total: ${_source.rowsData.length} | Matched: $_matchedCount | Duplikat: $_duplicateCount | Sukses: $_successCount | Gagal: $_failCount | Tidak Ada: $_notFoundCount',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Format Clipboard: Nama Usaha [TAB] Alamat [TAB] ID SBR Baru [TAB] Lat [TAB] Lng (opsional)',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: SfDataGrid(
                source: _source,
                columnWidthMode: ColumnWidthMode.fill,
                gridLinesVisibility: GridLinesVisibility.both,
                headerGridLinesVisibility: GridLinesVisibility.both,
                columns: [
                  GridColumn(
                    columnName: 'no',
                    width: 60,
                    label: const _HeaderCell(title: 'No'),
                  ),
                  GridColumn(
                    columnName: 'nama',
                    label: const _HeaderCell(title: 'Nama Usaha'),
                  ),
                  GridColumn(
                    columnName: 'alamat',
                    width: 240,
                    label: const _HeaderCell(title: 'Alamat'),
                  ),
                  GridColumn(
                    columnName: 'lat',
                    width: 120,
                    label: const _HeaderCell(title: 'Latitude'),
                  ),
                  GridColumn(
                    columnName: 'lng',
                    width: 120,
                    label: const _HeaderCell(title: 'Longitude'),
                  ),
                  GridColumn(
                    columnName: 'id_sbr',
                    width: 150,
                    label: const _HeaderCell(title: 'ID SBR Baru'),
                  ),
                  GridColumn(
                    columnName: 'id_sbr_found',
                    width: 150,
                    label: const _HeaderCell(title: 'ID SBR Ditemukan'),
                  ),
                  GridColumn(
                    columnName: 'status',
                    width: 120,
                    label: const _HeaderCell(title: 'Status'),
                  ),
                  GridColumn(
                    columnName: 'pesan',
                    width: 200,
                    label: const _HeaderCell(title: 'Keterangan'),
                  ),
                  GridColumn(
                    columnName: 'aksi',
                    width: 200,
                    label: const _HeaderCell(title: 'Aksi'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: (_isMatching || _isSyncing || _isInserting)
              ? null
              : () => Navigator.of(context).pop(true),
          child: const Text('Tutup'),
        ),
        ElevatedButton.icon(
          onPressed:
              _isInserting ||
                  !_source.rowsData.any((r) => r.status == _SyncStatus.notFound)
              ? null
              : _insertNotFound,
          icon: _isInserting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.playlist_add),
          label: Text(
            _isInserting ? 'Menambahkan...' : 'Masukkan yg Tidak Ada',
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.teal,
            foregroundColor: Colors.white,
          ),
        ),
        ElevatedButton.icon(
          onPressed: _isMatching || _source.rowsData.isEmpty
              ? null
              : _runMatching,
          icon: _isMatching
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.rule),
          label: Text(_isMatching ? 'Matching...' : 'Proses Matching'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            foregroundColor: Colors.white,
          ),
        ),
        ElevatedButton.icon(
          onPressed: _isSyncing || _matchedCount == 0 ? null : _startSync,
          icon: _isSyncing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.sync),
          label: Text(_isSyncing ? 'Menyinkron...' : 'Mulai Sinkronisasi'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}

enum _SyncStatus {
  pending,
  processing,
  matched,
  success,
  error,
  notFound,
  duplicate,
}

enum _FilterMode { all, nonMatched, duplicate, notFound, error, success }

class _SyncRow {
  final int no;
  final String namaUsaha;
  final String alamat;
  final String newIdSbr;
  _SyncStatus status;
  String message;
  Object? selectedId;
  String foundIdSbr;
  double? lat;
  double? lng;

  _SyncRow({
    required this.no,
    required this.namaUsaha,
    required this.alamat,
    required this.newIdSbr,
    this.status = _SyncStatus.pending,
    this.message = '-',
    this.selectedId,
    this.foundIdSbr = '-',
    this.lat,
    this.lng,
  });
}

class _SyncDataSource extends DataGridSource {
  List<_SyncRow> rowsData;
  final void Function(int no) onRemove;
  final Future<void> Function(int no) onResync;
  final Future<void> Function(int no) onReview;
  final Future<void> Function(int no)? onInsertNotFound;
  final Future<void> Function(int no)? onSetCoords;
  bool isBusy = false;
  _FilterMode filterMode = _FilterMode.all;

  _SyncDataSource({
    required this.rowsData,
    required this.onRemove,
    required this.onResync,
    required this.onReview,
    required this.onInsertNotFound,
    required this.onSetCoords,
  });

  void parseClipboard(String text) {
    final lines = text
        .split(RegExp(r'\r?\n'))
        .where((l) => l.trim().isNotEmpty)
        .toList();
    // Start numbering from last max no + 1 or 1
    int startNo = 1;
    if (rowsData.isNotEmpty) {
      startNo = rowsData.map((e) => e.no).reduce((a, b) => a > b ? a : b) + 1;
    }

    for (final line in lines) {
      final parts = line.split(RegExp(r'\t')).map((e) => e.trim()).toList();
      final finalParts = parts.length >= 3
          ? parts
          : line.split(RegExp(r',')).map((e) => e.trim()).toList();

      if (finalParts.length >= 3) {
        double? lat;
        double? lng;
        if (finalParts.length >= 5) {
          lat = double.tryParse(finalParts[3]);
          lng = double.tryParse(finalParts[4]);
        } else if (finalParts.length == 4) {
          final coordText = finalParts[3];
          final m = RegExp(
            r'^\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*$',
          ).firstMatch(coordText);
          if (m != null) {
            lat = double.tryParse(m.group(1)!);
            lng = double.tryParse(m.group(2)!);
          }
        }
        rowsData.add(
          _SyncRow(
            no: startNo++,
            namaUsaha: finalParts[0],
            alamat: finalParts[1],
            newIdSbr: finalParts[2],
            lat: lat,
            lng: lng,
          ),
        );
      }
    }
    notifyListeners();
  }

  void clear() {
    rowsData.clear();
    notifyListeners();
  }

  void updateDataGrid() {
    notifyListeners();
  }

  _SyncRow? findByNo(int no) {
    for (final r in rowsData) {
      if (r.no == no) return r;
    }
    return null;
  }

  _SyncRow? removeByNo(int no) {
    final idx = rowsData.indexWhere((r) => r.no == no);
    if (idx >= 0) {
      final removed = rowsData.removeAt(idx);
      notifyListeners();
      return removed;
    }
    return null;
  }

  void setFilter(_FilterMode mode) {
    filterMode = mode;
  }

  @override
  List<DataGridRow> get rows {
    Iterable<_SyncRow> items = rowsData;
    switch (filterMode) {
      case _FilterMode.all:
        break;
      case _FilterMode.nonMatched:
        items = items.where(
          (e) =>
              e.status != _SyncStatus.matched &&
              e.status != _SyncStatus.success,
        );
        break;
      case _FilterMode.duplicate:
        items = items.where((e) => e.status == _SyncStatus.duplicate);
        break;
      case _FilterMode.notFound:
        items = items.where((e) => e.status == _SyncStatus.notFound);
        break;
      case _FilterMode.error:
        items = items.where((e) => e.status == _SyncStatus.error);
        break;
      case _FilterMode.success:
        items = items.where((e) => e.status == _SyncStatus.success);
        break;
    }
    return items.map<DataGridRow>((e) {
      return DataGridRow(
        cells: [
          DataGridCell<int>(columnName: 'no', value: e.no),
          DataGridCell<String>(columnName: 'nama', value: e.namaUsaha),
          DataGridCell<String>(columnName: 'alamat', value: e.alamat),
          DataGridCell<String>(
            columnName: 'lat',
            value: e.lat?.toString() ?? '',
          ),
          DataGridCell<String>(
            columnName: 'lng',
            value: e.lng?.toString() ?? '',
          ),
          DataGridCell<String>(columnName: 'id_sbr', value: e.newIdSbr),
          DataGridCell<String>(columnName: 'id_sbr_found', value: e.foundIdSbr),
          DataGridCell<_SyncStatus>(columnName: 'status', value: e.status),
          DataGridCell<String>(columnName: 'pesan', value: e.message),
          DataGridCell<String>(columnName: 'aksi', value: ''),
        ],
      );
    }).toList();
  }

  @override
  DataGridRowAdapter buildRow(DataGridRow row) {
    final status =
        row.getCells().firstWhere((c) => c.columnName == 'status').value
            as _SyncStatus;
    final no =
        row.getCells().firstWhere((c) => c.columnName == 'no').value as int;
    Color? rowColor;
    if (status == _SyncStatus.matched) rowColor = Colors.blue[50];
    if (status == _SyncStatus.success) rowColor = Colors.green[50];
    if (status == _SyncStatus.error) rowColor = Colors.red[50];
    if (status == _SyncStatus.notFound) rowColor = Colors.orange[50];
    if (status == _SyncStatus.duplicate) rowColor = Colors.purple[50];

    return DataGridRowAdapter(
      color: rowColor,
      cells: row.getCells().map<Widget>((e) {
        if (e.columnName == 'status') {
          return Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.all(8),
            child: _buildStatusIcon(e.value as _SyncStatus),
          );
        }
        if (e.columnName == 'aksi') {
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: 'Hapus baris',
                onPressed: isBusy
                    ? null
                    : () {
                        onRemove(no);
                      },
                icon: const Icon(Icons.delete_outline, color: Colors.red),
              ),
              IconButton(
                tooltip: 'Set Koordinat',
                onPressed: isBusy
                    ? null
                    : () {
                        onSetCoords?.call(no);
                      },
                icon: const Icon(Icons.my_location, color: Colors.teal),
              ),
              IconButton(
                tooltip: 'Sinkron ulang baris ini',
                onPressed: isBusy
                    ? null
                    : () {
                        onResync(no);
                      },
                icon: const Icon(Icons.refresh, color: Colors.blue),
              ),
              if (status == _SyncStatus.duplicate)
                IconButton(
                  tooltip: 'Review kandidat',
                  onPressed: isBusy
                      ? null
                      : () {
                          onReview(no);
                        },
                  icon: const Icon(Icons.search, color: Colors.deepPurple),
                ),
              if (status == _SyncStatus.notFound)
                IconButton(
                  tooltip: 'Tambah ke Direktori',
                  onPressed: isBusy || onInsertNotFound == null
                      ? null
                      : () {
                          onInsertNotFound?.call(no);
                        },
                  icon: const Icon(Icons.playlist_add, color: Colors.teal),
                ),
            ],
          );
        }
        return Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.all(8),
          child: Text(e.value.toString(), overflow: TextOverflow.ellipsis),
        );
      }).toList(),
    );
  }

  Widget _buildStatusIcon(_SyncStatus status) {
    switch (status) {
      case _SyncStatus.pending:
        return const Icon(Icons.schedule, color: Colors.grey, size: 20);
      case _SyncStatus.processing:
        return const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case _SyncStatus.matched:
        return const Icon(
          Icons.playlist_add_check,
          color: Colors.blue,
          size: 20,
        );
      case _SyncStatus.success:
        return const Icon(Icons.check_circle, color: Colors.green, size: 20);
      case _SyncStatus.error:
        return const Icon(Icons.error, color: Colors.red, size: 20);
      case _SyncStatus.notFound:
        return const Icon(Icons.help, color: Colors.orange, size: 20);
      case _SyncStatus.duplicate:
        return const Icon(Icons.content_copy, color: Colors.purple, size: 20);
    }
  }
}

class _HeaderCell extends StatelessWidget {
  final String title;
  const _HeaderCell({required this.title});
  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: Colors.blue[50],
      child: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
      ),
    );
  }
}
