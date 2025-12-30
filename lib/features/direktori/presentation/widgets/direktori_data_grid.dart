import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../contribution/presentation/bloc/contribution_bloc.dart';
import '../../../contribution/presentation/bloc/contribution_event.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import '../../../map/data/repositories/map_repository_impl.dart';
import '../../../map/presentation/pages/main_page.dart';
import '../../domain/entities/direktori.dart';
import '../bloc/direktori_bloc.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/config/app_constants.dart';

class DirektoriDataGrid extends StatefulWidget {
  final List<Direktori> direktoriList;
  final ScrollController scrollController;
  final bool isLoadingMore;
  final bool hasReachedMax;
  final String? sortColumn; // 'nama' | 'status'
  final bool sortAscending;
  final void Function(String column, bool ascending) onRequestSort;
  final void Function(String id)? onGoToMap;
  final VoidCallback? onRowUpdated;
  final void Function(String id, DateTime updatedAt)? onRowUpdatedWithId;
  final ValueNotifier<bool>? batchModeNotifier;

  const DirektoriDataGrid({
    Key? key,
    required this.direktoriList,
    required this.scrollController,
    required this.isLoadingMore,
    required this.hasReachedMax,
    required this.sortColumn,
    required this.sortAscending,
    required this.onRequestSort,
    this.onGoToMap,
    this.onRowUpdated,
    this.onRowUpdatedWithId,
    this.batchModeNotifier,
  }) : super(key: key);

  @override
  State<DirektoriDataGrid> createState() => _DirektoriDataGridState();
}

class _DirektoriDataGridState extends State<DirektoriDataGrid> {
  late final DataGridController _gridController;
  late final _DirektoriDataGridSource _source;
  bool _batchMode = false;
  int? _batchSelectedStatus;
  String _batchDuplicateParent = '';
  bool _batchSaving = false;
  String? _skalaFilter;

  @override
  void initState() {
    super.initState();
    _gridController = DataGridController();
    _source = _DirektoriDataGridSource(
      data: widget.direktoriList,
      onDetail: (d) => _showDetailDialog(context, d),
      onGoToMap: widget.onGoToMap,
      onRowUpdated: widget.onRowUpdated,
      onRowUpdatedWithId: widget.onRowUpdatedWithId,
    );
    if (widget.batchModeNotifier != null) {
      _batchMode = widget.batchModeNotifier!.value;
      widget.batchModeNotifier!.addListener(_onExternalBatchModeChanged);
    }
  }

  @override
  void didUpdateWidget(covariant DirektoriDataGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.direktoriList, oldWidget.direktoriList)) {
      _source.updateData(widget.direktoriList);
    }
    if (oldWidget.batchModeNotifier != widget.batchModeNotifier) {
      oldWidget.batchModeNotifier?.removeListener(_onExternalBatchModeChanged);
      if (widget.batchModeNotifier != null) {
        _batchMode = widget.batchModeNotifier!.value;
        widget.batchModeNotifier!.addListener(_onExternalBatchModeChanged);
      }
    }
  }

  void _onExternalBatchModeChanged() {
    setState(() {
      _batchMode = widget.batchModeNotifier!.value;
      if (!_batchMode) {
        _batchSelectedStatus = null;
        _batchDuplicateParent = '';
        _batchSaving = false;
      }
    });
  }

  Future<String?> _pickSkalaFilter(
    BuildContext context,
    String? current,
  ) async {
    return await _source._pickSkalaFilter(context, current);
  }

  @override
  Widget build(BuildContext context) {
    final double availableWidth =
        MediaQuery.of(context).size.width - 32; // margin horizontal 16*2
    const Map<String, int> weights = {
      'id_sbr': 1,
      'nama': 3,
      'alamat': 3,
      'email': 2,
      'skala_usaha': 1,
      'status': 1,
      'idsbr_duplikat': 1,
      'koordinat': 1,
      'aksi': 2,
    };
    final int totalWeight = weights.values.reduce((a, b) => a + b);
    double cw(String key) {
      final base = availableWidth * (weights[key]! / totalWeight);
      final min = key == 'koordinat' ? 140.0 : 100.0;
      return base.clamp(min, availableWidth).toDouble();
    }

    return Column(
      children: [
        Expanded(
          child: Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  spreadRadius: 1,
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SfDataGrid(
                source: _source,
                verticalScrollController: widget.scrollController,
                controller: _gridController,
                rowHeight: 64,
                allowSorting: false,
                allowMultiColumnSorting: false,
                allowTriStateSorting: false,
                allowFiltering: true,
                selectionMode: _batchMode
                    ? SelectionMode.multiple
                    : SelectionMode.single,
                showCheckboxColumn: _batchMode,
                headerGridLinesVisibility: GridLinesVisibility.horizontal,
                gridLinesVisibility: GridLinesVisibility.horizontal,
                columnWidthMode: ColumnWidthMode.fill,
                onCellTap: null,
                columns: [
                  GridColumn(
                    columnName: 'id_sbr',
                    width: cw('id_sbr'),
                    allowSorting: false,
                    allowFiltering: false,
                    label: Container(
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      color: Colors.blue[50],
                      child: const Text(
                        'ID SBR',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ),
                  GridColumn(
                    columnName: 'nama',
                    width: cw('nama'),
                    allowFiltering: false,
                    label: GestureDetector(
                      onTap: () => widget.onRequestSort(
                        'nama',
                        widget.sortColumn == 'nama'
                            ? !widget.sortAscending
                            : true,
                      ),
                      child: Container(
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        color: Colors.blue[50],
                        child: Row(
                          children: [
                            const Text(
                              'Nama Usaha',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(width: 6),
                            if (widget.sortColumn == 'nama')
                              Icon(
                                widget.sortAscending
                                    ? Icons.arrow_upward
                                    : Icons.arrow_downward,
                                size: 14,
                                color: Colors.blue[700],
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  GridColumn(
                    columnName: 'alamat',
                    width: cw('alamat'),
                    allowSorting: false,
                    allowFiltering: false,
                    label: Container(
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      color: Colors.blue[50],
                      child: const Text(
                        'Alamat',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ),
                  GridColumn(
                    columnName: 'email',
                    width: cw('email'),
                    allowSorting: false,
                    allowFiltering: false,
                    label: Container(
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      color: Colors.blue[50],
                      child: const Text(
                        'Email',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ),
                  GridColumn(
                    columnName: 'skala_usaha',
                    width: cw('skala_usaha'),
                    allowSorting: false,
                    allowFiltering: false,
                    label: GestureDetector(
                      onTap: () async {
                        final String? selected = await _pickSkalaFilter(
                          context,
                          _skalaFilter,
                        );
                        if (selected == null || selected.isEmpty) {
                          setState(() {
                            _skalaFilter = null;
                          });
                          _source.applySkalaFilter(null);
                        } else {
                          setState(() {
                            _skalaFilter = selected;
                          });
                          _source.applySkalaFilter(selected);
                        }
                      },
                      child: Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        color: Colors.blue[50],
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const Text(
                              'Skala Usaha',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                              alignment: WrapAlignment.center,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 6,
                              runSpacing: 0,
                              children: [
                                Icon(
                                  Icons.filter_alt,
                                  size: 16,
                                  color: Colors.blue[700],
                                ),
                                if (_skalaFilter != null)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade100,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: Colors.blue.shade200,
                                      ),
                                    ),
                                    child: Text(
                                      _skalaFilter!,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.blue.shade900,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  GridColumn(
                    columnName: 'status',
                    width: cw('status'),
                    label: GestureDetector(
                      onTap: () => widget.onRequestSort(
                        'status',
                        widget.sortColumn == 'status'
                            ? !widget.sortAscending
                            : true,
                      ),
                      child: Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        color: Colors.blue[50],
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              'Status',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(width: 6),
                            if (widget.sortColumn == 'status')
                              Icon(
                                widget.sortAscending
                                    ? Icons.arrow_upward
                                    : Icons.arrow_downward,
                                size: 14,
                                color: Colors.blue[700],
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  GridColumn(
                    columnName: 'idsbr_duplikat',
                    width: cw('idsbr_duplikat'),
                    allowSorting: false,
                    allowFiltering: false,
                    label: Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      color: Colors.blue[50],
                      child: const Text(
                        'ID SBR Duplikat',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ),
                  GridColumn(
                    columnName: 'koordinat',
                    width: cw('koordinat'),
                    allowSorting: false,
                    allowFiltering: false,
                    label: Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      color: Colors.blue[50],
                      child: const Text(
                        'Koordinat',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ),
                  GridColumn(
                    columnName: 'aksi',
                    width: cw('aksi'),
                    allowSorting: false,
                    allowFiltering: false,
                    label: Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      color: Colors.blue[50],
                      child: const Text(
                        'Aksi',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // if (widget.isLoadingMore)
        //   const Padding(
        //     padding: EdgeInsets.all(16),
        //     child: CircularProgressIndicator(),
        //   ),
        // if (widget.hasReachedMax && widget.direktoriList.isNotEmpty)
        //   Padding(
        //     padding: const EdgeInsets.all(16),
        //     child: Text(
        //       'Semua data telah dimuat',
        //       style: TextStyle(color: Colors.grey[600], fontSize: 12),
        //     ),
        //   ),
        // const SizedBox(height: 80),
        if (_batchMode)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF8E1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFFE082)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Dipilih: ${_gridController.selectedRows.length}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'Ganti Status:',
                              style: TextStyle(fontSize: 12),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 220,
                              child: DropdownButtonFormField<int>(
                                value: _batchSelectedStatus,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                  labelText: 'Status',
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: 1,
                                    child: Text('Aktif'),
                                  ),
                                  DropdownMenuItem(
                                    value: 2,
                                    child: Text('Tutup Sementara'),
                                  ),
                                  DropdownMenuItem(
                                    value: 3,
                                    child: Text('Belum Beroperasi'),
                                  ),
                                  DropdownMenuItem(
                                    value: 4,
                                    child: Text('Tutup'),
                                  ),
                                  DropdownMenuItem(
                                    value: 5,
                                    child: Text('Alih Usaha'),
                                  ),
                                  DropdownMenuItem(
                                    value: 6,
                                    child: Text('Tidak Ditemukan'),
                                  ),
                                  DropdownMenuItem(
                                    value: 7,
                                    child: Text('Aktif Pindah'),
                                  ),
                                  DropdownMenuItem(
                                    value: 8,
                                    child: Text('Aktif Nonrespon'),
                                  ),
                                  DropdownMenuItem(
                                    value: 9,
                                    child: Text('Duplikat'),
                                  ),
                                  DropdownMenuItem(
                                    value: 10,
                                    child: Text('Salah Kode Wilayah'),
                                  ),
                                ],
                                onChanged: (v) {
                                  setState(() {
                                    _batchSelectedStatus = v;
                                  });
                                },
                              ),
                            ),
                            const Spacer(),
                            if (_batchSaving)
                              const SizedBox(
                                width: 28,
                                height: 28,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            else ...[
                              ElevatedButton(
                                onPressed:
                                    (_gridController.selectedRows.isEmpty ||
                                        _batchSelectedStatus == null ||
                                        (_batchSelectedStatus == 9 &&
                                            _batchDuplicateParent
                                                .trim()
                                                .isEmpty))
                                    ? null
                                    : () async {
                                        await _applyBatchStatus(context);
                                      },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text('Simpan'),
                              ),
                              const SizedBox(width: 8),
                              TextButton(
                                onPressed: () {
                                  setState(() {
                                    _batchMode = false;
                                    _batchSelectedStatus = null;
                                    _batchDuplicateParent = '';
                                  });
                                  widget.batchModeNotifier?.value = false;
                                },
                                child: const Text('Batal'),
                              ),
                            ],
                          ],
                        ),
                        if (_batchSelectedStatus == 9) ...[
                          const SizedBox(height: 8),
                          TextField(
                            decoration: const InputDecoration(
                              labelText: 'ID SBR Parent Duplikat',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (v) {
                              setState(() {
                                _batchDuplicateParent = v.trim();
                              });
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _applyBatchStatus(BuildContext context) async {
    setState(() {
      _batchSaving = true;
    });
    final selected = List<DataGridRow>.from(_gridController.selectedRows);
    int success = 0;
    for (final row in selected) {
      final cells = row.getCells();
      if (cells.isEmpty) continue;
      final Direktori d = cells.last.value as Direktori;
      final String id = d.id;
      bool ok = false;
      if (_batchSelectedStatus == 9) {
        ok = await MapRepositoryImpl().markDirectoryAsDuplicate(
          id,
          _batchDuplicateParent.trim(),
        );
      } else {
        ok = await MapRepositoryImpl().updateDirectoryStatus(
          id,
          _batchSelectedStatus!,
        );
        final cleared = await MapRepositoryImpl().clearDirectoryDuplicateParent(
          id,
        );
        if (cleared) {
          _source._setIdSbrDuplikatForId(id, null);
        }
      }
      if (ok) {
        _source._setStatusForId(id, _batchSelectedStatus!);
        if (_batchSelectedStatus == 9) {
          _source._setIdSbrDuplikatForId(id, _batchDuplicateParent.trim());
        }
        _source._markRowUpdated(id);
        try {
          final Map<String, dynamic> changes = {
            'keberadaan_usaha': _batchSelectedStatus,
          };
          if (_batchSelectedStatus == 9 &&
              _batchDuplicateParent.trim().isNotEmpty) {
            changes['idsbr_duplikat'] = _batchDuplicateParent.trim();
          }
          context.read<ContributionBloc>().add(
            CreateContributionEvent(
              actionType: 'update',
              targetType: 'direktori',
              targetId: id,
              changes: changes,
            ),
          );
        } catch (_) {}
        success++;
      }
    }
    setState(() {
      _batchSaving = false;
      _batchMode = false;
      _batchSelectedStatus = null;
      _batchDuplicateParent = '';
    });
    // Berhasil, tidak tampilkan SnackBar agar tidak mengganggu
  }

  void _showDetailDialog(BuildContext context, Direktori direktori) {
    showDialog<void>(
      context: context,
      builder: (context) =>
          _DetailDialog(direktori: direktori, onGoToMap: widget.onGoToMap),
    );
  }
}

// Pager dihapus sesuai permintaan; infinite scroll tetap aktif via Bloc.

class _DirektoriDataGridSource extends DataGridSource {
  List<Direktori> data;
  final void Function(Direktori) onDetail;
  final void Function(String id)? onGoToMap;
  final VoidCallback? onRowUpdated;
  final void Function(String id, DateTime updatedAt)? onRowUpdatedWithId;
  final Set<String> _editingIds = <String>{};
  final Map<String, String> _editedNamaById = <String, String>{};
  final Map<String, String?> _editedAlamatById = <String, String?>{};
  final Map<String, String?> _editedEmailById = <String, String?>{};
  final Map<String, int?> _editedStatusById = <String, int?>{};
  final Map<String, String> _editedIdSbrDuplikatById = <String, String>{};
  final Map<String, String?> _editedSkalaUsahaById = <String, String?>{};
  final Set<String> _savingIds = <String>{};
  final Set<String> _recentlyUpdatedIds = <String>{};
  String? _skalaFilter;

  _DirektoriDataGridSource({
    required this.data,
    required this.onDetail,
    this.onGoToMap,
    this.onRowUpdated,
    this.onRowUpdatedWithId,
  }) {
    _rows = data
        .where(
          (d) =>
              _skalaFilter == null ||
              _normalizeSkalaUsaha(d.skalaUsaha) == _skalaFilter,
        )
        .map(
          (d) => DataGridRow(
            cells: [
              DataGridCell<String>(columnName: 'id_sbr', value: d.idSbr),
              DataGridCell<String>(columnName: 'nama', value: d.namaUsaha),
              DataGridCell<String?>(columnName: 'alamat', value: d.alamat),
              DataGridCell<String?>(columnName: 'email', value: d.email),
              DataGridCell<String?>(
                columnName: 'skala_usaha',
                value: d.skalaUsaha,
              ),
              DataGridCell<int?>(
                columnName: 'status',
                value: d.keberadaanUsaha,
              ),
              DataGridCell<String?>(
                columnName: 'idsbr_duplikat',
                value: d.idSbrDuplikat,
              ),
              DataGridCell<bool>(
                columnName: 'koordinat',
                value:
                    ((d.latitude ?? d.lat) != null) &&
                    ((d.longitude ?? d.long) != null),
              ),

              DataGridCell<Direktori>(columnName: 'aksi', value: d),
            ],
          ),
        )
        .toList();
  }

  List<DataGridRow> _rows = [];

  @override
  List<DataGridRow> get rows => _rows;

  void updateData(List<Direktori> newData) {
    data = newData;
    _rows = data
        .where(
          (d) =>
              _skalaFilter == null ||
              _normalizeSkalaUsaha(d.skalaUsaha) == _skalaFilter,
        )
        .map(
          (d) => DataGridRow(
            cells: [
              DataGridCell<String>(columnName: 'id_sbr', value: d.idSbr),
              DataGridCell<String>(columnName: 'nama', value: d.namaUsaha),
              DataGridCell<String?>(columnName: 'alamat', value: d.alamat),
              DataGridCell<String?>(columnName: 'email', value: d.email),
              DataGridCell<String?>(
                columnName: 'skala_usaha',
                value: d.skalaUsaha,
              ),
              DataGridCell<int?>(
                columnName: 'status',
                value: d.keberadaanUsaha,
              ),
              DataGridCell<String?>(
                columnName: 'idsbr_duplikat',
                value: d.idSbrDuplikat,
              ),
              DataGridCell<bool>(
                columnName: 'koordinat',
                value:
                    ((d.latitude ?? d.lat) != null) &&
                    ((d.longitude ?? d.long) != null),
              ),

              DataGridCell<Direktori>(columnName: 'aksi', value: d),
            ],
          ),
        )
        .toList();
    notifyListeners();
  }

  void applySkalaFilter(String? filter) {
    _skalaFilter = (filter == null || filter.isEmpty) ? null : filter;
    _rows = data
        .where(
          (d) =>
              _skalaFilter == null ||
              _normalizeSkalaUsaha(d.skalaUsaha) == _skalaFilter,
        )
        .map(
          (d) => DataGridRow(
            cells: [
              DataGridCell<String>(columnName: 'id_sbr', value: d.idSbr),
              DataGridCell<String>(columnName: 'nama', value: d.namaUsaha),
              DataGridCell<String?>(columnName: 'alamat', value: d.alamat),
              DataGridCell<String?>(columnName: 'email', value: d.email),
              DataGridCell<String?>(
                columnName: 'skala_usaha',
                value: d.skalaUsaha,
              ),
              DataGridCell<int?>(
                columnName: 'status',
                value: d.keberadaanUsaha,
              ),
              DataGridCell<String?>(
                columnName: 'idsbr_duplikat',
                value: d.idSbrDuplikat,
              ),
              DataGridCell<bool>(
                columnName: 'koordinat',
                value:
                    ((d.latitude ?? d.lat) != null) &&
                    ((d.longitude ?? d.long) != null),
              ),
              DataGridCell<Direktori>(columnName: 'aksi', value: d),
            ],
          ),
        )
        .toList();
    notifyListeners();
  }

  @override
  DataGridRowAdapter buildRow(DataGridRow row) {
    final cells = row.getCells();
    final direktori = cells.isNotEmpty ? (cells.last.value as Direktori) : null;
    if (direktori == null) {
      return const DataGridRowAdapter(cells: []);
    }
    final int? status = cells[5].value as int?;
    final bool hasCoord = cells[7].value as bool;
    final DateTime? updatedAt = direktori.updatedAt;
    final String id = direktori.id;
    final bool isEditing = _editingIds.contains(id);
    final DateTime threshold = AppConstants.updatedThreshold;
    final bool isRowUpdated =
        _recentlyUpdatedIds.contains(id) ||
        (updatedAt != null && updatedAt.isAfter(threshold));

    Color? rowColor;
    if (isRowUpdated) {
      if (!hasCoord) {
        rowColor = const Color(0xFFFFEBEE);
      } else if ((status ?? 0) != 1) {
        rowColor = const Color(0xFFFFF3E0);
      } else {
        rowColor = const Color(0xFFE9F7EF);
      }
    } else {
      rowColor = null;
    }

    return DataGridRowAdapter(
      color: rowColor,
      cells: [
        Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(
                child: Text(
                  cells[0].value ?? '-',
                  style: const TextStyle(fontSize: 12, color: Colors.black87),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              if (((cells[0].value ?? '') as String).isEmpty ||
                  ((cells[0].value ?? '-') == '-') ||
                  ((cells[0].value ?? '').toString().trim() == '0'))
                Tooltip(
                  message: 'Tempel ID SBR dari clipboard',
                  child: Builder(
                    builder: (ctx) => InkWell(
                      onTap: () async {
                        try {
                          final data = await Clipboard.getData(
                            Clipboard.kTextPlain,
                          );
                          final txt = data?.text?.trim();
                          if ((txt ?? '').isEmpty) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                content: Text('Clipboard kosong'),
                                duration: Duration(milliseconds: 900),
                              ),
                            );
                            return;
                          }
                          final ok = await MapRepositoryImpl()
                              .updateDirectoryIdSbr(id, txt!);
                          if (ok) {
                            _setIdSbrForId(id, txt);
                            _markRowUpdated(id);
                            try {
                              ctx.read<ContributionBloc>().add(
                                CreateContributionEvent(
                                  actionType: 'update',
                                  targetType: 'direktori',
                                  targetId: id,
                                  changes: {'id_sbr': txt},
                                ),
                              );
                            } catch (_) {}
                          }
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(
                              content: Text('ID SBR ditempel'),
                              duration: Duration(milliseconds: 900),
                            ),
                          );
                        } catch (_) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(
                              content: Text('Gagal membaca clipboard'),
                              duration: Duration(milliseconds: 900),
                            ),
                          );
                        }
                      },
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: const BoxDecoration(
                          color: Colors.orange,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.content_paste,
                          color: Colors.white,
                          size: 14,
                        ),
                      ),
                    ),
                  ),
                ),
              if (((cells[0].value ?? '') as String).isNotEmpty &&
                  (cells[0].value ?? '-') != '-')
                Tooltip(
                  message: 'Copy ID SBR',
                  child: Builder(
                    builder: (ctx) => InkWell(
                      onTap: () {
                        final txt = (cells[0].value ?? '').toString();
                        Clipboard.setData(ClipboardData(text: txt));
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                            content: Text('ID SBR disalin'),
                            duration: Duration(milliseconds: 800),
                          ),
                        );
                      },
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: const BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.copy,
                          color: Colors.white,
                          size: 14,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: isEditing
              ? BoxDecoration(
                  color: const Color(0xFFFFF8E1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFFFE082)),
                )
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isEditing)
                TextFormField(
                  key: ValueKey('nama-$id'),
                  initialValue: _editedNamaById[id] ?? (cells[1].value ?? ''),
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                  onChanged: (v) => _editedNamaById[id] = v,
                )
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Builder(
                        builder: (ctx) => GestureDetector(
                          onDoubleTap: () {
                            final txt = (cells[1].value ?? '').toString();
                            Clipboard.setData(ClipboardData(text: txt));
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                content: Text('Nama usaha disalin'),
                                duration: Duration(milliseconds: 800),
                              ),
                            );
                          },
                          child: Text(
                            cells[1].value ?? '',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Tooltip(
                      message: 'Cari di Google Maps (nama)',
                      child: Builder(
                        builder: (ctx) => InkWell(
                          onTap: () async {
                            final name = (cells[1].value ?? '')
                                .toString()
                                .trim();
                            if (name.isEmpty) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(
                                  content: Text('Nama usaha kosong'),
                                  duration: Duration(milliseconds: 1000),
                                ),
                              );
                              return;
                            }
                            final q = '$name parepare';
                            final url = Uri.parse(
                              'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(q)}',
                            );
                            final ok = await launchUrl(
                              url,
                              mode: LaunchMode.externalApplication,
                            );
                            if (!ok) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Tidak bisa membuka Google Maps',
                                  ),
                                  duration: Duration(milliseconds: 1000),
                                ),
                              );
                            }
                          },
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: const BoxDecoration(
                              color: Colors.blue,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.travel_explore,
                              color: Colors.white,
                              size: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: isEditing
              ? BoxDecoration(
                  color: const Color(0xFFFFF8E1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFFFE082)),
                )
              : null,
          child: isEditing
              ? TextFormField(
                  key: ValueKey('alamat-$id'),
                  initialValue:
                      _editedAlamatById[id] ?? (cells[2].value ?? '-'),
                  style: const TextStyle(fontSize: 13),
                  maxLines: 2,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                  onChanged: (v) => _editedAlamatById[id] = v,
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        cells[2].value ?? '-',
                        style: const TextStyle(fontSize: 13),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Tooltip(
                      message: 'Cari di Google Maps (alamat)',
                      child: Builder(
                        builder: (ctx) => InkWell(
                          onTap: () async {
                            final alamat = (cells[2].value ?? '')
                                .toString()
                                .trim();
                            if (alamat.isEmpty || alamat == '-') {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(
                                  content: Text('Alamat kosong'),
                                  duration: Duration(milliseconds: 1000),
                                ),
                              );
                              return;
                            }
                            final q2 = '$alamat parepare';
                            final url = Uri.parse(
                              'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(q2)}',
                            );
                            final ok = await launchUrl(
                              url,
                              mode: LaunchMode.externalApplication,
                            );
                            if (!ok) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Tidak bisa membuka Google Maps',
                                  ),
                                  duration: Duration(milliseconds: 1000),
                                ),
                              );
                            }
                          },
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: const BoxDecoration(
                              color: Colors.blue,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.travel_explore,
                              color: Colors.white,
                              size: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
        Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(
                child: Text(
                  (_editedEmailById[id]?.isNotEmpty == true)
                      ? _editedEmailById[id]!
                      : (cells[3].value ?? '-') as String,
                  style: const TextStyle(fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              if (isEditing) ...[
                if ((_editedEmailById[id]?.isNotEmpty != true) &&
                    ((((cells[3].value ?? '') as String).isEmpty) ||
                        ((cells[3].value ?? '-') == '-')))
                  Tooltip(
                    message: 'Tempel Email dari clipboard',
                    child: Builder(
                      builder: (ctx) => InkWell(
                        onTap: () async {
                          try {
                            final data = await Clipboard.getData(
                              Clipboard.kTextPlain,
                            );
                            final txt = data?.text?.trim();
                            if ((txt ?? '').isEmpty) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(
                                  content: Text('Clipboard kosong'),
                                  duration: Duration(milliseconds: 900),
                                ),
                              );
                              return;
                            }
                            _editedEmailById[id] = txt;
                            notifyListeners();
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                content: Text('Email ditempel'),
                                duration: Duration(milliseconds: 900),
                              ),
                            );
                          } catch (_) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                content: Text('Gagal membaca clipboard'),
                                duration: Duration(milliseconds: 900),
                              ),
                            );
                          }
                        },
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: const BoxDecoration(
                            color: Colors.orange,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.content_paste,
                            color: Colors.white,
                            size: 14,
                          ),
                        ),
                      ),
                    ),
                  ),
              ] else ...[
                if ((_editedEmailById[id]?.isNotEmpty != true) &&
                    ((((cells[3].value ?? '') as String).isEmpty) ||
                        ((cells[3].value ?? '-') == '-')))
                  Tooltip(
                    message: 'Tempel Email dari clipboard',
                    child: Builder(
                      builder: (ctx) => InkWell(
                        onTap: () async {
                          try {
                            final data = await Clipboard.getData(
                              Clipboard.kTextPlain,
                            );
                            final txt = data?.text?.trim();
                            if ((txt ?? '').isEmpty) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(
                                  content: Text('Clipboard kosong'),
                                  duration: Duration(milliseconds: 900),
                                ),
                              );
                              return;
                            }
                            try {
                              final ok = await MapRepositoryImpl()
                                  .updateDirectoryBasicFields(id, email: txt);
                              if (ok) {
                                _setEmailForId(id, txt!);
                                _markRowUpdated(id);
                                try {
                                  ctx.read<ContributionBloc>().add(
                                    CreateContributionEvent(
                                      actionType: 'update',
                                      targetType: 'direktori',
                                      targetId: id,
                                      changes: {'email': txt},
                                    ),
                                  );
                                } catch (_) {}
                              }
                            } catch (_) {}
                            notifyListeners();
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                content: Text('Email ditempel'),
                                duration: Duration(milliseconds: 900),
                              ),
                            );
                          } catch (_) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                content: Text('Gagal membaca clipboard'),
                                duration: Duration(milliseconds: 900),
                              ),
                            );
                          }
                        },
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: const BoxDecoration(
                            color: Colors.orange,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.content_paste,
                            color: Colors.white,
                            size: 14,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
        Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: isEditing
              ? DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value:
                        (_editedSkalaUsahaById[id] ??
                        _normalizeSkalaUsaha(direktori.skalaUsaha)),
                    items: const [
                      DropdownMenuItem(value: 'UMKM', child: Text('UMKM')),
                      DropdownMenuItem(value: 'UB', child: Text('UB')),
                    ],
                    onChanged: (v) {
                      _editedSkalaUsahaById[id] = v;
                      notifyListeners();
                    },
                  ),
                )
              : Text(
                  _normalizeSkalaUsaha(cells[4].value) ?? '-',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
        Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: isEditing
              ? Builder(
                  builder: (ctx) => InkWell(
                    onTap: () => _pickStatus(ctx, id, status),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF8E1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFFFE082)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _getKeberadaanUsahaDescription(
                              _editedStatusById[id] ?? status,
                            ),
                            style: const TextStyle(fontSize: 12),
                          ),
                          const SizedBox(width: 6),
                          const Icon(Icons.arrow_drop_down, size: 18),
                        ],
                      ),
                    ),
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        _getKeberadaanUsahaDescription(status),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: _getKeberadaanColor(status),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
        Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(
                child: Text(
                  (_editedIdSbrDuplikatById[id]?.isNotEmpty == true)
                      ? _editedIdSbrDuplikatById[id]!
                      : (cells[6].value ?? '-') as String,
                  style: const TextStyle(fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              if (false) const SizedBox.shrink(),
              if (isEditing) ...[
                const SizedBox(width: 6),
                if ((_editedIdSbrDuplikatById[id]?.isNotEmpty != true) &&
                    ((((cells[6].value ?? '') as String).isEmpty) ||
                        ((cells[6].value ?? '-') == '-')))
                  Tooltip(
                    message: 'Tempel ID SBR Duplikat dari clipboard',
                    child: Builder(
                      builder: (ctx) => InkWell(
                        onTap: () async {
                          try {
                            final data = await Clipboard.getData(
                              Clipboard.kTextPlain,
                            );
                            final txt = data?.text?.trim();
                            if ((txt ?? '').isEmpty) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(
                                  content: Text('Clipboard kosong'),
                                  duration: Duration(milliseconds: 900),
                                ),
                              );
                              return;
                            }
                            _editedIdSbrDuplikatById[id] = txt!;
                            _editedStatusById[id] = 9;
                            notifyListeners();
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                content: Text('ID SBR duplikat ditempel'),
                                duration: Duration(milliseconds: 900),
                              ),
                            );
                          } catch (_) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                content: Text('Gagal membaca clipboard'),
                                duration: Duration(milliseconds: 900),
                              ),
                            );
                          }
                        },
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: const BoxDecoration(
                            color: Colors.orange,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.content_paste,
                            color: Colors.white,
                            size: 14,
                          ),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(width: 6),
                if ((_editedIdSbrDuplikatById[id]?.isNotEmpty == true) ||
                    ((((cells[6].value ?? '') as String).isNotEmpty) &&
                        (cells[6].value ?? '-') != '-')) ...[
                  const SizedBox(width: 6),
                  Tooltip(
                    message: 'Hapus ID SBR Duplikat',
                    child: Builder(
                      builder: (ctx) => InkWell(
                        onTap: () {
                          _editedIdSbrDuplikatById[id] = '';
                          _setIdSbrDuplikatForId(id, null);
                          notifyListeners();
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(
                              content: Text('ID SBR duplikat dihapus'),
                              duration: Duration(milliseconds: 900),
                            ),
                          );
                        },
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.clear,
                            color: Colors.white,
                            size: 14,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
              if (!isEditing) ...[
                const SizedBox(width: 6),
                if ((_editedIdSbrDuplikatById[id]?.isNotEmpty != true) &&
                    ((((cells[6].value ?? '') as String).isEmpty) ||
                        ((cells[6].value ?? '-') == '-')))
                  Tooltip(
                    message: 'Tempel ID SBR Duplikat dari clipboard',
                    child: Builder(
                      builder: (ctx) => InkWell(
                        onTap: () async {
                          try {
                            final data = await Clipboard.getData(
                              Clipboard.kTextPlain,
                            );
                            final txt = data?.text?.trim();
                            if ((txt ?? '').isEmpty) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(
                                  content: Text('Clipboard kosong'),
                                  duration: Duration(milliseconds: 900),
                                ),
                              );
                              return;
                            }
                            _editedIdSbrDuplikatById[id] = txt!;
                            try {
                              final ok = await MapRepositoryImpl()
                                  .markDirectoryAsDuplicate(id, txt!);
                              if (ok) {
                                _setStatusForId(id, 9);
                                _setIdSbrDuplikatForId(id, txt!);
                                _markRowUpdated(id);
                                final Map<String, dynamic> changes = {
                                  'keberadaan_usaha': 9,
                                  'idsbr_duplikat': txt!,
                                };
                                try {
                                  ctx.read<ContributionBloc>().add(
                                    CreateContributionEvent(
                                      actionType: 'update',
                                      targetType: 'direktori',
                                      targetId: id,
                                      changes: changes,
                                    ),
                                  );
                                } catch (_) {}
                              }
                            } catch (_) {}
                            notifyListeners();
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                content: Text('ID SBR duplikat ditempel'),
                                duration: Duration(milliseconds: 900),
                              ),
                            );
                          } catch (_) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                content: Text('Gagal membaca clipboard'),
                                duration: Duration(milliseconds: 900),
                              ),
                            );
                          }
                        },
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: const BoxDecoration(
                            color: Colors.orange,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.content_paste,
                            color: Colors.white,
                            size: 14,
                          ),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(width: 6),
                if ((_editedIdSbrDuplikatById[id]?.isNotEmpty == true) ||
                    ((((cells[6].value ?? '') as String).isNotEmpty) &&
                        (cells[6].value ?? '-') != '-')) ...[
                  const SizedBox(width: 6),
                  Tooltip(
                    message: 'Hapus ID SBR Duplikat',
                    child: Builder(
                      builder: (ctx) => InkWell(
                        onTap: () {
                          _editedIdSbrDuplikatById[id] = '';
                          _setIdSbrDuplikatForId(id, null);
                          notifyListeners();
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(
                              content: Text('ID SBR duplikat dihapus'),
                              duration: Duration(milliseconds: 900),
                            ),
                          );
                        },
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.clear,
                            color: Colors.white,
                            size: 14,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
        Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                hasCoord ? Icons.location_on : Icons.location_off,
                size: 16,
                color: hasCoord ? Colors.green : Colors.red,
              ),
              const SizedBox(width: 6),
              Text(
                hasCoord ? 'Ada' : 'Tidak',
                style: TextStyle(
                  fontSize: 12,
                  color: hasCoord ? Colors.green : Colors.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (hasCoord && !isEditing) ...[
                const SizedBox(width: 8),
                Tooltip(
                  message: 'Copy koordinat',
                  child: InkWell(
                    onTap: () {
                      final lat = (direktori.latitude ?? direktori.lat) ?? 0;
                      final lng = (direktori.longitude ?? direktori.long) ?? 0;
                      final text =
                          '${lat.toStringAsFixed(15)}, ${lng.toStringAsFixed(15)}';
                      Clipboard.setData(ClipboardData(text: text));
                    },
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.copy,
                        color: Colors.white,
                        size: 14,
                      ),
                    ),
                  ),
                ),
              ],
              if (isEditing) ...[
                const SizedBox(width: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Tooltip(
                      message: 'Pakai posisi peta',
                      child: Builder(
                        builder: (ctx) => InkWell(
                          onTap: () => _navigateToMap(ctx, id),
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: const BoxDecoration(
                              color: Colors.teal,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.map,
                              color: Colors.white,
                              size: 14,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Tooltip(
                      message: 'Input koordinat langsung',
                      child: Builder(
                        builder: (ctx) => InkWell(
                          onTap: () => _promptInputCoordinates(ctx, id),
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: const BoxDecoration(
                              color: Colors.deepOrange,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.edit_location_alt,
                              color: Colors.white,
                              size: 14,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),

        Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            alignment: WrapAlignment.center,
            children: [
              if (!isEditing) ...[
                _iconAction(
                  icon: Icons.visibility,
                  color: Colors.blue,
                  tooltip: 'Lihat',
                  onTap: (ctx) => onDetail(direktori),
                ),
                if (hasCoord)
                  _iconAction(
                    icon: Icons.map,
                    color: Colors.teal,
                    tooltip: 'Buka peta (Go to)',
                    onTap: (ctx) {
                      if (onGoToMap != null) {
                        onGoToMap!(id);
                      } else {
                        _navigateToMap(ctx, id);
                      }
                    },
                  ),
                if ((cells[0].value ?? '') == '0')
                  _iconAction(
                    icon: Icons.delete_outline,
                    color: Colors.redAccent,
                    tooltip: 'Hapus',
                    onTap: (ctx) async {
                      final ok = await showDialog<bool>(
                        context: ctx,
                        builder: (dctx) => AlertDialog(
                          title: const Text('Konfirmasi Hapus'),
                          content: const Text(
                            'Apakah yakin ingin menghapus data ini?',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(dctx).pop(false),
                              child: const Text('Batal'),
                            ),
                            ElevatedButton(
                              onPressed: () => Navigator.of(dctx).pop(true),
                              child: const Text('Hapus'),
                            ),
                          ],
                        ),
                      );
                      if (ok == true) {
                        final success = await MapRepositoryImpl()
                            .deleteOrCloseDirectoryById(id);
                        if (success) {
                          _removeRowById(id);
                          onRowUpdated?.call();
                          try {
                            ctx.read<ContributionBloc>().add(
                              CreateContributionEvent(
                                actionType: 'delete',
                                targetType: 'direktori',
                                targetId: id,
                              ),
                            );
                          } catch (_) {}
                        }
                      }
                    },
                  ),
              ],
              if (!isEditing)
                _iconAction(
                  icon: Icons.edit_outlined,
                  color: Colors.orange,
                  tooltip: 'Edit',
                  onTap: (ctx) {
                    _editingIds.add(id);
                    _editedNamaById[id] = cells[1].value ?? '';
                    _editedAlamatById[id] = cells[2].value;
                    _editedEmailById[id] = cells[3].value;
                    notifyListeners();
                  },
                )
              else ...[
                if (_savingIds.contains(id))
                  Container(
                    width: 32,
                    height: 32,
                    decoration: const BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(6),
                    child: const CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                else ...[
                  _iconAction(
                    icon: Icons.save,
                    color: Colors.green,
                    tooltip: 'Simpan',
                    onTap: (ctx) async {
                      _savingIds.add(id);
                      notifyListeners();
                      if ((_editedStatusById[id] ?? status) == 9) {
                        final parent = _editedIdSbrDuplikatById[id];
                        if (parent == null || parent.trim().isEmpty) {
                          _savingIds.remove(id);
                          notifyListeners();
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Isi ID SBR duplikat terlebih dahulu',
                              ),
                              backgroundColor: Colors.red,
                              duration: Duration(milliseconds: 1000),
                            ),
                          );
                          return;
                        }
                      }
                      final currentSkala = _normalizeSkalaUsaha(
                        direktori.skalaUsaha,
                      );
                      final String? desiredUiSkala = _editedSkalaUsahaById[id];
                      final bool skalaChanged =
                          desiredUiSkala != null &&
                          desiredUiSkala != currentSkala;
                      final String? skalaToSave = skalaChanged
                          ? _toBackendSkalaUsaha(desiredUiSkala)
                          : null;
                      final ok = await MapRepositoryImpl()
                          .updateDirectoryBasicFields(
                            id,
                            namaUsaha: _editedNamaById[id],
                            alamat: _editedAlamatById[id],
                            email: _editedEmailById[id],
                            skalaUsaha: skalaToSave,
                            updateSkalaUsaha: skalaChanged,
                          );
                      if (ok) {
                        if (_editedNamaById[id] != null) {
                          _setNamaForId(id, _editedNamaById[id]!);
                        }
                        if (_editedAlamatById[id] != null) {
                          _setAlamatForId(id, _editedAlamatById[id]!);
                        }
                        if (_editedEmailById[id] != null) {
                          _setEmailForId(id, _editedEmailById[id]!);
                        }
                        if (skalaChanged && desiredUiSkala != null) {
                          _setSkalaUsahaForId(id, desiredUiSkala);
                        }
                        bool statusUpdated = false;
                        int? newStatus;
                        if (_editedStatusById[id] != null &&
                            _editedStatusById[id] != status) {
                          bool okStatus;
                          String? parent;
                          if (_editedStatusById[id] == 9) {
                            parent = _editedIdSbrDuplikatById[id];
                            okStatus = await MapRepositoryImpl()
                                .markDirectoryAsDuplicate(id, parent ?? '');
                          } else {
                            okStatus = await MapRepositoryImpl()
                                .updateDirectoryStatus(
                                  id,
                                  _editedStatusById[id]!,
                                );
                          }
                          if (okStatus) {
                            _setStatusForId(id, _editedStatusById[id]!);
                            if (_editedStatusById[id] == 9) {
                              _setIdSbrDuplikatForId(id, parent);
                            } else {
                              final cleared = await MapRepositoryImpl()
                                  .clearDirectoryDuplicateParent(id);
                              if (cleared) {
                                _setIdSbrDuplikatForId(id, null);
                              }
                            }
                            statusUpdated = true;
                            newStatus = _editedStatusById[id]!;
                          }
                        }
                        final Map<String, dynamic> changes = {};
                        if (_editedNamaById[id] != null) {
                          changes['nama_usaha'] = _editedNamaById[id];
                        }
                        if (_editedAlamatById[id] != null) {
                          changes['alamat'] = _editedAlamatById[id];
                        }
                        if (_editedEmailById[id] != null) {
                          changes['email'] = _editedEmailById[id];
                        }
                        if (skalaChanged && desiredUiSkala != null) {
                          changes['skala_usaha'] = desiredUiSkala;
                        }
                        if (statusUpdated && newStatus != null) {
                          changes['keberadaan_usaha'] = newStatus;
                          if (newStatus == 9 &&
                              _editedIdSbrDuplikatById[id]?.isNotEmpty ==
                                  true) {
                            changes['idsbr_duplikat'] =
                                _editedIdSbrDuplikatById[id];
                          }
                        }
                        if (changes.isNotEmpty) {
                          try {
                            ctx.read<ContributionBloc>().add(
                              CreateContributionEvent(
                                actionType: 'update',
                                targetType: 'direktori',
                                targetId: id,
                                changes: changes,
                              ),
                            );
                          } catch (_) {}
                        }
                        _markRowUpdated(id);
                      }
                      _editingIds.remove(id);
                      _editedStatusById.remove(id);
                      _editedIdSbrDuplikatById.remove(id);
                      _editedSkalaUsahaById.remove(id);
                      _editedEmailById.remove(id);
                      _savingIds.remove(id);
                      notifyListeners();
                    },
                  ),
                  _iconAction(
                    icon: Icons.close,
                    color: Colors.red,
                    tooltip: 'Batal',
                    onTap: (ctx) {
                      _editingIds.remove(id);
                      _editedStatusById.remove(id);
                      _editedSkalaUsahaById.remove(id);
                      notifyListeners();
                    },
                  ),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }

  String _getKeberadaanUsahaDescription(int? keberadaanUsaha) {
    if (keberadaanUsaha == null) return 'Undefined';
    switch (keberadaanUsaha) {
      case 1:
        return 'Aktif';
      case 2:
        return 'Tutup Sementara';
      case 3:
        return 'Belum Beroperasi';
      case 4:
        return 'Tutup';
      case 5:
        return 'Alih Usaha';
      case 6:
        return 'Tidak Ditemukan';
      case 7:
        return 'Aktif Pindah';
      case 8:
        return 'Aktif Nonrespon';
      case 9:
        return 'Duplikat';
      case 10:
        return 'Salah Kode Wilayah';
      default:
        return 'Tidak Diketahui';
    }
  }

  Color _getKeberadaanColor(int? keberadaanUsaha) {
    if (keberadaanUsaha == null) return Colors.grey;
    switch (keberadaanUsaha) {
      case 1:
        return Colors.green;
      case 4:
        return Colors.red;
      case 2:
      case 3:
      case 5:
      case 7:
      case 8:
        return Colors.orange;
      case 6:
      case 9:
      case 10:
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  void _setStatusForId(String id, int status) {
    final idx = _rows.indexWhere((r) {
      final d = r.getCells().last.value as Direktori;
      return d.id == id;
    });
    if (idx < 0) return;
    final old = _rows[idx].getCells();
    final updated = DataGridRow(
      cells: [
        old[0],
        old[1],
        old[2],
        old[3],
        old[4],
        DataGridCell<int?>(columnName: 'status', value: status),
        old[6],
        old[7],
        old[8],
      ],
    );
    _rows[idx] = updated;
    notifyListeners();
  }

  void _setIdSbrDuplikatForId(String id, String? parent) {
    final idx = _rows.indexWhere((r) {
      final d = r.getCells().last.value as Direktori;
      return d.id == id;
    });
    if (idx < 0) return;
    final old = _rows[idx].getCells();
    final updated = DataGridRow(
      cells: [
        old[0],
        old[1],
        old[2],
        old[3],
        old[4],
        old[5],
        DataGridCell<String?>(columnName: 'idsbr_duplikat', value: parent),
        old[7],
        old[8],
      ],
    );
    _rows[idx] = updated;
    notifyListeners();
  }

  void _setNamaForId(String id, String namaBaru) {
    final idx = _rows.indexWhere((r) {
      final d = r.getCells().last.value as Direktori;
      return d.id == id;
    });
    if (idx < 0) return;
    final old = _rows[idx].getCells();
    final updated = DataGridRow(
      cells: [
        old[0],
        DataGridCell<String>(columnName: 'nama', value: namaBaru),
        old[2],
        old[3],
        old[4],
        old[5],
        old[6],
        old[7],
        old[8],
      ],
    );
    _rows[idx] = updated;
    notifyListeners();
  }

  void _setAlamatForId(String id, String alamatBaru) {
    final idx = _rows.indexWhere((r) {
      final d = r.getCells().last.value as Direktori;
      return d.id == id;
    });
    if (idx < 0) return;
    final old = _rows[idx].getCells();
    final updated = DataGridRow(
      cells: [
        old[0],
        old[1],
        DataGridCell<String?>(columnName: 'alamat', value: alamatBaru),
        old[3],
        old[4],
        old[5],
        old[6],
        old[7],
        old[8],
      ],
    );
    _rows[idx] = updated;
    notifyListeners();
  }

  void _setEmailForId(String id, String emailBaru) {
    final idx = _rows.indexWhere((r) {
      final d = r.getCells().last.value as Direktori;
      return d.id == id;
    });
    if (idx < 0) return;
    final old = _rows[idx].getCells();
    final updated = DataGridRow(
      cells: [
        old[0],
        old[1],
        old[2],
        DataGridCell<String?>(columnName: 'email', value: emailBaru),
        old[4],
        old[5],
        old[6],
        old[7],
        old[8],
      ],
    );
    _rows[idx] = updated;
    notifyListeners();
  }

  void _setIdSbrForId(String id, String idSbrBaru) {
    final idx = _rows.indexWhere((r) {
      final d = r.getCells().last.value as Direktori;
      return d.id == id;
    });
    if (idx < 0) return;
    final old = _rows[idx].getCells();
    final updated = DataGridRow(
      cells: [
        DataGridCell<String>(columnName: 'id_sbr', value: idSbrBaru),
        old[1],
        old[2],
        old[3],
        old[4],
        old[5],
        old[6],
        old[7],
        old[8],
      ],
    );
    _rows[idx] = updated;
    notifyListeners();
  }

  void _setKoordinatForId(String id, bool hasCoord) {
    final idx = _rows.indexWhere((r) {
      final d = r.getCells().last.value as Direktori;
      return d.id == id;
    });
    if (idx < 0) return;
    final old = _rows[idx].getCells();
    final updated = DataGridRow(
      cells: [
        old[0],
        old[1],
        old[2],
        old[3],
        old[4],
        old[5],
        old[6],
        DataGridCell<bool>(columnName: 'koordinat', value: hasCoord),
        old[8],
      ],
    );
    _rows[idx] = updated;
    notifyListeners();
  }

  bool _hasKoordinatForId(String id) {
    final idx = _rows.indexWhere((r) {
      final d = r.getCells().last.value as Direktori;
      return d.id == id;
    });
    if (idx < 0) return false;
    final cells = _rows[idx].getCells();
    final bool hasCoord = cells[7].value as bool? ?? false;
    return hasCoord;
  }

  void _removeRowById(String id) {
    final idx = _rows.indexWhere((r) {
      final d = r.getCells().last.value as Direktori;
      return d.id == id;
    });
    if (idx < 0) return;
    _rows.removeAt(idx);
    notifyListeners();
  }

  void _markRowUpdated(String id) {
    _recentlyUpdatedIds.add(id);
    notifyListeners();
    onRowUpdated?.call();
    onRowUpdatedWithId?.call(id, DateTime.now().toUtc());
  }

  Widget _iconAction({
    required IconData icon,
    required Color color,
    required String tooltip,
    required void Function(BuildContext) onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Builder(
        builder: (ctx) => InkWell(
          onTap: () => onTap(ctx),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
        ),
      ),
    );
  }

  void _navigateToMap(BuildContext context, String focusId) {
    List<dynamic>? cached;
    try {
      final bloc = context.read<DirektoriBloc>();
      if (bloc.isAllLoaded) {
        cached = bloc.cachedAllList;
      }
    } catch (_) {}
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => const MainPage(initialTabIndex: 0),
        settings: RouteSettings(
          arguments: {
            'focusDirectoryId': focusId,
            if (cached != null) 'direktoriList': cached,
          },
        ),
      ),
    );
  }

  Future<void> _promptInputCoordinates(BuildContext context, String id) async {
    final controller = TextEditingController();
    final regex = RegExp(r'^\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*$');

    // Prefill from clipboard if available and valid
    double? initLat;
    double? initLng;
    bool initValid = false;
    try {
      final clip = await Clipboard.getData(Clipboard.kTextPlain);
      final text = clip?.text?.trim();
      if (text != null) {
        final m = regex.firstMatch(text);
        if (m != null) {
          final lt = double.tryParse(m.group(1)!);
          final lg = double.tryParse(m.group(2)!);
          final inRange =
              lt != null &&
              lg != null &&
              lt >= -90 &&
              lt <= 90 &&
              lg >= -180 &&
              lg <= 180;
          if (inRange) {
            controller.text =
                '${lt!.toStringAsFixed(15)}, ${lg!.toStringAsFixed(15)}';
            initLat = lt;
            initLng = lg;
            initValid = true;
          }
        }
      }
    } catch (_) {}

    final result = await showDialog<List<double>>(
      context: context,
      builder: (ctx) {
        bool valid = initValid;
        double? lat = initLat;
        double? lng = initLng;
        return StatefulBuilder(
          builder: (ctx, setState) => AlertDialog(
            title: const Text('Masukkan Koordinat'),
            content: TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: '-4.0118994376424615, 119.62250218148489',
              ),
              onChanged: (text) {
                final match = regex.firstMatch(text.trim());
                if (match == null) {
                  setState(() {
                    valid = false;
                    lat = null;
                    lng = null;
                  });
                  return;
                }
                final lt = double.tryParse(match.group(1)!);
                final lg = double.tryParse(match.group(2)!);
                final inRange =
                    lt != null &&
                    lg != null &&
                    lt >= -90 &&
                    lt <= 90 &&
                    lg >= -180 &&
                    lg <= 180;
                setState(() {
                  valid = inRange;
                  lat = lt;
                  lng = lg;
                });
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Batal'),
              ),
              TextButton(
                onPressed: valid && lat != null && lng != null
                    ? () => Navigator.of(ctx).pop(<double>[lat!, lng!])
                    : null,
                child: const Text('Simpan'),
              ),
            ],
          ),
        );
      },
    );
    if (result != null && result.length == 2) {
      final repo = MapRepositoryImpl();
      // Coba perbarui dengan data regional
      String idSls = '';
      String? kodePos;
      String? namaSls;
      String kdProv = '';
      String kdKab = '';
      String kdKec = '';
      String kdDesa = '';
      String kdSls = '';
      try {
        final polygons = await repo.getAllPolygonsMetaFromGeoJson(
          'assets/geojson/final_sls.geojson',
        );
        for (final polygon in polygons) {
          if (_isPointInPolygon(LatLng(result[0], result[1]), polygon.points)) {
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

      bool ok;
      final bool preHadCoord = _hasKoordinatForId(id);
      if (idSls.isNotEmpty) {
        ok = await repo.updateDirectoryCoordinatesWithRegionalData(
          id,
          result[0],
          result[1],
          idSls,
          kdProv,
          kdKab,
          kdKec,
          kdDesa,
          kdSls,
          kodePos,
          namaSls,
        );
      } else {
        ok = await repo.updateDirectoryCoordinates(id, result[0], result[1]);
      }

      if (ok) {
        if (!context.mounted) return;
        _setKoordinatForId(id, true);
        _markRowUpdated(id);
        try {
          final Map<String, dynamic> changes = {
            'latitude': result[0],
            'longitude': result[1],
            'action_subtype': preHadCoord
                ? 'update_coordinates'
                : 'set_first_coordinates',
          };
          if (idSls.isNotEmpty) {
            changes['id_sls'] = idSls;
          }
          context.read<ContributionBloc>().add(
            CreateContributionEvent(
              actionType: 'update',
              targetType: 'direktori',
              targetId: id,
              changes: changes,
              latitude: result[0],
              longitude: result[1],
            ),
          );
        } catch (_) {}

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Koordinat disimpan'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Gagal menyimpan koordinat'),
            backgroundColor: Colors.red,
          ),
        );
      }
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

  Future<void> _pickStatus(
    BuildContext context,
    String id,
    int? current,
  ) async {
    final int? selected = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Pilih Status Keberadaan'),
        children: [
          _statusItem(ctx, 1, 'Aktif'),
          _statusItem(ctx, 2, 'Tutup Sementara'),
          _statusItem(ctx, 3, 'Belum Beroperasi'),
          _statusItem(ctx, 4, 'Tutup'),
          _statusItem(ctx, 5, 'Alih Usaha'),
          _statusItem(ctx, 6, 'Tidak Ditemukan'),
          _statusItem(ctx, 7, 'Aktif Pindah'),
          _statusItem(ctx, 8, 'Aktif Nonrespon'),
          _statusItem(ctx, 9, 'Duplikat'),
          _statusItem(ctx, 10, 'Salah Kode Wilayah'),
        ],
      ),
    );
    if (selected != null) {
      _editedStatusById[id] = selected;
      if (selected == 9) {
        try {
          final data = await Clipboard.getData(Clipboard.kTextPlain);
          final txt = data?.text?.trim();
          if ((txt ?? '').isNotEmpty) {
            _editedIdSbrDuplikatById[id] = txt!;
          }
        } catch (_) {}
      }
      notifyListeners();
    }
  }

  Future<String?> _pickSkalaFilter(
    BuildContext context,
    String? current,
  ) async {
    final String? selected = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Filter Skala Usaha'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop('UMKM'),
            child: Row(
              children: [
                Icon(Icons.filter_alt, size: 16, color: Colors.blue[600]),
                const SizedBox(width: 8),
                const Text('UMKM', style: TextStyle(fontSize: 13)),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop('UB'),
            child: Row(
              children: [
                Icon(Icons.filter_alt, size: 16, color: Colors.blue[600]),
                const SizedBox(width: 8),
                const Text('UB', style: TextStyle(fontSize: 13)),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(''),
            child: Row(
              children: [
                Icon(Icons.filter_alt_off, size: 16, color: Colors.grey[700]),
                const SizedBox(width: 8),
                const Text('Semua', style: TextStyle(fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
    return selected;
  }

  Widget _statusItem(BuildContext ctx, int value, String label) {
    return SimpleDialogOption(
      onPressed: () => Navigator.of(ctx).pop(value),
      child: Row(
        children: [
          Icon(Icons.radio_button_checked, size: 16, color: Colors.blue[600]),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }

  Future<void> _promptDuplicateParent(BuildContext context, String id) async {
    final controller = TextEditingController(
      text: _editedIdSbrDuplikatById[id] ?? '',
    );
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ID SBR Duplikat (Parent)'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Masukkan ID SBR parent'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () {
              final v = controller.text.trim();
              if (v.isNotEmpty) {
                Navigator.of(ctx).pop(v);
              }
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (result != null && result.trim().isNotEmpty) {
      _editedIdSbrDuplikatById[id] = result.trim();
    }
  }

  void _setSkalaUsahaForId(String id, String skala) {
    final idx = _rows.indexWhere((r) {
      final d = r.getCells().last.value as Direktori;
      return d.id == id;
    });
    if (idx < 0) return;
    final old = _rows[idx].getCells();
    final updated = DataGridRow(
      cells: [
        old[0],
        old[1],
        old[2],
        old[3],
        DataGridCell<String?>(columnName: 'skala_usaha', value: skala),
        old[5],
        old[6],
        old[7],
        old[8],
      ],
    );
    _rows[idx] = updated;
    notifyListeners();
  }

  String? _normalizeSkalaUsaha(String? value) {
    if (value == null) return 'UMKM';
    final v = value.trim().toUpperCase();
    return v == 'UB' ? 'UB' : 'UMKM';
  }

  String? _toBackendSkalaUsaha(String? uiValue) {
    if (uiValue == null) return null;
    final v = uiValue.trim().toUpperCase();
    if (v == 'UB') return 'UB';
    if (v == 'UMKM') return 'UMKM';
    return null;
  }
}

class _DetailDialog extends StatefulWidget {
  final Direktori direktori;
  final void Function(String id)? onGoToMap;

  const _DetailDialog({super.key, required this.direktori, this.onGoToMap});

  @override
  State<_DetailDialog> createState() => _DetailDialogState();
}

class _DetailDialogState extends State<_DetailDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _showNik = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _navigateToMap(BuildContext context, String focusId) {
    List<dynamic>? cached;
    try {
      final bloc = context.read<DirektoriBloc>();
      if (bloc.isAllLoaded) {
        cached = bloc.cachedAllList;
      }
    } catch (_) {}
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => const MainPage(initialTabIndex: 0),
        settings: RouteSettings(
          arguments: {
            'focusDirectoryId': focusId,
            if (cached != null) 'direktoriList': cached,
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.direktori;
    final width = MediaQuery.of(context).size.width;
    final isLargeScreen = width > 800;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isLargeScreen ? width * 0.15 : 16,
        vertical: 24,
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 1000, maxHeight: 800),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            _buildHeader(d),
            Container(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
              ),
              child: TabBar(
                controller: _tabController,
                labelColor: Colors.blue.shade700,
                unselectedLabelColor: Colors.grey.shade600,
                indicatorColor: Colors.blue.shade700,
                indicatorWeight: 3,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
                tabs: const [
                  Tab(text: 'Ringkasan'),
                  Tab(text: 'Kontak'),
                  Tab(text: 'Legalitas & Lainnya'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildRingkasanTab(d),
                  _buildKontakTab(d),
                  _buildLegalitasTab(d),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.grey.shade700,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                    ),
                    child: const Text('Tutup'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(Direktori d) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade100,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.business, color: Colors.blue.shade700, size: 32),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  d.namaUsaha,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                if (d.namaKomersialUsaha != null &&
                    d.namaKomersialUsaha!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '(${d.namaKomersialUsaha})',
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _Badge(
                      label: 'ID SBR: ${d.idSbr}',
                      color: Colors.blue.shade100,
                      textColor: Colors.blue.shade900,
                    ),
                    if (d.keberadaanUsaha != null)
                      _StatusBadge(status: d.keberadaanUsaha!),
                  ],
                ),
              ],
            ),
          ),
          if ((d.latitude ?? d.lat) != null && (d.longitude ?? d.long) != null)
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: ElevatedButton.icon(
                onPressed: () {
                  if (widget.onGoToMap != null) {
                    widget.onGoToMap!(d.id);
                  } else {
                    _navigateToMap(context, d.id);
                  }
                },
                icon: const Icon(Icons.map_outlined, size: 18),
                label: const Text('Lihat Peta'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRingkasanTab(Direktori d) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(title: 'Informasi Utama'),
          const SizedBox(height: 16),
          if (d.urlGambar != null && d.urlGambar!.isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: GestureDetector(
                onTap: () async {
                  try {
                    final uri = Uri.parse(d.urlGambar!);
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  } catch (_) {}
                },
                child: SizedBox(
                  width: double.infinity,
                  height: 200,
                  child: Image.network(
                    d.urlGambar!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: Colors.grey.shade200,
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.image_not_supported,
                              color: Colors.grey,
                              size: 28,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Gambar tidak tersedia',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 12,
                              ),
                            ),
                            TextButton(
                              onPressed: () async {
                                try {
                                  final uri = Uri.parse(d.urlGambar!);
                                  if (await canLaunchUrl(uri)) {
                                    await launchUrl(
                                      uri,
                                      mode: LaunchMode.externalApplication,
                                    );
                                  }
                                } catch (_) {}
                              },
                              child: const Text('Buka di browser'),
                            ),
                          ],
                        ),
                      );
                    },
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return Container(
                        color: Colors.grey.shade100,
                        alignment: Alignment.center,
                        child: const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 600;
              return GridView.count(
                crossAxisCount: isWide ? 4 : 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 2.5,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                children: [
                  _StatCard(
                    label: 'Tahun Berdiri',
                    value: d.tahunBerdiri?.toString() ?? '-',
                    icon: Icons.calendar_today,
                  ),
                  _StatCard(
                    label: 'Tenaga Kerja',
                    value: d.tenagaKerja?.toString() ?? '-',
                    icon: Icons.people,
                  ),
                  _StatCard(
                    label: 'Skala Usaha',
                    value: d.skalaUsaha ?? '-',
                    icon: Icons.bar_chart,
                  ),
                  _StatCard(
                    label: 'Jaringan',
                    value: _getJaringanText(d.jaringanUsaha),
                    icon: Icons.hub,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 32),

          _SectionTitle(title: 'Kegiatan Usaha (KBLI)'),
          const SizedBox(height: 16),
          if (d.kbli != null && d.kbli!.isNotEmpty)
            FutureBuilder<String?>(
              future: MapRepositoryImpl().getKbliTitle(d.kbli!),
              builder: (context, snapshot) {
                final title = snapshot.data;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: _KbliCard(
                    code: d.kbli!,
                    title: (title == null || title.isEmpty)
                        ? 'Tidak diketahui'
                        : title,
                  ),
                );
              },
            ),
          // Tampilkan list kegiatan usaha jika ada
          if (d.kegiatanUsaha.isNotEmpty)
            ...d.kegiatanUsaha.map(
              (k) => _KbliCard(
                code: k['kbli']?.toString() ?? '-',
                title: k['judul_kbli']?.toString() ?? 'Tidak diketahui',
                category: k['kategori_kbli']?.toString(),
              ),
            ),
          // Jika keduanya kosong
          if ((d.kbli == null || d.kbli!.isEmpty) && d.kegiatanUsaha.isEmpty)
            const Text(
              'Tidak ada data KBLI',
              style: TextStyle(color: Colors.grey),
            ),

          if (d.tag != null && d.tag!.isNotEmpty) ...[
            const SizedBox(height: 32),
            _SectionTitle(title: 'Tags'),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: d.tag!
                  .map(
                    (tag) => Chip(
                      label: Text(tag),
                      backgroundColor: Colors.blue.shade50,
                      labelStyle: TextStyle(
                        color: Colors.blue.shade800,
                        fontWeight: FontWeight.w500,
                      ),
                      side: BorderSide(color: Colors.blue.shade100),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                    ),
                  )
                  .toList(),
            ),
          ],

          const SizedBox(height: 32),
          _SectionTitle(title: 'Detail Perusahaan'),
          const SizedBox(height: 16),
          _DetailRow(
            label: 'Jenis Perusahaan',
            value: d.jenisPerusahaan,
            icon: Icons.business_center,
          ),
          _DetailRow(
            label: 'Kepemilikan',
            value: _getKepemilikanText(d.jenisKepemilikanUsaha),
            icon: Icons.person_outline,
          ),
          _DetailRow(
            label: 'Sektor Institusi',
            value: _getSektorText(d.sektorInstitusi),
            icon: Icons.category,
          ),
          _DetailRow(
            label: 'Keterangan',
            value: d.keterangan,
            icon: Icons.info_outline,
          ),
          _DetailRow(
            label: 'Deskripsi Lainnya',
            value: d.deskripsiBadanUsahaLainnya,
            icon: Icons.description,
          ),
          const SizedBox(height: 32),
          _SectionTitle(title: 'Lokasi'),
          const SizedBox(height: 16),
          _DetailRow(label: 'Alamat', value: d.alamat, icon: Icons.location_on),
          _DetailRow(
            label: 'Kode Pos',
            value: d.kodePos,
            icon: Icons.markunread_mailbox,
          ),
          _DetailRow(label: 'Provinsi', value: d.nmProv, icon: Icons.map),
          _DetailRow(
            label: 'Kab/Kota',
            value: d.nmKab,
            icon: Icons.location_city,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildKontakTab(Direktori d) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(title: 'Kontak'),
          const SizedBox(height: 16),
          _DetailRow(
            label: 'Telepon',
            value: d.nomorTelepon,
            isCopyable: true,
            icon: Icons.phone,
          ),
          _DetailRow(
            label: 'WhatsApp',
            value: d.nomorWhatsapp,
            isCopyable: true,
            icon: Icons.chat,
          ),
          _DetailRow(
            label: 'Email',
            value: d.email,
            isCopyable: true,
            icon: Icons.email,
          ),
          _DetailRow(
            label: 'Website',
            value: d.website,
            isLink: true,
            icon: Icons.language,
          ),
        ],
      ),
    );
  }

  Widget _buildLegalitasTab(Direktori d) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(title: 'Legalitas'),
          const SizedBox(height: 16),
          _DetailRow(
            label: 'NIB',
            value: d.nib,
            isCopyable: true,
            icon: Icons.verified_user,
          ),
          _DetailRow(
            label: 'Bentuk Hukum',
            value: _getBadanHukumText(d.bentukBadanHukumUsaha),
            icon: Icons.gavel,
          ),

          const SizedBox(height: 32),
          _SectionTitle(title: 'Identitas Pemilik'),
          const SizedBox(height: 16),
          _DetailRow(
            label: 'Nama Pemilik',
            value: d.pemilik,
            icon: Icons.person,
          ),
          _DetailRow(
            label: 'No. HP Pemilik',
            value: d.nohpPemilik,
            isCopyable: true,
            icon: Icons.phone_android,
          ),
          if (d.nikPemilik != null && d.nikPemilik!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.badge, size: 20, color: Colors.grey.shade400),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 140,
                    child: Text(
                      'NIK Pemilik',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        Text(
                          _showNik ? d.nikPemilik! : '••••••••••••••••',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: () => setState(() => _showNik = !_showNik),
                          child: Icon(
                            _showNik ? Icons.visibility_off : Icons.visibility,
                            size: 18,
                            color: Colors.blue,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 32),
          _SectionTitle(title: 'Metadata'),
          const SizedBox(height: 16),
          _DetailRow(
            label: 'Sumber Data',
            value: d.sumberData,
            icon: Icons.source,
          ),
          _DetailRow(
            label: 'Dibuat',
            value: _formatDate(d.createdAt),
            icon: Icons.calendar_today,
          ),
          _DetailRow(
            label: 'Diperbarui',
            value: _formatDate(d.updatedAt),
            icon: Icons.update,
          ),
          _DetailRow(
            label: 'ID System',
            value: d.id,
            isSmall: true,
            icon: Icons.fingerprint,
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return '-';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  String _getJaringanText(int? code) {
    if (code == 1) {
      return 'Tunggal';
    }
    if (code == 2) {
      return 'Pusat';
    }
    if (code == 3) {
      return 'Cabang';
    }
    return '-';
  }

  String _getKepemilikanText(int? code) {
    // Implement mapping if available, otherwise return raw or generic
    return code?.toString() ?? '-';
  }

  String _getSektorText(int? code) {
    // Implement mapping if available
    return code?.toString() ?? '-';
  }

  String _getBadanHukumText(int? code) {
    if (code == null) return '-';
    return 'Kode $code';
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatCard({
    Key? key,
    required this.label,
    required this.value,
    required this.icon,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.05),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.blue.shade700, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Colors.black87,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _KbliCard extends StatelessWidget {
  final String code;
  final String title;
  final String? category;

  const _KbliCard({
    Key? key,
    required this.code,
    required this.title,
    this.category,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.teal.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.teal.shade200),
              ),
              child: Text(
                code,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.teal.shade800,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  if (category != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        category!,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final int status;

  const _StatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    String text;
    switch (status) {
      case 1:
        color = Colors.green;
        text = 'Aktif';
        break;
      case 2:
        color = Colors.orange;
        text = 'Tutup Sementara';
        break;
      case 3:
        color = Colors.orange;
        text = 'Belum Beroperasi';
        break;
      case 4:
        color = Colors.red;
        text = 'Tutup';
        break;
      default:
        color = Colors.grey;
        text = 'Lainnya';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({Key? key, required this.title}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.blue.shade900,
          ),
        ),
        const SizedBox(height: 4),
        Container(width: 40, height: 3, color: Colors.blue.shade200),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String? value;
  final bool isCopyable;
  final bool isLink;
  final bool isSmall;
  final IconData? icon;

  const _DetailRow({
    Key? key,
    required this.label,
    required this.value,
    this.isCopyable = false,
    this.isLink = false,
    this.isSmall = false,
    this.icon,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (value == null || value!.isEmpty || value == '-') {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20, color: Colors.grey.shade400),
            const SizedBox(width: 12),
          ],
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
            ),
          ),
          Expanded(
            child: isLink
                ? InkWell(
                    onTap: () => launchUrl(
                      Uri.parse(
                        value!.startsWith('http') ? value! : 'https://$value',
                      ),
                      mode: LaunchMode.externalApplication,
                    ),
                    child: Text(
                      value!,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.blue,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  )
                : Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          value!,
                          style: TextStyle(
                            fontSize: isSmall ? 12 : 14,
                            fontWeight: FontWeight.w500,
                            color: isSmall ? Colors.grey[600] : Colors.black87,
                          ),
                        ),
                      ),
                      if (isCopyable)
                        InkWell(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: value!));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Disalin ke clipboard'),
                                duration: Duration(milliseconds: 500),
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.only(left: 8.0),
                            child: Icon(
                              Icons.copy,
                              size: 16,
                              color: Colors.grey.shade400,
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  final Color? textColor;

  const _Badge({
    Key? key,
    required this.label,
    required this.color,
    this.textColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: textColor ?? Colors.black87,
        ),
      ),
    );
  }
}
