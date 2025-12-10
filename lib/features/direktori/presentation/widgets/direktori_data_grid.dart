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
  }) : super(key: key);

  @override
  State<DirektoriDataGrid> createState() => _DirektoriDataGridState();
}

class _DirektoriDataGridState extends State<DirektoriDataGrid> {
  late final DataGridController _gridController;
  late final _DirektoriDataGridSource _source;

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
  }

  @override
  void didUpdateWidget(covariant DirektoriDataGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.direktoriList, oldWidget.direktoriList)) {
      _source.updateData(widget.direktoriList);
    }
  }

  @override
  Widget build(BuildContext context) {
    final double availableWidth =
        MediaQuery.of(context).size.width - 32; // margin horizontal 16*2
    const Map<String, int> weights = {
      'id_sbr': 1,
      'nama': 3,
      'alamat': 3,
      'status': 2,
      'koordinat': 2,
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
                selectionMode: SelectionMode.single,
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
      ],
    );
  }

  void _showDetailDialog(BuildContext context, Direktori direktori) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Detail'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              direktori.namaUsaha,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(direktori.namaKomersialUsaha ?? ''),
            const SizedBox(height: 8),
            Text(direktori.alamat ?? '-'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Tutup'),
          ),
        ],
      ),
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
  final Map<String, int?> _editedStatusById = <String, int?>{};
  final Set<String> _savingIds = <String>{};
  final Set<String> _recentlyUpdatedIds = <String>{};

  _DirektoriDataGridSource({
    required this.data,
    required this.onDetail,
    this.onGoToMap,
    this.onRowUpdated,
    this.onRowUpdatedWithId,
  }) {
    _rows = data
        .map(
          (d) => DataGridRow(
            cells: [
              DataGridCell<String>(columnName: 'id_sbr', value: d.idSbr),
              DataGridCell<String>(columnName: 'nama', value: d.namaUsaha),
              DataGridCell<String?>(columnName: 'alamat', value: d.alamat),
              DataGridCell<int?>(
                columnName: 'status',
                value: d.keberadaanUsaha,
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
        .map(
          (d) => DataGridRow(
            cells: [
              DataGridCell<String>(columnName: 'id_sbr', value: d.idSbr),
              DataGridCell<String>(columnName: 'nama', value: d.namaUsaha),
              DataGridCell<String?>(columnName: 'alamat', value: d.alamat),
              DataGridCell<int?>(
                columnName: 'status',
                value: d.keberadaanUsaha,
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
    final int? status = cells[3].value as int?;
    final bool hasCoord = cells[4].value as bool;
    final DateTime? updatedAt = direktori.updatedAt;
    final String id = direktori.id;
    final bool isEditing = _editingIds.contains(id);
    final DateTime threshold = DateTime.parse('2025-11-01 13:35:36.438909+00');
    final bool isRowUpdated =
        _recentlyUpdatedIds.contains(id) ||
        (updatedAt != null && updatedAt.isAfter(threshold));

    return DataGridRowAdapter(
      color: isRowUpdated ? const Color(0xFFE9F7EF) : null,
      cells: [
        Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Text(
            cells[0].value ?? '-',
            style: const TextStyle(fontSize: 12, color: Colors.black87),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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
                Builder(
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              if (!isEditing &&
                  direktori.namaKomersialUsaha?.isNotEmpty == true) ...[
                const SizedBox(height: 2),
                Text(
                  direktori.namaKomersialUsaha!,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
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
              : Text(
                  cells[2].value ?? '-',
                  style: const TextStyle(fontSize: 13),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
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
                      final ok = await MapRepositoryImpl()
                          .updateDirectoryBasicFields(
                            id,
                            namaUsaha: _editedNamaById[id],
                            alamat: _editedAlamatById[id],
                          );
                      if (ok) {
                        if (_editedNamaById[id] != null) {
                          _setNamaForId(id, _editedNamaById[id]!);
                        }
                        if (_editedAlamatById[id] != null) {
                          _setAlamatForId(id, _editedAlamatById[id]!);
                        }
                        bool statusUpdated = false;
                        int? newStatus;
                        if (_editedStatusById[id] != null &&
                            _editedStatusById[id] != status) {
                          final okStatus = await MapRepositoryImpl()
                              .updateDirectoryStatus(
                                id,
                                _editedStatusById[id]!,
                              );
                          if (okStatus) {
                            _setStatusForId(id, _editedStatusById[id]!);
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
                        if (statusUpdated && newStatus != null) {
                          changes['keberadaan_usaha'] = newStatus;
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
        DataGridCell<int?>(columnName: 'status', value: status),
        old[4],
        old[5],
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
        DataGridCell<bool>(columnName: 'koordinat', value: hasCoord),
        old[5],
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
    final bool hasCoord = cells[4].value as bool? ?? false;
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
      notifyListeners();
    }
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
}
