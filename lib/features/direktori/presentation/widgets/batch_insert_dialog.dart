import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:latlong2/latlong.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import '../../../map/data/models/direktori_model.dart';
import '../../../map/data/repositories/map_repository_impl.dart';
import '../../../contribution/presentation/bloc/contribution_bloc.dart';
import '../../../contribution/presentation/bloc/contribution_event.dart';

class BatchInsertDialog extends StatefulWidget {
  const BatchInsertDialog({super.key});

  @override
  State<BatchInsertDialog> createState() => _BatchInsertDialogState();
}

class _BatchInsertDialogState extends State<BatchInsertDialog> {
  late final _BatchDataSource _source;
  bool _saving = false;
  int _success = 0;
  int _fail = 0;

  @override
  void initState() {
    super.initState();
    _source = _BatchDataSource(rowsData: []);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Tambah Data (Batch)'),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.8,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                TextButton.icon(
                  onPressed: _saving
                      ? null
                      : () async {
                          final data = await Clipboard.getData(
                            Clipboard.kTextPlain,
                          );
                          if (data?.text != null) {
                            _source.parseClipboard(data!.text!);
                            setState(() {});
                          }
                        },
                  icon: const Icon(Icons.content_paste),
                  label: const Text('Ambil dari Clipboard'),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _saving
                      ? null
                      : () {
                          _source.addEmptyRow();
                          setState(() {});
                        },
                  icon: const Icon(Icons.add),
                  label: const Text('Tambah Baris'),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _saving
                      ? null
                      : () {
                          _source.removeSelected();
                          setState(() {});
                        },
                  icon: const Icon(Icons.remove),
                  label: const Text('Hapus Baris'),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _saving
                      ? null
                      : () {
                          _source.removeDuplicates();
                          setState(() {});
                        },
                  icon: const Icon(Icons.filter_alt),
                  label: const Text('Hapus Duplikat'),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    'Baris: ${_source.totalCount} • Valid: ${_source.validCount} • Duplikat: ${_source.duplicateCount}',
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ),
                if (_saving)
                  Row(
                    children: [
                      const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 8),
                      Text('Menyimpan... ($_success sukses, $_fail gagal)'),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.6,
              child: SfDataGrid(
                source: _source,
                allowEditing: true,
                editingGestureType: EditingGestureType.doubleTap,
                selectionMode: SelectionMode.single,
                columnWidthMode: ColumnWidthMode.fill,
                columns: [
                  GridColumn(
                    columnName: 'no',
                    width: 80,
                    label: const _HeaderCell(title: 'No'),
                  ),
                  GridColumn(
                    columnName: 'nama',
                    label: const _HeaderCell(title: 'Nama Usaha'),
                  ),
                  GridColumn(
                    columnName: 'alamat',
                    label: const _HeaderCell(title: 'Alamat'),
                  ),
                  GridColumn(
                    columnName: 'koordinat',
                    label: const _HeaderCell(title: 'Koordinat (lat,lng)'),
                  ),
                  GridColumn(
                    columnName: 'valid',
                    width: 120,
                    label: const _HeaderCell(title: 'Valid'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Tutup'),
        ),
        ElevatedButton.icon(
          onPressed: _saving
              ? null
              : () async {
                  setState(() {
                    _saving = true;
                    _success = 0;
                    _fail = 0;
                  });
                  final repo = MapRepositoryImpl();
                  for (final r in _source.rowsData) {
                    try {
                      if (r.nama.trim().isEmpty) {
                        _fail++;
                        continue;
                      }
                      // Jika ada koordinat, coba tentukan data regional dulu
                      String idSls = '';
                      String? kodePos;
                      String? namaSls;
                      String kdProv = '';
                      String kdKab = '';
                      String kdKec = '';
                      String kdDesa = '';
                      String kdSls = '';
                      if (r.lat != null && r.lng != null) {
                        try {
                          final polygons = await repo
                              .getAllPolygonsMetaFromGeoJson(
                                'assets/geojson/final_sls.geojson',
                              );
                          for (final p in polygons) {
                            if (_isPointInPolygon(
                              LatLng(r.lat!, r.lng!),
                              p.points,
                            )) {
                              idSls = p.idsls ?? '';
                              namaSls = p.name;
                              kodePos = p.kodePos;
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

                      final model = DirektoriModel(
                        id: '',
                        idSbr: '0',
                        namaUsaha: r.nama,
                        alamat: r.alamat.isEmpty ? null : r.alamat,
                        idSls: idSls,
                        latitude: idSls.isNotEmpty ? r.lat : null,
                        longitude: idSls.isNotEmpty ? r.lng : null,
                        kdProv: kdProv.isNotEmpty ? kdProv : null,
                        kdKab: kdKab.isNotEmpty ? kdKab : null,
                        kdKec: kdKec.isNotEmpty ? kdKec : null,
                        kdDesa: kdDesa.isNotEmpty ? kdDesa : null,
                        kdSls: kdSls.isNotEmpty ? kdSls : null,
                        kodePos: kodePos,
                        nmSls: namaSls,
                        keberadaanUsaha: 1,
                        createdAt: DateTime.now(),
                        updatedAt: DateTime.now(),
                      );
                      final newId = await repo.insertDirectoryAndGetId(model);
                      if (newId == null) {
                        _fail++;
                        setState(() {});
                        continue;
                      }
                      try {
                        final Map<String, dynamic> changes = {
                          'nama_usaha': r.nama,
                        };
                        if (r.alamat.isNotEmpty) {
                          changes['alamat'] = r.alamat;
                        }
                        if (r.lat != null && r.lng != null) {
                          changes['latitude'] = r.lat;
                          changes['longitude'] = r.lng;
                        }
                        context.read<ContributionBloc>().add(
                          CreateContributionEvent(
                            actionType: 'create',
                            targetType: 'direktori',
                            targetId: newId,
                            changes: changes,
                            latitude: r.lat,
                            longitude: r.lng,
                          ),
                        );
                      } catch (_) {}
                      _success++;
                      setState(() {});
                    } catch (_) {
                      _fail++;
                      setState(() {});
                    }
                  }
                  setState(() {
                    _saving = false;
                  });
                  Navigator.of(context).pop(true);
                },
          icon: const Icon(Icons.save_alt),
          label: const Text('Simpan Semua'),
        ),
      ],
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

class _BatchRow {
  String nama;
  String alamat;
  String koordinat;
  double? lat;
  double? lng;
  bool valid;
  _BatchRow({
    this.nama = '',
    this.alamat = '',
    this.koordinat = '',
    this.lat,
    this.lng,
    this.valid = false,
  });
}

class _BatchDataSource extends DataGridSource {
  final List<_BatchRow> rowsData;
  final DataGridController controller = DataGridController();
  _BatchDataSource({required this.rowsData}) {
    _rebuildRows();
    _recomputeStats();
  }
  late List<DataGridRow> _rows;
  @override
  List<DataGridRow> get rows => _rows;

  int totalCount = 0;
  int validCount = 0;
  int duplicateCount = 0;

  @override
  DataGridRowAdapter buildRow(DataGridRow row) {
    final cells = row.getCells();
    final valid = cells[4].value as bool;
    return DataGridRowAdapter(
      cells: [
        Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text((cells[0].value ?? '').toString()),
        ),
        _cellEditor(row, 'nama', cells[1].value as String),
        _cellEditor(row, 'alamat', cells[2].value as String),
        _cellEditor(row, 'koordinat', cells[3].value as String),
        Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Icon(
            valid ? Icons.check_circle : Icons.error,
            color: valid ? Colors.green : Colors.red,
            size: 18,
          ),
        ),
      ],
    );
  }

  Widget _cellEditor(DataGridRow row, String column, String initial) {
    return Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: TextFormField(
        key: ValueKey('cell-$column-${_rows.indexOf(row)}'),
        initialValue: initial,
        maxLines: 1,
        decoration: const InputDecoration(
          isDense: true,
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        ),
        onChanged: (v) => updateCellValue(row, column, v),
      ),
    );
  }

  bool updateCellValue(DataGridRow row, String columnName, dynamic value) {
    final index = _rows.indexOf(row);
    if (index < 0) return false;
    final r = rowsData[index];
    switch (columnName) {
      case 'no':
        break;
      case 'nama':
        r.nama = (value as String?)?.trim() ?? '';
        break;
      case 'alamat':
        r.alamat = (value as String?)?.trim() ?? '';
        break;
      case 'koordinat':
        r.koordinat = (value as String?)?.trim() ?? '';
        _parseCoord(r);
        break;
    }
    _rebuildRows();
    _recomputeStats();
    notifyListeners();
    return true;
  }

  void parseClipboard(String text) {
    debugPrint('BatchInsert: mulai parse clipboard, panjang=${text.length}');
    final lines = text
        .split(RegExp(r'\r?\n'))
        .where((l) => l.trim().isNotEmpty)
        .toList();
    rowsData.clear();
    for (int i = 0; i < lines.length; i++) {
      final raw = lines[i];
      final line = raw.trim();
      String koordinat = '';
      double? lat;
      double? lng;
      String prefix = line;
      final cm = RegExp(
        r'(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*$',
      ).firstMatch(line);
      if (cm != null) {
        koordinat = '${cm.group(1)}, ${cm.group(2)}';
        lat = double.tryParse(cm.group(1)!);
        lng = double.tryParse(cm.group(2)!);
        prefix = line.substring(0, cm.start).trim();
      }

      String nama = '';
      String alamat = '';
      if (prefix.contains('\t')) {
        final cols = prefix.split('\t');
        if (cols.isNotEmpty) nama = cols[0].trim();
        if (cols.length > 1) alamat = cols[1].trim();
      } else {
        final idx = prefix.indexOf(',');
        if (idx >= 0) {
          nama = prefix.substring(0, idx).trim();
          alamat = prefix.substring(idx + 1).trim();
        } else {
          nama = prefix.trim();
          alamat = '';
        }
      }

      final r = _BatchRow(
        nama: nama,
        alamat: alamat,
        koordinat: koordinat,
        lat: lat,
        lng: lng,
      );
      _parseCoord(r);
      rowsData.add(r);
      debugPrint(
        'BatchInsert: row ${i + 1}: raw="$raw" => nama="$nama" alamat="$alamat" koordinat="$koordinat" lat=${lat?.toStringAsFixed(6)} lng=${lng?.toStringAsFixed(6)} valid=${r.valid}',
      );
    }
    _rebuildRows();
    _recomputeStats();
    debugPrint(
      'BatchInsert: selesai parse. total=${rowsData.length} valid=${rowsData.where((e) => e.valid).length} dup=$duplicateCount',
    );
    notifyListeners();
  }

  void addEmptyRow() {
    rowsData.add(_BatchRow());
    _rebuildRows();
    _recomputeStats();
    notifyListeners();
  }

  void removeSelected() {
    final sel = controller.selectedRow;
    if (sel == null) return;
    final index = _rows.indexOf(sel);
    if (index >= 0) {
      rowsData.removeAt(index);
      _rebuildRows();
      _recomputeStats();
      notifyListeners();
    }
  }

  void removeDuplicates() {
    final Set<String> seen = {};
    final List<_BatchRow> unique = [];
    for (final r in rowsData) {
      final key = _rowKey(r);
      if (seen.add(key)) {
        unique.add(r);
      }
    }
    rowsData
      ..clear()
      ..addAll(unique);
    _rebuildRows();
    _recomputeStats();
    notifyListeners();
  }

  void _parseCoord(_BatchRow r) {
    final m = RegExp(
      r'^\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*$',
    ).firstMatch(r.koordinat);
    if (m == null) {
      r.lat = null;
      r.lng = null;
      r.valid = false;
      return;
    }
    final lat = double.tryParse(m.group(1)!);
    final lng = double.tryParse(m.group(2)!);
    final inRange =
        lat != null &&
        lng != null &&
        lat >= -90 &&
        lat <= 90 &&
        lng >= -180 &&
        lng <= 180;
    r.lat = inRange ? lat : null;
    r.lng = inRange ? lng : null;
    r.valid = inRange;
  }

  void _rebuildRows() {
    _rows = [];
    for (int i = 0; i < rowsData.length; i++) {
      final r = rowsData[i];
      _rows.add(
        DataGridRow(
          cells: [
            DataGridCell<String>(columnName: 'no', value: '${i + 1}'),
            DataGridCell<String>(columnName: 'nama', value: r.nama),
            DataGridCell<String>(columnName: 'alamat', value: r.alamat),
            DataGridCell<String>(columnName: 'koordinat', value: r.koordinat),
            DataGridCell<bool>(columnName: 'valid', value: r.valid),
          ],
        ),
      );
    }
  }

  String _rowKey(_BatchRow r) {
    final name = r.nama.trim().toLowerCase();
    final addr = r.alamat.trim().toLowerCase();
    final coord = r.koordinat.trim().toLowerCase();
    return '$name|$addr|$coord';
  }

  void _recomputeStats() {
    totalCount = rowsData.length;
    validCount = rowsData.where((r) => r.valid).length;
    final Set<String> seen = {};
    int dup = 0;
    for (final r in rowsData) {
      final key = _rowKey(r);
      if (!seen.add(key)) dup++;
    }
    duplicateCount = dup;
  }

  void logRows(String tag) {
    debugPrint('BatchInsert: logRows tag=$tag total=${rowsData.length}');
    for (int i = 0; i < rowsData.length; i++) {
      final r = rowsData[i];
      debugPrint(
        'Row ${i + 1}: nama="${r.nama}" alamat="${r.alamat}" koordinat="${r.koordinat}" lat=${r.lat?.toStringAsFixed(6)} lng=${r.lng?.toStringAsFixed(6)} valid=${r.valid}',
      );
    }
  }
}
