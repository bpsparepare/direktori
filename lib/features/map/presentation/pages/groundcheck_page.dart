import 'dart:convert';
import 'dart:math';
import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/services/bps_gc_service.dart';
import '../../data/services/groundcheck_supabase_service.dart';
import '../../data/constants/wilayah_mapping.dart';
import '../../data/constants/wilayah_mapping_sidrap.dart';
import '../widgets/inappwebview_login_dialog.dart';
import '../bloc/map_bloc.dart';
import '../bloc/map_event.dart';
import '../bloc/map_state.dart';
import '../../data/repositories/map_repository_impl.dart';
import '../utils/map_download_helper.dart';
import '../../../../../core/services/account_manager_service.dart';

// Optional bootstrap via --dart-define (removed)

import '../../domain/entities/groundcheck_record.dart';

class GroundcheckDataSource extends DataGridSource {
  late List<DataGridRow> _rows;
  final Map<DataGridRow, GroundcheckRecord> _rowToRecord = {};
  final void Function(GroundcheckRecord record)? onGcPressed;
  final void Function(GroundcheckRecord record)? onGoToMap;
  Map<String, String>? comparisonMap;

  GroundcheckDataSource({
    required List<GroundcheckRecord> data,
    this.onGcPressed,
    this.onGoToMap,
    this.comparisonMap,
  }) {
    _buildRows(data);
  }

  void updateComparisonMap(Map<String, String>? map) {
    comparisonMap = map;
    notifyListeners();
  }

  @override
  List<DataGridRow> get rows => _rows;

  GroundcheckRecord? getRecord(DataGridRow row) => _rowToRecord[row];

  @override
  int compare(DataGridRow? a, DataGridRow? b, SortColumnDetails sortColumn) {
    if (sortColumn.name == 'nama_usaha') {
      final value1 = a
          ?.getCells()
          .firstWhere((element) => element.columnName == sortColumn.name)
          .value
          ?.toString();
      final value2 = b
          ?.getCells()
          .firstWhere((element) => element.columnName == sortColumn.name)
          .value
          ?.toString();

      if (value1 == null || value2 == null) {
        return 0;
      }

      final int comparison = value1.toLowerCase().compareTo(
        value2.toLowerCase(),
      );

      if (sortColumn.sortDirection == DataGridSortDirection.descending) {
        return -comparison;
      }
      return comparison;
    }
    return super.compare(a, b, sortColumn);
  }

  @override
  DataGridRowAdapter buildRow(DataGridRow row) {
    final record = _rowToRecord[row];
    return DataGridRowAdapter(
      cells: row.getCells().map((cell) {
        if (cell.columnName == 'isUploaded') {
          final isUploaded = cell.value as bool? ?? false;
          final isRevisi = record?.isRevisi ?? false;

          if (isRevisi) {
            return const Center(
              child: Tooltip(
                message: 'Perlu Kirim Ulang (Revisi)',
                child: Icon(Icons.sync_problem, color: Colors.orange, size: 20),
              ),
            );
          }

          return Center(
            child: Icon(
              isUploaded ? Icons.cloud_done : Icons.cloud_off,
              color: isUploaded ? Colors.green : Colors.grey,
              size: 20,
            ),
          );
        }
        if (cell.columnName == 'gcs_result') {
          final raw = (cell.value ?? '').toString().trim();
          final lower = raw.toLowerCase();
          String code = raw;
          String label = raw;
          MaterialColor base = Colors.grey;
          if (lower.isEmpty || lower == '-- pilih --') {
            code = '';
            label = 'Belum GC';
            base = Colors.grey;
          } else if (lower == '99' || lower.contains('tidak ditemukan')) {
            code = '99';
            label = 'Tidak Ditemukan';
            base = Colors.red;
          } else if (lower == '1' || lower.contains('ditemukan')) {
            code = '1';
            label = 'Ditemukan';
            base = Colors.green;
          } else if (lower == '3' || lower.contains('tutup')) {
            code = '3';
            label = 'Tutup';
            base = Colors.blueGrey;
          } else if (lower == '4' || lower.contains('ganda')) {
            code = '4';
            label = 'Ganda';
            base = Colors.orange;
          } else if (lower == '5' || lower.contains('usaha baru')) {
            code = '5';
            label = 'Usaha Baru';
            base = Colors.blue;
          } else {
            label = raw;
            base = Colors.blueGrey;
          }

          // Check comparison logic
          if (comparisonMap != null && record != null) {
            final compareVal = comparisonMap![record.idsbr];
            // Only highlight if comparison exists and is different
            if (compareVal != null && compareVal != raw) {
              label = '$label (Excel: $compareVal)';
              base = Colors.purple;
            }
          }

          return Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Chip(
              label: Text(
                code.isNotEmpty && !label.contains('Excel:')
                    ? '$code. $label'
                    : label,
                style: TextStyle(color: base.shade700, fontSize: 12),
              ),
              backgroundColor: base.withValues(alpha: 0.12),
              shape: StadiumBorder(
                side: BorderSide(color: base.withValues(alpha: 0.3)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              visualDensity: VisualDensity.compact,
            ),
          );
        }
        if (cell.columnName == 'gcs_result_excel') {
          final idsbr = (cell.value ?? '').toString();
          String compareVal = '-';
          if (comparisonMap != null && comparisonMap!.containsKey(idsbr)) {
            compareVal = comparisonMap![idsbr] ?? '-';
          }

          // Format value for display similar to gcs_result logic
          final raw = compareVal;
          final lower = raw.toLowerCase();
          String label = raw;
          MaterialColor base = Colors.grey;

          if (lower == '99' || lower.contains('tidak ditemukan')) {
            label = 'Tidak Ditemukan';
            base = Colors.red;
          } else if (lower == '1' || lower.contains('ditemukan')) {
            label = 'Ditemukan';
            base = Colors.green;
          } else if (lower == '3' || lower.contains('tutup')) {
            label = 'Tutup';
            base = Colors.blueGrey;
          } else if (lower == '4' || lower.contains('ganda')) {
            label = 'Ganda';
            base = Colors.orange;
          } else if (lower == '5' || lower.contains('usaha baru')) {
            label = 'Usaha Baru';
            base = Colors.blue;
          } else if (lower == '-' || lower.isEmpty || lower == 'null') {
            label = '-';
            base = Colors.grey;
          } else {
            label = raw;
            base = Colors.blueGrey;
          }

          if (raw != '-' &&
              raw.isNotEmpty &&
              raw != 'null' &&
              !label.contains(raw) &&
              label != raw) {
            // If raw is a code like "1", and label is "Ditemukan", show "1. Ditemukan"
            // But my logic above sets label to "Ditemukan" directly.
            // Let's mimic the gcs_result logic more closely if needed.
            // For now, let's just prepend raw if it's short (likely a code).
            if (raw.length <= 2) {
              label = '$raw. $label';
            }
          } else if (label != raw && raw.length <= 2) {
            label = '$raw. $label';
          }

          return Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Chip(
              label: Text(
                label,
                style: TextStyle(color: base.shade700, fontSize: 12),
              ),
              backgroundColor: base.withValues(alpha: 0.12),
              shape: StadiumBorder(
                side: BorderSide(color: base.withValues(alpha: 0.3)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              visualDensity: VisualDensity.compact,
            ),
          );
        }
        if (cell.columnName == 'gc_action' && record != null) {
          final lat = double.tryParse(record.latitude);
          final lon = double.tryParse(record.longitude);
          final hasCoord =
              lat != null && lon != null && lat != 0.0 && lon != 0.0;

          return Center(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                if (hasCoord)
                  Tooltip(
                    message: 'Buka peta (Go to)',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => onGoToMap?.call(record),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.teal.withValues(alpha: 0.1),
                        ),
                        child: const Icon(
                          Icons.map,
                          color: Colors.teal,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                if (record.gcsResult.isNotEmpty && !record.isUploaded)
                  ElevatedButton(
                    onPressed: () => onGcPressed?.call(record),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    child: const Text('GC', style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),
          );
        }
        return Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            cell.value?.toString() ?? '',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        );
      }).toList(),
    );
  }

  void updateData(List<GroundcheckRecord> data) {
    _buildRows(data);
    notifyListeners();
  }

  void _buildRows(List<GroundcheckRecord> data) {
    _rowToRecord.clear();
    _rows = data.map((e) {
      final row = DataGridRow(
        cells: [
          DataGridCell<String>(columnName: 'idsbr', value: e.idsbr),
          DataGridCell<String>(columnName: 'nama_usaha', value: e.namaUsaha),
          DataGridCell<String>(
            columnName: 'alamat_usaha',
            value: e.alamatUsaha,
          ),
          DataGridCell<String>(
            columnName: 'kode_wilayah',
            value: e.kodeWilayah,
          ),
          DataGridCell<String>(columnName: 'gcs_result_excel', value: e.idsbr),
          DataGridCell<String>(columnName: 'sumber_data', value: e.sumberData),
          DataGridCell<bool>(columnName: 'isUploaded', value: e.isUploaded),
          DataGridCell<String>(columnName: 'gcs_result', value: e.gcsResult),
          DataGridCell<String>(columnName: 'gc_username', value: e.gcUsername),
          DataGridCell<String>(columnName: 'gc_action', value: e.perusahaanId),
        ],
      );
      _rowToRecord[row] = e;
      return row;
    }).toList();
  }
}

class _SidrapManagerDialog extends StatefulWidget {
  final BpsGcService gcService;
  final Function(List<Map<String, String>>) onProcessAll;
  final String? gcToken;
  final String? gcCookie;
  final String? userAgent;
  final String? csrfToken;

  const _SidrapManagerDialog({
    Key? key,
    required this.gcService,
    required this.onProcessAll,
    this.gcToken,
    this.gcCookie,
    this.userAgent,
    this.csrfToken,
  }) : super(key: key);

  @override
  _SidrapManagerDialogState createState() => _SidrapManagerDialogState();
}

class _SidrapManagerDialogState extends State<_SidrapManagerDialog> {
  List<Map<String, String>> _data = [];
  final Set<int> _processingIndices = {};
  final Set<int> _successIndices = {};
  final Set<int> _selectedIndices = {};
  String? _error;

  Future<void> _pasteFromClipboard() async {
    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    final text = clipboardData?.text;

    if (text == null || text.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Clipboard kosong')));
      }
      return;
    }

    // Parsing data
    // Format: nama_usaha | alamat | lat | long | kode_wilayah
    final lines = text.trim().split('\n');
    final List<Map<String, String>> parsedData = [];
    final List<String> errors = [];

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      final cols = line.split('\t');
      if (cols.length < 5) {
        errors.add('Baris ${i + 1}: Kolom kurang (${cols.length}/5)');
        continue;
      }

      final namaUsaha = cols[0].trim();
      final alamat = cols[1].trim();
      var lat = cols[2].trim();
      var long = cols[3].trim();
      final kodeWilayah = cols[4].trim();

      // Clean coordinates
      // 1. Remove quotes
      lat = lat.replaceAll('"', '').replaceAll("'", "");
      long = long.replaceAll('"', '').replaceAll("'", "");

      // 2. Replace comma with dot
      lat = lat.replaceAll(',', '.');
      long = long.replaceAll(',', '.');

      // Validasi sederhana
      if (namaUsaha.isEmpty || kodeWilayah.length < 10) {
        errors.add('Baris ${i + 1}: Data tidak valid (Nama/Kode Wilayah)');
        continue;
      }

      // Validasi koordinat
      if (double.tryParse(lat) == null || double.tryParse(long) == null) {
        errors.add('Baris ${i + 1}: Koordinat tidak valid ($lat, $long)');
        continue;
      }

      parsedData.add({
        'nama_usaha': namaUsaha,
        'alamat': alamat,
        'latitude': lat,
        'longitude': long,
        'kode_wilayah': kodeWilayah,
      });
    }

    if (parsedData.isEmpty) {
      setState(() {
        _error =
            'Tidak ada data valid ditemukan.\n\nError:\n${errors.join('\n')}';
      });
    } else {
      setState(() {
        _data = parsedData;
        _error = errors.isNotEmpty ? '${errors.length} data diabaikan' : null;
        _successIndices.clear();
        _processingIndices.clear();
        // Default select all
        _selectedIndices.clear();
        for (int i = 0; i < _data.length; i++) {
          _selectedIndices.add(i);
        }
      });
    }
  }

  Future<void> _sendSingle(int index) async {
    final item = _data[index];
    setState(() {
      _processingIndices.add(index);
    });

    try {
      if (widget.gcCookie != null && widget.userAgent != null) {
        widget.gcService.setCredentials(
          cookie: widget.gcCookie!,
          csrfToken: widget.csrfToken ?? '',
          gcToken: widget.gcToken ?? '',
          userAgent: widget.userAgent!,
        );
      }

      final rawKode = item['kode_wilayah'] ?? '';
      final kecCode = rawKode.substring(4, 7);
      final desaCode = rawKode.substring(7, 10);
      final serverKecId = WilayahMappingSidrap.getKecamatanId(kecCode);
      final serverDesaId = WilayahMappingSidrap.getDesaId(kecCode, desaCode);

      final result = await widget.gcService.saveDraftTambahUsaha(
        namaUsaha: item['nama_usaha'] ?? '',
        alamat: item['alamat'] ?? '',
        provinsiId: WilayahMappingSidrap.serverProvinsiId,
        kabupatenId: WilayahMappingSidrap.serverKabupatenId,
        kecamatanId: serverKecId,
        desaId: serverDesaId,
        latitude: item['latitude'] ?? '0',
        longitude: item['longitude'] ?? '0',
      );

      if (result != null && result['success'] == true) {
        if (mounted) {
          setState(() {
            _successIndices.add(index);
            _selectedIndices.remove(index); // Deselect if success
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Berhasil: ${item['nama_usaha']}')),
          );
        }
      } else {
        throw result?['message'] ?? 'Unknown error';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _processingIndices.remove(index);
        });
      }
    }
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selectedIndices.length == _data.length) {
        _selectedIndices.clear();
      } else {
        for (int i = 0; i < _data.length; i++) {
          _selectedIndices.add(i);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final pendingSelectionCount = _selectedIndices
        .where((i) => !_successIndices.contains(i))
        .length;

    return AlertDialog(
      title: const Text('Sidrap Manager'),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Column(
          children: [
            if (_error != null)
              Container(
                padding: const EdgeInsets.all(8),
                color: Colors.red[50],
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.paste),
                    label: const Text('Ambil Clipboard'),
                    onPressed: _pasteFromClipboard,
                  ),
                ),
                if (_data.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _toggleSelectAll,
                    child: Text(
                      _selectedIndices.length == _data.length
                          ? 'Deselect All'
                          : 'Select All',
                    ),
                  ),
                ],
              ],
            ),
            const Divider(),
            Expanded(
              child: _data.isEmpty
                  ? const Center(child: Text('Belum ada data'))
                  : ListView.separated(
                      itemCount: _data.length,
                      separatorBuilder: (ctx, i) => const Divider(),
                      itemBuilder: (ctx, i) {
                        final item = _data[i];
                        final isProcessing = _processingIndices.contains(i);
                        final isSuccess = _successIndices.contains(i);
                        final isSelected = _selectedIndices.contains(i);

                        return CheckboxListTile(
                          value: isSelected,
                          onChanged: isSuccess
                              ? null // Disable checkbox if already success
                              : (val) {
                                  setState(() {
                                    if (val == true) {
                                      _selectedIndices.add(i);
                                    } else {
                                      _selectedIndices.remove(i);
                                    }
                                  });
                                },
                          title: Text(item['nama_usaha'] ?? '-'),
                          subtitle: Text(
                            '${item['alamat']}\n${item['kode_wilayah']}\nLat: ${item['latitude']}, Long: ${item['longitude']}',
                          ),
                          secondary: isSuccess
                              ? const Icon(
                                  Icons.check_circle,
                                  color: Colors.green,
                                )
                              : isProcessing
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : IconButton(
                                  icon: const Icon(
                                    Icons.send,
                                    color: Colors.blue,
                                  ),
                                  onPressed: () => _sendSingle(i),
                                  tooltip: 'Kirim Satu',
                                ),
                          controlAffinity: ListTileControlAffinity.leading,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Tutup'),
        ),
        ElevatedButton(
          onPressed: pendingSelectionCount == 0
              ? null
              : () => widget.onProcessAll(
                  _data
                      .asMap()
                      .entries
                      .where(
                        (e) =>
                            _selectedIndices.contains(e.key) &&
                            !_successIndices.contains(e.key),
                      )
                      .map((e) => e.value)
                      .toList(),
                ),
          child: Text('Kirim Terpilih ($pendingSelectionCount)'),
        ),
      ],
    );
  }
}

class _Metadata {
  final String nmKec;
  final String nmDesa;

  _Metadata({required this.nmKec, required this.nmDesa});
}

class _SlsPolygon {
  final String idsls;
  final String nmsls;
  final List<LatLng> points;

  _SlsPolygon({required this.idsls, this.nmsls = '', required this.points});
}

class _GeocodeResult {
  final LatLng location;
  final LatLng? viewportNE;
  final LatLng? viewportSW;

  _GeocodeResult(this.location, {this.viewportNE, this.viewportSW});
}

class GroundcheckPage extends StatefulWidget {
  final void Function(GroundcheckRecord)? onGoToMap;

  const GroundcheckPage({super.key, this.onGoToMap});

  @override
  State<GroundcheckPage> createState() => _GroundcheckPageState();
}

class _GroundcheckPageState extends State<GroundcheckPage> {
  final ScrollController _scrollController = ScrollController();
  final DataGridController _dataGridController = DataGridController();
  final BpsGcService _gcService = BpsGcService();
  final GroundcheckSupabaseService _supabaseService =
      GroundcheckSupabaseService();
  GroundcheckDataSource? _dataSource;
  List<GroundcheckRecord> _allRecords = [];
  List<String> _statusOptions = [];
  List<String> _gcsOptions = [];
  List<String> _sumberDataOptions = [];
  String _searchQuery = '';
  String? _statusFilter;
  String? _gcsFilter;
  String? _sumberDataFilter;
  String? _isUploadedFilter;
  String? _regionFilter;
  List<String> _regionOptions = [];
  List<String> _petugasOptions = [];
  Map<String, String> _recordToRegionMap = {}; // idsbr -> region name
  List<_SlsPolygon> _polygons = [];
  Map<String, _Metadata> _metadataMap = {};
  bool _isLoading = true;
  bool _isSpatialLoading = true;
  bool _isDeletingNew = false;
  String? _error;
  String? _gcCookie;
  String? _gcToken;
  String? _currentUser;
  String? _currentLoginId; // Username login asli (e.g. muharram-pppk)
  String? _userAgent;
  String? _csrfToken;
  bool _isDialogShowing = false;

  // Active Upload State
  ValueNotifier<int>? _activeProgressNotifier;
  ValueNotifier<String>? _activeStatusNotifier;
  ValueNotifier<int>? _activeSuccessNotifier;
  ValueNotifier<int>? _activeFailNotifier;
  ValueNotifier<int>? _activePendingUiNotifier;
  ValueNotifier<bool>? _activeIsFinishedNotifier;
  ValueNotifier<bool>? _activeIsCancelledNotifier;
  int _activeTotalUploadCount = 0;
  bool _isUploadHidden = false;

  // Comparison State
  Map<String, String> _parepareComparison = {};
  Map<String, String> _idsbrToGcid = {};
  bool _showParepareDiff = false;
  bool _isLoadingParepare = false;
  String? _petugasFilter;

  @override
  void initState() {
    super.initState();
    _loadSpatialData();
    _loadStoredGcCredentials().then((_) {
      _loadData();
    });
  }

  Future<void> _loadSpatialData() async {
    try {
      // 1. Load Metadata
      final metadataString = await rootBundle.loadString(
        'assets/json/sls_metadata.json',
      );
      final List<dynamic> metadataJson = jsonDecode(metadataString);
      // Map<KecCode+DesaCode, Metadata>
      final Map<String, _Metadata> metadataMap = {};

      for (var item in metadataJson) {
        final idsls = item['idsls'] as String;
        // 73 72 011 001 (10 chars)
        if (idsls.length >= 10) {
          final key = idsls.substring(0, 10);
          if (!metadataMap.containsKey(key)) {
            metadataMap[key] = _Metadata(
              nmKec: item['nmkec'] ?? '',
              nmDesa: item['nmdesa'] ?? '',
            );
          }
        }
      }

      // 2. Load GeoJSON
      final geoJsonString = await rootBundle.loadString(
        'assets/geojson/final_sls_optimized.json',
      );
      final geoJson = jsonDecode(geoJsonString);
      final features = geoJson['features'] as List;

      final List<_SlsPolygon> polygons = [];

      for (var feature in features) {
        final props = feature['properties'];
        final idsls = props['idsls'] as String;
        final nmsls = props['nmsls'] as String? ?? '';
        final geometry = feature['geometry'];
        final type = geometry['type'];
        final coordinates = geometry['coordinates'] as List;

        if (type == 'MultiPolygon') {
          for (var poly in coordinates) {
            // poly is List<List<Position>> (Ring)
            // usually index 0 is outer ring
            final outerRing = poly[0] as List;
            final points = outerRing.map((p) {
              return LatLng((p[1] as num).toDouble(), (p[0] as num).toDouble());
            }).toList();
            polygons.add(
              _SlsPolygon(idsls: idsls, nmsls: nmsls, points: points),
            );
          }
        } else if (type == 'Polygon') {
          final outerRing = coordinates[0] as List;
          final points = outerRing.map((p) {
            return LatLng((p[1] as num).toDouble(), (p[0] as num).toDouble());
          }).toList();
          polygons.add(_SlsPolygon(idsls: idsls, nmsls: nmsls, points: points));
        }
      }

      if (mounted) {
        final Set<String> allRegions = {};
        for (var meta in metadataMap.values) {
          allRegions.add('${meta.nmKec} - ${meta.nmDesa}');
        }

        // Tambahkan opsi 'Luar Wilayah' secara eksplisit
        allRegions.add('Luar Wilayah');
        allRegions.add('Tidak Sesuai');
        allRegions.add('Tidak ada Koordinat');

        setState(() {
          _metadataMap = metadataMap;
          _polygons = polygons;
          _regionOptions = allRegions.toList()..sort();
          _isSpatialLoading = false;
        });
        // Jika data record sudah ada, hitung ulang mapping wilayah
        if (_allRecords.isNotEmpty) {
          _calculateRecordRegions();
        }
      }
    } catch (e) {
      debugPrint('Error loading spatial data: $e');
      if (mounted) {
        setState(() {
          _isSpatialLoading = false;
        });
      }
    }
  }

  void _calculateRecordRegions() {
    if (_polygons.isEmpty) return;

    final Map<String, String> mapping = {};
    final Set<String> availableRegions = {};

    for (var record in _allRecords) {
      final lat = double.tryParse(record.latitude);
      final lng = double.tryParse(record.longitude);

      if (lat != null && lng != null && lat != 0 && lng != 0) {
        final point = LatLng(lat, lng);
        String regionName = 'Luar Wilayah';

        for (var poly in _polygons) {
          if (_isPointInPolygon(point, poly.points)) {
            if (poly.idsls.length >= 10) {
              final key = poly.idsls.substring(0, 10);
              if (_metadataMap.containsKey(key)) {
                final meta = _metadataMap[key]!;
                regionName = '${meta.nmKec} - ${meta.nmDesa}';

                // Cek Kesesuaian Kode Wilayah
                // Kode Wilayah di record bisa format 72.01.010 (ada titik) atau 7201010
                // Kode polygon (idsls) format 7201010... (tanpa titik)
                String recCode = record.kodeWilayah.replaceAll('.', '').trim();
                String polyCode = poly.idsls.trim();

                bool isMatch = false;
                // Logika pencocokan:
                // 1. Jika kode record >= 10 digit, bandingkan 10 digit pertama (Desa)
                // 2. Jika kode record >= 7 digit, bandingkan 7 digit pertama (Kecamatan)
                // 3. Fallback: startsWith

                if (recCode.length >= 10 && polyCode.length >= 10) {
                  isMatch =
                      recCode.substring(0, 10) == polyCode.substring(0, 10);
                } else if (recCode.length >= 7 && polyCode.length >= 7) {
                  // Cek level kecamatan (7 digit)
                  isMatch = recCode.substring(0, 7) == polyCode.substring(0, 7);
                } else {
                  // Best effort
                  isMatch =
                      polyCode.startsWith(recCode) ||
                      recCode.startsWith(polyCode);
                }

                if (!isMatch) {
                  regionName = 'Tidak Sesuai';
                }

                break; // Found
              }
            }
          }
        }
        mapping[record.idsbr] = regionName;
        availableRegions.add(regionName);
      } else {
        mapping[record.idsbr] = 'Tidak ada Koordinat';
        availableRegions.add('Tidak ada Koordinat');
      }
    }

    setState(() {
      _recordToRegionMap = mapping;
      // Jangan timpa _regionOptions agar tetap berisi semua wilayah dari metadata
      // _regionOptions = availableRegions.toList()..sort();
    });

    // Refresh jika ada filter aktif
    if (_regionFilter != null) {
      _refreshFilteredData();
    }
  }

  // Ray Casting Algorithm
  bool _isPointInPolygon(LatLng point, List<LatLng> polygon) {
    bool c = false;
    for (int i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      if (((polygon[i].latitude > point.latitude) !=
              (polygon[j].latitude > point.latitude)) &&
          (point.longitude <
              (polygon[j].longitude - polygon[i].longitude) *
                      (point.latitude - polygon[i].latitude) /
                      (polygon[j].latitude - polygon[i].latitude) +
                  polygon[i].longitude)) {
        c = !c;
      }
    }
    return c;
  }

  Future<void> _loadData() async {
    // Prevent re-entry if dialog is showing
    if (_isDialogShowing) return;

    setState(() {
      if (_allRecords.isEmpty) _isLoading = true;
      _error = null;
    });
    try {
      // 1. Load from local cache immediately
      final local = await _supabaseService.loadLocalRecords();

      // Cek status MapBloc untuk validasi "Data Lokal Kosong"
      final mapState = context.read<MapBloc>().state;
      // Also check polygonsMeta in case user refers to polygon markers
      final hasMapData =
          mapState.places.isNotEmpty || mapState.polygonsMeta.isNotEmpty;
      // Consider initial state as loading to prevent premature dialog
      final isMapLoading =
          mapState.status == MapStatus.loading ||
          mapState.status == MapStatus.initial;

      if (local.isNotEmpty && mounted) {
        _processRecords(local);

        // 2. Sync with server (fetch only updates) - Background Process
        // Hanya jalankan auto-sync jika kita SUDAH punya data lokal
        try {
          // syncRecords sekarang HANYA melakukan incremental sync.
          // Jika tidak ada lastSync atau lokal kosong, dia akan return [] atau local.
          final records = await _supabaseService.syncRecords();

          if (mounted) {
            if (records.isNotEmpty) {
              // Ada update baru, refresh tampilan
              _processRecords(records);
            }
            // Jika records kosong, berarti tidak ada update atau sync gagal (fallback ke local).
            // Kita tidak perlu melakukan apa-apa karena data lokal sudah tampil.
          }
        } catch (e) {
          debugPrint('Error during background sync: $e');
          // Ignore error, keep showing local data
        }
      } else {
        // Jika data lokal kosong...

        if (isMapLoading) {
          // Map sedang loading, tunggu hasil dari MapBloc (via BlocListener)
          debugPrint('Local data empty, waiting for Map loading...');
          return;
        }

        // Jika data benar-benar kosong
        // Tampilkan konfirmasi ke user.
        if (mounted) {
          _processRecords([]);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showDownloadConfirmation();
          });
        }
        return;
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _showDownloadConfirmation() async {
    if (_isDialogShowing) return;
    _isDialogShowing = true;

    // Gunakan helper yang sudah distandarisasi
    await MapDownloadHelper.showInitialDownloadDialog(
      context,
      onSuccess: (records) {
        if (mounted) {
          _processRecords(records);
        }
      },
    );

    _isDialogShowing = false;
  }

  Future<void> _refreshLocalData() async {
    setState(() => _isLoading = true);
    try {
      final local = await _supabaseService.loadLocalRecords();
      if (mounted) {
        _processRecords(local);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Data lokal berhasil disinkronkan: ${local.length} data',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Gagal sinkronisasi: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _processRecords(List<GroundcheckRecord> records) {
    final sorted = [...records];
    sorted.sort((a, b) {
      final da = DateTime.tryParse(a.updatedAt);
      final db = DateTime.tryParse(b.updatedAt);
      final aMs = da?.millisecondsSinceEpoch ?? 0;
      final bMs = db?.millisecondsSinceEpoch ?? 0;
      return bMs.compareTo(aMs);
    });
    _allRecords = sorted;
    _statusOptions =
        records
            .map((e) => e.statusPerusahaan)
            .where((v) => v.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    _gcsOptions =
        records
            .map((e) => e.gcsResult)
            .where((v) => v.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    _sumberDataOptions =
        records
            .map((e) => e.sumberData.trim())
            .where((v) => v.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    _petugasOptions =
        records
            .map((e) => e.gcUsername?.trim())
            .where((v) => v != null && v.isNotEmpty)
            .map((v) => v!)
            .toSet()
            .toList()
          ..sort();

    // Validasi filter saat ini agar tetap konsisten dengan opsi baru (trim)
    if (_sumberDataFilter != null) {
      // Allow empty string as valid filter (meaning "No Source/Null")
      if (_sumberDataFilter!.isEmpty) {
        // Keep it as is
      } else {
        final trimmed = _sumberDataFilter!.trim();
        if (_sumberDataOptions.contains(trimmed)) {
          _sumberDataFilter = trimmed;
        } else {
          // Jika opsi yang dipilih tidak ada lagi (misal data berubah total), reset
          _sumberDataFilter = null;
        }
      }
    }

    if (_petugasFilter != null) {
      if (_petugasFilter!.isEmpty) {
        // Keep it
      } else {
        final trimmed = _petugasFilter!.trim();
        if (_petugasOptions.contains(trimmed)) {
          _petugasFilter = trimmed;
        } else {
          _petugasFilter = null;
        }
      }
    }

    // Recalculate regions when new data arrives
    _calculateRecordRegions();

    final filtered = _filteredRecords();
    setState(() {
      _dataSource = GroundcheckDataSource(
        data: filtered,
        onGcPressed: _onGcPressed,
        onGoToMap: widget.onGoToMap,
      );
      _isLoading = false;
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadStoredGcCredentials() async {
    debugPrint('proses kirim: Menunggu login/input manual untuk kredensial.');
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _gcToken = prefs.getString('gc_token');
      _gcCookie = prefs.getString('gc_cookie');
      _currentLoginId = prefs.getString('current_login_id');
    });
  }

  Future<void> _saveStoredGcCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    if (_gcToken != null) await prefs.setString('gc_token', _gcToken!);
    if (_gcCookie != null) await prefs.setString('gc_cookie', _gcCookie!);
    if (_currentLoginId != null)
      await prefs.setString('current_login_id', _currentLoginId!);
  }

  Future<void> _handleRefreshSession() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final data = await _gcService.refreshSession();
      if (data != null) {
        final userName = data['userName'] ?? '';
        final gcToken = data['gcToken'] ?? '';
        final csrfToken = data['csrfToken'] ?? '';

        if (userName.isNotEmpty) {
          setState(() {
            _currentUser = userName;
          });
        }
        if (gcToken.isNotEmpty) {
          setState(() {
            _gcToken = gcToken;
          });
        }
        if (csrfToken.isNotEmpty) {
          setState(() {
            _csrfToken = csrfToken;
          });
        }

        // Update credentials in service
        if (_gcCookie != null && _userAgent != null) {
          _gcService.setCredentials(
            cookie: _gcCookie!,
            csrfToken: _csrfToken ?? '',
            gcToken: _gcToken ?? '',
            userAgent: _userAgent!,
          );
          await _saveStoredGcCredentials();
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Sesi berhasil diperbarui!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Gagal memperbarui sesi. Cookie mungkin kadaluarsa.',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error refresh sesi: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Konfirmasi Logout'),
        content: const Text('Apakah Anda yakin ingin keluar akun BPS?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Keluar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isLoading = true;
    });

    try {
      await _gcService.logout();

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('gc_token');
      await prefs.remove('gc_cookie');

      setState(() {
        _gcToken = null;
        _gcCookie = null;
        _currentUser = null;
        _csrfToken = null;
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Logout berhasil.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Logout gagal: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showGcInputDialog(GroundcheckRecord record) async {
    final hasilOptions = <Map<String, String>>[
      {'code': '', 'label': '-- Pilih --'},
      {'code': '99', 'label': '0. Tidak Ditemukan'},
      {'code': '1', 'label': '1. Ditemukan'},
      {'code': '3', 'label': '3. Tutup'},
      {'code': '4', 'label': '4. Ganda'},
    ];
    String selectedHasil = record.gcsResult.isNotEmpty ? record.gcsResult : '';
    final latController = TextEditingController(text: record.latitude);
    final lonController = TextEditingController(text: record.longitude);
    LatLng? markerPos;
    try {
      final lat = double.tryParse(record.latitude);
      final lon = double.tryParse(record.longitude);
      if (lat != null && lon != null) {
        markerPos = LatLng(lat, lon);
      }
    } catch (_) {}
    final mapController = MapController();
    bool isSubmitting = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateSB) {
            final lat = double.tryParse(latController.text);
            final lon = double.tryParse(lonController.text);
            final center = (lat != null && lon != null)
                ? LatLng(lat, lon)
                : (markerPos ?? const LatLng(-6.2, 106.8));
            return AlertDialog(
              title: const Text('Tandai Usaha Sudah Dicek!'),
              content: SizedBox(
                width: 700,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Keberadaan Usaha Hasil GC',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: hasilOptions.map((o) {
                          final code = o['code']!;
                          final label = o['label']!;
                          MaterialColor base = Colors.grey;
                          switch (code) {
                            case '99':
                              base = Colors.red;
                              break;
                            case '1':
                              base = Colors.green;
                              break;
                            case '3':
                              base = Colors.blueGrey;
                              break;
                            case '4':
                              base = Colors.orange;
                              break;
                            default:
                              base = Colors.grey;
                          }
                          final isSelected = selectedHasil == code;
                          return ChoiceChip(
                            label: Text(label),
                            selected: isSelected,
                            onSelected: (_) {
                              setStateSB(() {
                                selectedHasil = code;
                              });
                            },
                            labelStyle: TextStyle(
                              color: isSelected
                                  ? base.shade800
                                  : Colors.black87,
                              fontSize: 12,
                            ),
                            selectedColor: base.withValues(alpha: 0.18),
                            backgroundColor: Colors.grey.withValues(alpha: 0.1),
                            shape: StadiumBorder(
                              side: BorderSide(
                                color: isSelected
                                    ? base.withValues(alpha: 0.4)
                                    : Colors.grey.withValues(alpha: 0.3),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: latController,
                              decoration: const InputDecoration(
                                labelText: 'Latitude',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    signed: true,
                                    decimal: true,
                                  ),
                              onChanged: (_) {
                                setStateSB(() {
                                  final la = double.tryParse(
                                    latController.text.trim(),
                                  );
                                  final lo = double.tryParse(
                                    lonController.text.trim(),
                                  );
                                  if (la != null && lo != null) {
                                    markerPos = LatLng(la, lo);
                                  }
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: lonController,
                              decoration: const InputDecoration(
                                labelText: 'Longitude',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    signed: true,
                                    decimal: true,
                                  ),
                              onChanged: (_) {
                                setStateSB(() {
                                  final la = double.tryParse(
                                    latController.text.trim(),
                                  );
                                  final lo = double.tryParse(
                                    lonController.text.trim(),
                                  );
                                  if (la != null && lo != null) {
                                    markerPos = LatLng(la, lo);
                                  }
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            try {
                              bool serviceEnabled =
                                  await Geolocator.isLocationServiceEnabled();
                              if (!serviceEnabled) {
                                throw Exception('Layanan lokasi tidak aktif');
                              }
                              LocationPermission permission =
                                  await Geolocator.checkPermission();
                              if (permission == LocationPermission.denied) {
                                permission =
                                    await Geolocator.requestPermission();
                                if (permission == LocationPermission.denied) {
                                  throw Exception('Izin lokasi ditolak');
                                }
                              }
                              if (permission ==
                                  LocationPermission.deniedForever) {
                                throw Exception('Izin lokasi ditolak permanen');
                              }
                              final pos = await Geolocator.getCurrentPosition(
                                desiredAccuracy: LocationAccuracy.high,
                              );
                              setStateSB(() {
                                latController.text = pos.latitude
                                    .toStringAsFixed(10);
                                lonController.text = pos.longitude
                                    .toStringAsFixed(10);
                                markerPos = LatLng(pos.latitude, pos.longitude);
                              });
                              try {
                                mapController.move(
                                  LatLng(pos.latitude, pos.longitude),
                                  18.0,
                                );
                              } catch (_) {}
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Gagal mengambil lokasi: ${e.toString()}',
                                    ),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            }
                          },
                          icon: const Icon(
                            Icons.my_location,
                            color: Colors.redAccent,
                          ),
                          label: const Text('Ambil Lokasi Saat Ini'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 320,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: FlutterMap(
                            mapController: mapController,
                            options: MapOptions(
                              initialCenter: center,
                              initialZoom: 16,
                              onTap: (tapPos, point) {
                                setStateSB(() {
                                  markerPos = point;
                                  latController.text = point.latitude
                                      .toStringAsFixed(10);
                                  lonController.text = point.longitude
                                      .toStringAsFixed(10);
                                });
                              },
                            ),
                            children: [
                              TileLayer(
                                urlTemplate:
                                    'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                                subdomains: const ['a', 'b', 'c'],
                              ),
                              MarkerLayer(
                                markers: [
                                  if (markerPos != null)
                                    Marker(
                                      point: markerPos!,
                                      width: 40,
                                      height: 40,
                                      alignment: Alignment.center,
                                      child: const Icon(
                                        Icons.place,
                                        color: Colors.blue,
                                        size: 36,
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 50),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Batal'),
                ),
                if (isSubmitting)
                  const SizedBox(
                    height: 40,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else
                  FilledButton.icon(
                    onPressed: () async {
                      debugPrint(
                        'proses kirim: Tombol "Tandai Usaha Sudah Dicek" ditekan.',
                      );
                      final laInput = double.tryParse(
                        latController.text.trim(),
                      );
                      final loInput = double.tryParse(
                        lonController.text.trim(),
                      );
                      debugPrint(
                        'proses kirim: Input Awal -> LatInput: $laInput, LonInput: $loInput, Hasil: $selectedHasil',
                      );

                      if (selectedHasil.isEmpty) {
                        debugPrint(
                          'proses kirim: Gagal - Hasil GC belum dipilih',
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Pilih hasil GC terlebih dahulu'),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }
                      final laFinal =
                          laInput ?? double.tryParse(record.latitude);
                      final loFinal =
                          loInput ?? double.tryParse(record.longitude);

                      debugPrint(
                        'proses kirim: Koordinat Final -> Lat: $laFinal, Lon: $loFinal',
                      );

                      debugPrint('proses kirim: Memanggil _ensureGcConfig...');
                      final ok = await _ensureGcConfig();
                      debugPrint('proses kirim: _ensureGcConfig result: $ok');

                      if (!ok) {
                        debugPrint(
                          'proses kirim: Gagal - Konfigurasi GC tidak valid/lengkap.',
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Konfigurasi GC belum lengkap (Cookie/Token).',
                            ),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }
                      setStateSB(() {
                        isSubmitting = true;
                      });
                      try {
                        debugPrint('proses kirim: Mempersiapkan payload...');
                        final requestPayload = {
                          'perusahaan_id': record.perusahaanId,
                          'latitude': laFinal != null ? laFinal.toString() : '',
                          'longitude': loFinal != null
                              ? loFinal.toString()
                              : '',
                          'hasilgc': selectedHasil,
                          'gc_token': _gcToken ?? '',
                          'gc_cookie':
                              _gcService.cookieHeader ?? (_gcCookie ?? ''),
                          'timestamp': DateTime.now().toIso8601String(),
                        };
                        debugPrint(
                          'proses kirim: Payload Request => ${jsonEncode(requestPayload)}',
                        );
                        debugPrint(
                          'proses kirim: Cookie Header (sebelum kirim) => ${_gcService.cookieHeader ?? "KOSONG"}',
                        );
                        debugPrint(
                          'proses kirim: GC Token (sebelum kirim) => ${_gcToken ?? "KOSONG"}',
                        );
                        final resp = await _gcService.konfirmasiUser(
                          perusahaanId: record.perusahaanId,
                          latitude: laFinal != null ? laFinal.toString() : '',
                          longitude: loFinal != null ? loFinal.toString() : '',
                          hasilGc: selectedHasil,
                        );
                        if (resp == null || resp['status'] != 'success') {
                          if (resp != null) {
                            debugPrint(
                              'proses kirim: Response Status: ${resp['status']}, Message: ${resp['message'] ?? ""}',
                            );
                          } else {
                            debugPrint(
                              'proses kirim: Response null atau gagal autentikasi.',
                            );
                          }
                          final debugInfo = <String, dynamic>{
                            'request': requestPayload,
                            'response': resp != null
                                ? _sanitizeResponse(resp)
                                : 'null (No Response / Auth Failed)',
                            'status': 'failed',
                          };

                          final pretty = const JsonEncoder.withIndent(
                            '  ',
                          ).convert(debugInfo);
                          debugPrint(
                            'proses kirim: Response GAGAL =>\n$pretty',
                          );

                          await _showResponseDialog(debugInfo);

                          setStateSB(() {
                            isSubmitting = false;
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Konfirmasi GC gagal dikirim'),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }

                        final debugInfo = <String, dynamic>{
                          'request': requestPayload,
                          'response': _sanitizeResponse(resp),
                          'status': 'success',
                        };
                        final pretty = const JsonEncoder.withIndent(
                          '  ',
                        ).convert(debugInfo);
                        debugPrint('proses kirim: Response SUKSES =>\n$pretty');
                        debugPrint(
                          'proses kirim: Response Status: ${resp['status']}, Message: ${resp['message'] ?? ""}',
                        );

                        final newToken = resp['new_gc_token'] as String?;
                        if (newToken != null && newToken.isNotEmpty) {
                          _gcToken = newToken;
                          await _saveStoredGcCredentials();
                        }
                        // Update Token jika ada di response
                        if (resp != null && resp['new_gc_token'] != null) {
                          final newToken = resp['new_gc_token'].toString();
                          if (newToken.isNotEmpty && newToken != _gcToken) {
                            _gcToken = newToken;
                            await _saveStoredGcCredentials();
                          }
                        }

                        final currentCookie = _gcService.cookieHeader;
                        if (currentCookie != null &&
                            currentCookie.isNotEmpty &&
                            currentCookie != _gcCookie) {
                          _gcCookie = currentCookie;
                          await _saveStoredGcCredentials();
                        }
                        await _applyGcInput(
                          record,
                          selectedHasil,
                          laFinal,
                          loFinal,
                          isUploaded: true,
                        );
                        setStateSB(() {
                          isSubmitting = false;
                        });
                        Navigator.of(ctx).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Konfirmasi GC terkirim untuk ${record.namaUsaha}',
                            ),
                            backgroundColor: Colors.green,
                          ),
                        );
                      } catch (e, stack) {
                        setStateSB(() {
                          isSubmitting = false;
                        });
                        final errorInfo = {
                          'error': e.toString(),
                          'stack_trace': stack
                              .toString()
                              .split('\n')
                              .take(5)
                              .toList(),
                          'timestamp': DateTime.now().toIso8601String(),
                        };
                        debugPrint('proses kirim: EXCEPTION => $e');
                        await _showResponseDialog(errorInfo);

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Terjadi kesalahan: ${e.toString()}'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.flag),
                    label: const Text('Tandai Usaha Sudah Dicek!'),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Map<String, dynamic> _sanitizeResponse(Map<String, dynamic> resp) {
    final safe = <String, dynamic>{};
    resp.forEach((k, v) {
      final key = k.toString().toLowerCase();
      if (key.contains('token') ||
          key.contains('cookie') ||
          key.contains('session')) {
        if (v is String && v.isNotEmpty) {
          safe[k] = '***masked(${v.length})***';
        } else {
          safe[k] = '***masked***';
        }
      } else {
        safe[k] = v;
      }
    });
    return safe;
  }

  Future<void> _showResponseDialog(Map<String, dynamic> resp) async {
    final pretty = const JsonEncoder.withIndent('  ').convert(resp);
    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Respons Konfirmasi GC'),
          content: SizedBox(
            width: 600,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    pretty,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Tutup'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _applyGcInput(
    GroundcheckRecord record,
    String hasilGc,
    double? lat,
    double? lon, {
    bool isUploaded = false,
    bool? allowCancel,
  }) async {
    final updated = GroundcheckRecord(
      idsbr: record.idsbr,
      namaUsaha: record.namaUsaha,
      alamatUsaha: record.alamatUsaha,
      kodeWilayah: record.kodeWilayah,
      statusPerusahaan: record.statusPerusahaan,
      skalaUsaha: record.skalaUsaha,
      gcsResult: hasilGc,
      latitude: lat != null ? lat.toString() : record.latitude,
      longitude: lon != null ? lon.toString() : record.longitude,
      perusahaanId: record.perusahaanId,
      userId: record.userId,
      isUploaded: isUploaded,
      allowCancel: allowCancel ?? record.allowCancel,
    );
    final idx = _allRecords.indexWhere((r) => r.idsbr == record.idsbr);
    if (idx != -1) {
      _allRecords[idx] = updated;
    }
    _refreshFilteredData();
    // Simpan perubahan ke cache lokal agar tetap ada saat restart (optimistic update)
    await _supabaseService.saveLocalRecords(_allRecords);

    // Jangan update timestamp jika ini hanya update status upload (isUploaded=true)
    // Agar updated_at tetap mencerminkan waktu pengambilan data di lapangan.
    await _supabaseService.updateRecord(updated, updateTimestamp: !isUploaded);

    // Khusus update status upload (jika true) menggunakan fungsi terpisah
    if (isUploaded) {
      await _supabaseService.updateUploadStatus(record.idsbr, true);
    }

    try {
      MapRepositoryImpl().invalidatePlacesCache();
      if (mounted) {
        context.read<MapBloc>().add(const PlacesRequested());
      }
    } catch (_) {}
  }

  Future<bool> _ensureGcConfig({bool forceShow = false}) async {
    debugPrint('proses kirim: _ensureGcConfig dipanggil. forceShow=$forceShow');
    debugPrint(
      'proses kirim: State Awal -> Cookie: ${_gcCookie ?? "KOSONG"}, Token: ${_gcToken ?? "KOSONG"}',
    );

    // Cek jika cookie cukup kuat (Laravel Session + XSRF)
    final hasStrongCookie =
        _gcCookie != null &&
        _gcCookie!.contains('laravel_session') &&
        _gcCookie!.contains('XSRF-TOKEN');

    // Jika kredensial sudah ada, langsung anggap valid (sesuai permintaan user: tidak perlu cek validnya)
    // PERBAIKAN: Jika punya Strong Cookie (Laravel Session), kita izinkan lewat meskipun gc_token kosong
    if (!forceShow &&
        ((_gcCookie != null &&
                _gcCookie!.isNotEmpty &&
                _gcToken != null &&
                _gcToken!.isNotEmpty) ||
            hasStrongCookie)) {
      debugPrint(
        'proses kirim: Kredensial tersedia (Token/Strong Cookie), melanjutkan tanpa cek validitas (bypass).',
      );
      return true;
    }

    debugPrint(
      'proses kirim: State Akhir (Pre-Check) -> Cookie: ${_gcCookie ?? "KOSONG"}, Token: ${_gcToken ?? "KOSONG"}',
    );

    if (_gcCookie != null && _gcCookie!.isNotEmpty) {
      // Logic auto-refresh dihapus. User diminta login jika token tidak valid.
      debugPrint(
        'proses kirim: Cookie ada, tapi token mungkin tidak valid/lengkap.',
      );
    }

    debugPrint(
      'proses kirim: Konfigurasi belum lengkap atau tidak valid. Tanyakan login.',
    );

    final shouldLogin = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Login Diperlukan'),
          content: const Text(
            'Sesi belum tersedia atau sudah kadaluarsa. Silakan login BPS.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Login'),
            ),
          ],
        );
      },
    );

    if (shouldLogin == true && mounted) {
      _showBpsLoginDialog();
    }
    return false;
  }

  Future<void> _handleLoginSuccess(
    String cookie,
    String gcToken,
    String csrfToken,
    String userAgent,
    String userName, {
    String? loginId,
  }) async {
    debugPrint('Login Success: $userName');
    debugPrint('proses kirim: Login Cookie Visible (JS): $cookie');

    // Analisis Cookie untuk Feedback User
    final hasSession = cookie.contains('laravel_session');
    final hasXsrf = cookie.contains('XSRF-TOKEN');

    String statusMsg = 'Login berhasil! User: $userName';
    Color snackBarColor = Colors.green;

    if (hasSession && hasXsrf) {
      debugPrint(
        'proses kirim: [INFO] Sesi Lengkap. Siap kirim via HTTP Direct.',
      );
      statusMsg += '\n[OK] Mode Cepat (HTTP Direct) Aktif';
    } else {
      debugPrint(
        'proses kirim: [INFO] Sesi Terbatas (HttpOnly hidden). Fallback ke WebView.',
      );
      statusMsg += '\n[Info] Mode Kompatibilitas (WebView) Aktif';
      snackBarColor = Colors.orange[800]!;
    }

    setState(() {
      _gcCookie = cookie;
      _gcToken = gcToken;
      _currentUser = userName.isNotEmpty ? userName : 'Pengguna Terautentikasi';
      if (loginId != null) _currentLoginId = loginId;
    });

    _gcService.setCredentials(
      cookie: cookie,
      csrfToken: csrfToken,
      gcToken: gcToken,
      userAgent: userAgent,
    );

    await _saveStoredGcCredentials();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(statusMsg),
          backgroundColor: snackBarColor,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  void _showAccountManagerDialog() {
    showDialog(
      context: context,
      builder: (context) {
        final usernameController = TextEditingController();
        final passwordController = TextEditingController();
        final manager = AccountManagerService();

        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Kelola Akun Otomatis'),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Daftar akun ini akan digunakan untuk login otomatis saat terkena Rate Limit (429).',
                      style: TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    // Input Form
                    TextField(
                      controller: usernameController,
                      decoration: const InputDecoration(
                        labelText: 'Username / NIP',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: passwordController,
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      obscureText: true,
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: () {
                        if (usernameController.text.isNotEmpty &&
                            passwordController.text.isNotEmpty) {
                          manager.addAccount(
                            usernameController.text,
                            passwordController.text,
                          );
                          usernameController.clear();
                          passwordController.clear();
                          setState(() {});
                        }
                      },
                      child: const Text('Tambah Akun'),
                    ),
                    const Divider(),
                    // List Accounts
                    Flexible(
                      child: manager.accounts.isEmpty
                          ? const Text(
                              'Belum ada akun tersimpan.',
                              style: TextStyle(fontStyle: FontStyle.italic),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: manager.accounts.length,
                              itemBuilder: (context, index) {
                                final account = manager.accounts[index];
                                final isLimited = account.isRateLimited;
                                return ListTile(
                                  dense: true,
                                  title: Row(
                                    children: [
                                      Text(
                                        account.username,
                                        style: TextStyle(
                                          color: isLimited ? Colors.red : null,
                                          fontWeight: isLimited
                                              ? FontWeight.bold
                                              : null,
                                        ),
                                      ),
                                      if (isLimited) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.red[50],
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                            border: Border.all(
                                              color: Colors.red,
                                            ),
                                          ),
                                          child: Text(
                                            account.rateLimitStatus,
                                            style: const TextStyle(
                                              color: Colors.red,
                                              fontSize: 10,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  subtitle: const Text('Password: ***'),
                                  trailing: IconButton(
                                    icon: const Icon(
                                      Icons.delete,
                                      color: Colors.red,
                                      size: 20,
                                    ),
                                    onPressed: () {
                                      manager.removeAccount(account.username);
                                      setState(() {});
                                    },
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Tutup'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _handleBpsLoginButton() async {
    final accounts = AccountManagerService().accounts;
    if (accounts.isEmpty) {
      await _performManualLogin();
    } else if (accounts.length == 1) {
      await _performAutoLogin(accounts.first);
    } else {
      if (!mounted) return;
      await showModalBottomSheet(
        context: context,
        builder: (ctx) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  'Pilih Akun',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ),
              ...accounts.map(
                (acc) => ListTile(
                  leading: const Icon(Icons.person),
                  title: Text(acc.username),
                  subtitle: acc.name != null ? Text(acc.name!) : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    _performAutoLogin(acc);
                  },
                ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.login),
                title: const Text('Login Manual (WebView)'),
                onTap: () {
                  Navigator.pop(ctx);
                  _performManualLogin();
                },
              ),
              const SizedBox(height: 16),
            ],
          );
        },
      );
    }
  }

  Future<void> _performAutoLogin(BpsAccount account) async {
    if (!mounted) return;

    // Show Loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Login otomatis...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final result = await _gcService.automatedLogin(
        username: account.username,
        password: account.password,
      );

      // Close Loading
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      if (result['status'] == 'success') {
        if (mounted) {
          await _handleLoginSuccess(
            _gcService.cookieHeader ?? '',
            result['gcToken'] ?? '',
            result['csrfToken'] ?? '',
            _gcService.userAgent ?? '',
            result['userName'] ?? 'User',
            loginId: result['loginId'],
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Login otomatis gagal: ${result['message']}'),
              backgroundColor: Colors.red,
              action: SnackBarAction(
                label: 'Coba Manual',
                textColor: Colors.white,
                onPressed: _performManualLogin,
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _performManualLogin() async {
    if (!mounted) return;

    // Gunakan InAppWebView yang lebih powerful (bisa ambil HttpOnly cookies)
    await Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => InAppWebViewLoginDialog(
          onLoginSuccess:
              (cookie, gcToken, csrfToken, userAgent, userName) async {
                await _handleLoginSuccess(
                  cookie,
                  gcToken,
                  csrfToken,
                  userAgent,
                  userName,
                );
              },
        ),
      ),
    );
  }

  Future<void> _showBpsLoginDialog() async {
    await _handleBpsLoginButton();
  }

  Future<void> _showGcConfirmationDialog(GroundcheckRecord record) async {
    final lat = double.tryParse(record.latitude);
    final lon = double.tryParse(record.longitude);
    final hasCoord = lat != null && lon != null && lat != 0.0 && lon != 0.0;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Konfirmasi Kirim GC'),
          content: SingleChildScrollView(
            child: ListBody(
              children: [
                const Text('Apakah Anda yakin ingin mengirim data ini?'),
                const SizedBox(height: 12),
                _buildInfoRow('Nama Usaha', record.namaUsaha),
                _buildInfoRow('Hasil GC', record.gcsResult),
                _buildInfoRow('Latitude', record.latitude),
                _buildInfoRow('Longitude', record.longitude),
                if (!hasCoord)
                  const Padding(
                    padding: EdgeInsets.only(top: 8.0),
                    child: Text(
                      'Peringatan: Koordinat 0/Kosong',
                      style: TextStyle(color: Colors.orange, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Kirim'),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      final ok = await _ensureGcConfig();
      if (!ok) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Login BPS diperlukan untuk mengirim data.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Mengirim data...'),
            duration: Duration(seconds: 1),
          ),
        );
      }

      try {
        final laFinal = lat ?? 0.0;
        final loFinal = lon ?? 0.0;

        final resp = await _gcService.konfirmasiUser(
          perusahaanId: record.perusahaanId,
          latitude: laFinal.toString(),
          longitude: loFinal.toString(),
          hasilGc: record.gcsResult,
        );

        bool isSuccess = false;
        if (resp != null) {
          final status = resp['status']?.toString().toLowerCase();
          final msg = resp['message']?.toString().toLowerCase() ?? '';
          if (status == 'success' ||
              msg.contains('berhasil') ||
              msg.contains('success')) {
            isSuccess = true;
          } else if (status == 'error' &&
              msg.contains('sudah diground check')) {
            // Handle kasus: "Usaha ini sudah diground check oleh user lain"
            // Server mengembalikan data status hasil GC yang sudah ada.
            final data = resp['data'];
            if (data is Map) {
              final serverResult = data['status_hasil_gc']?.toString();
              if (serverResult != null && serverResult.isNotEmpty) {
                // Update lokal dengan data server dan tandai isUploaded = true
                await _applyGcInput(
                  record,
                  serverResult, // Update gcsResult dengan data server
                  laFinal,
                  loFinal,
                  isUploaded: true,
                );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Info: Data sudah di-GC user lain ($serverResult). Lokal diperbarui.',
                      ),
                      backgroundColor: Colors.orange,
                    ),
                  );
                }
                return; // Keluar, anggap selesai
              }
            }
          }
        }

        if (isSuccess) {
          await _applyGcInput(
            record,
            record.gcsResult,
            laFinal,
            loFinal,
            isUploaded: true,
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Berhasil terkirim!'),
                backgroundColor: Colors.green,
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Gagal: ${resp?['message'] ?? 'Unknown'}'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _onGcPressed(GroundcheckRecord record) async {
    await _showGcConfirmationDialog(record);
  }

  Future<void> _loadParepareComparison() async {
    if (_parepareComparison.isNotEmpty) return;
    setState(() => _isLoadingParepare = true);
    try {
      final jsonString = await DefaultAssetBundle.of(
        context,
      ).loadString('assets/json/parepare_comparison.json');
      final List<dynamic> jsonList = jsonDecode(jsonString);
      for (var item in jsonList) {
        final idsbr = item['idsbr']?.toString() ?? '';
        final gcs = item['gcs_result']?.toString() ?? '';
        if (idsbr.isNotEmpty) {
          _parepareComparison[idsbr] = gcs;
        }
      }
    } catch (e) {
      debugPrint('Error loading parepare comparison: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memuat data pembanding: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingParepare = false);
      }
    }
  }

  Future<void> _loadGcidMap() async {
    if (_idsbrToGcid.isNotEmpty) return;
    // Gunakan _isLoadingParepare sebagai indikator loading, tapi hati-hati konflik
    // jika dipanggil bersamaan.
    setState(() => _isLoadingParepare = true);
    try {
      final jsonString = await DefaultAssetBundle.of(
        context,
      ).loadString('assets/json/parepare_comparison.json');
      final List<dynamic> jsonList = jsonDecode(jsonString);
      for (var item in jsonList) {
        final idsbr = item['idsbr']?.toString() ?? '';
        final gcid = item['gcid']?.toString() ?? '';
        if (idsbr.isNotEmpty && gcid.isNotEmpty) {
          _idsbrToGcid[idsbr] = gcid;
        }
      }
    } catch (e) {
      debugPrint('Error loading gcid map: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Gagal memuat data GCID: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingParepare = false);
      }
    }
  }

  Future<void> _syncGcUsernameFromParepareJson() async {
    if (_isLoadingParepare) return;
    setState(() => _isLoadingParepare = true);
    try {
      final jsonString = await DefaultAssetBundle.of(
        context,
      ).loadString('assets/json/parepare_comparison.json');
      final List<dynamic> jsonList = jsonDecode(jsonString);
      final Map<String, String> usernameMap = {};
      for (var item in jsonList) {
        final idsbr = item['idsbr']?.toString() ?? '';
        final username = item['gc_username']?.toString() ?? '';
        if (idsbr.isNotEmpty && username.isNotEmpty) {
          usernameMap[idsbr] = username;
        }
      }

      final service = GroundcheckSupabaseService();
      final localRecords = await service.loadLocalRecords();
      int updatedCount = 0;
      final newRecords = localRecords.map((r) {
        if (usernameMap.containsKey(r.idsbr)) {
          final newUsername = usernameMap[r.idsbr]!;
          if (r.gcUsername != newUsername) {
            updatedCount++;
            return r.copyWith(gcUsername: newUsername);
          }
        }
        return r;
      }).toList();

      if (updatedCount > 0) {
        await service.saveLocalRecords(newRecords);
        await _loadData(); // Reload UI
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Berhasil update $updatedCount username petugas dari Excel',
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Tidak ada data username yang perlu diupdate'),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error syncing username: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Gagal update username: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingParepare = false);
      }
    }
  }

  List<GroundcheckRecord> _filteredRecords() {
    return _allRecords.where((r) {
      if (_showParepareDiff) {
        final compareVal = _parepareComparison[r.idsbr];
        // If not in comparison file, or if values are same, skip it.
        // We only want to show DIFFERENCES where the ID exists in both.
        if (compareVal == null) return false;

        final localVal = r.gcsResult.trim();
        final remoteVal = compareVal.trim();

        // If both are empty/null-ish, consider them same
        final localEmpty = localVal.isEmpty || localVal == 'null';
        final remoteEmpty = remoteVal.isEmpty || remoteVal == 'null';
        if (localEmpty && remoteEmpty) return false;

        if (localVal == remoteVal) return false;
      }

      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final match =
            r.idsbr.toLowerCase().contains(q) ||
            r.namaUsaha.toLowerCase().contains(q) ||
            r.alamatUsaha.toLowerCase().contains(q) ||
            r.kodeWilayah.toLowerCase().contains(q);
        if (!match) {
          return false;
        }
      }
      if (_statusFilter != null &&
          _statusFilter!.isNotEmpty &&
          r.statusPerusahaan != _statusFilter) {
        return false;
      }
      if (_gcsFilter != null && _gcsFilter!.isNotEmpty) {
        if (_gcsFilter == 'NULL') {
          // Filter data yang belum ada hasil GCS (kosong)
          if (r.gcsResult.isNotEmpty) return false;
        } else if (r.gcsResult != _gcsFilter) {
          return false;
        }
      }
      if (_sumberDataFilter != null) {
        if (_sumberDataFilter!.isEmpty) {
          // Filter data yang kosong/null
          if (r.sumberData.trim().isNotEmpty) return false;
        } else if (r.sumberData.trim() != _sumberDataFilter) {
          return false;
        }
      }
      if (_isUploadedFilter != null) {
        if (_isUploadedFilter == 'revisi') {
          if (!r.isRevisi) return false;
        } else if (_isUploadedFilter == 'uploaded') {
          // Uploaded tapi bukan revisi
          if (!r.isUploaded || r.isRevisi) return false;
        } else if (_isUploadedFilter == 'not_uploaded') {
          // Belum upload dan bukan revisi
          if (r.isUploaded || r.isRevisi) return false;
        }
      }

      if (_petugasFilter != null) {
        if (_petugasFilter!.isEmpty) {
          // Filter data yang belum ada petugas (kosong)
          if (r.gcUsername != null && r.gcUsername!.isNotEmpty) return false;
        } else if (r.gcUsername?.trim() != _petugasFilter) {
          return false;
        }
      }

      if (_regionFilter != null) {
        final region = _recordToRegionMap[r.idsbr];
        if (region != _regionFilter) return false;
      }

      return true;
    }).toList();
  }

  void _refreshFilteredData() {
    if (_dataSource == null) {
      return;
    }
    _dataSource!.updateComparisonMap(
      _showParepareDiff ? _parepareComparison : null,
    );
    final filtered = _filteredRecords();
    _dataSource!.updateData(filtered);
  }

  Future<void> _handleBulkEditStatus() async {
    final selected = _dataGridController.selectedRows;
    if (selected.isEmpty) return;

    String? selectedStatus;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('Ubah Status ${selected.length} Data'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Pilih status baru untuk data yang dipilih:'),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: selectedStatus,
                    items: const [
                      DropdownMenuItem(value: '1', child: Text('Ditemukan')),
                      DropdownMenuItem(
                        value: '99',
                        child: Text('Tidak Ditemukan'),
                      ),
                      DropdownMenuItem(value: '3', child: Text('Tutup')),
                      DropdownMenuItem(value: '4', child: Text('Ganda')),
                      DropdownMenuItem(value: '5', child: Text('Usaha Baru')),
                    ],
                    onChanged: (v) {
                      setState(() {
                        selectedStatus = v;
                      });
                    },
                    decoration: const InputDecoration(
                      labelText: 'Status GC',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Batal'),
                ),
                ElevatedButton(
                  onPressed: selectedStatus != null
                      ? () => Navigator.pop(ctx, true)
                      : null,
                  child: const Text('Simpan'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirm == true && selectedStatus != null) {
      // Show progress dialog
      final progressNotifier = ValueNotifier<double>(0.0);
      final currentItemNotifier = ValueNotifier<String>('');

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Memperbarui Status'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder<double>(
                valueListenable: progressNotifier,
                builder: (context, progress, _) {
                  return LinearProgressIndicator(value: progress);
                },
              ),
              const SizedBox(height: 16),
              ValueListenableBuilder<String>(
                valueListenable: currentItemNotifier,
                builder: (context, item, _) {
                  return Text(
                    item,
                    style: const TextStyle(fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  );
                },
              ),
              const SizedBox(height: 8),
              ValueListenableBuilder<double>(
                valueListenable: progressNotifier,
                builder: (context, progress, _) {
                  return Text('${(progress * 100).toInt()}%');
                },
              ),
            ],
          ),
        ),
      );

      int count = 0;
      final total = selected.length;

      for (var i = 0; i < total; i++) {
        final row = selected[i];
        final record = _dataSource?.getRecord(row);

        if (record != null) {
          // Update progress
          currentItemNotifier.value = 'Memproses: ${record.namaUsaha}';
          progressNotifier.value = (i + 1) / total;

          // Cek apakah perlu status revisi (jika sudah diupload sebelumnya)
          final bool shouldBeRevisi = record.isUploaded || record.isRevisi;

          final updated = GroundcheckRecord(
            idsbr: record.idsbr,
            namaUsaha: record.namaUsaha,
            alamatUsaha: record.alamatUsaha,
            kodeWilayah: record.kodeWilayah,
            statusPerusahaan: record.statusPerusahaan,
            skalaUsaha: record.skalaUsaha,
            gcsResult: selectedStatus!,
            sumberData: record.sumberData,
            latitude: record.latitude,
            longitude: record.longitude,
            perusahaanId: record.perusahaanId,
            userId: record.userId,
            isUploaded: false, // Reset status upload karena data berubah
            isRevisi: shouldBeRevisi,
          );

          // Update local list
          final idx = _allRecords.indexWhere((r) => r.idsbr == record.idsbr);
          if (idx != -1) {
            _allRecords[idx] = updated;
          }

          // Update Supabase
          await _supabaseService.updateRecord(updated, updateTimestamp: true);

          count++;

          // Small delay to allow UI to update
          await Future.delayed(const Duration(milliseconds: 50));
        }
      }

      // Save local cache once
      await _supabaseService.saveLocalRecords(_allRecords);

      // Refresh Map
      try {
        MapRepositoryImpl().invalidatePlacesCache();
        if (mounted) {
          context.read<MapBloc>().add(const PlacesRequested());
        }
      } catch (_) {}

      _refreshFilteredData();

      // Close progress dialog
      if (mounted) {
        Navigator.pop(context);

        // setState(() {
        //   _isLoading = false;
        // });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Berhasil mengubah status $count data')),
        );
        setState(() {
          _dataGridController.selectedRows = [];
        });
      }
    }
  }

  Future<void> _handleBulkCancelGc() async {
    final selected = _dataGridController.selectedRows;
    if (selected.isEmpty) return;

    final revisiRecords = <GroundcheckRecord>[];
    if (_dataSource != null) {
      for (final row in selected) {
        final record = _dataSource!.getRecord(row);
        // Perbaikan: Support juga status isUploaded (bukan hanya revisi) asalkan allowCancel=true
        if (record != null &&
            (record.isRevisi || record.isUploaded) &&
            record.allowCancel) {
          revisiRecords.add(record);
        }
      }
    }

    if (revisiRecords.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Tidak ada data yang dapat dibatalkan (Uploaded/Revisi & allowCancel).',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Batalkan ${revisiRecords.length} Kiriman?'),
          content: const Text(
            'Data yang dibatalkan akan kembali menjadi status "Belum Upload" dan bisa dikirim ulang.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text(
                'Ya, Batalkan',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    // Show progress dialog
    final progressNotifier = ValueNotifier<int>(0);
    final successNotifier = ValueNotifier<int>(0);
    final failNotifier = ValueNotifier<int>(0);
    final isFinishedNotifier = ValueNotifier<bool>(false);
    final total = revisiRecords.length;

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            title: const Text('Membatalkan Kiriman...'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ValueListenableBuilder<int>(
                  valueListenable: progressNotifier,
                  builder: (ctx, val, _) {
                    return LinearProgressIndicator(
                      value: total > 0 ? val / total : 0,
                    );
                  },
                ),
                const SizedBox(height: 16),
                ValueListenableBuilder<int>(
                  valueListenable: successNotifier,
                  builder: (ctx, val, _) => Text('Berhasil: $val'),
                ),
                ValueListenableBuilder<int>(
                  valueListenable: failNotifier,
                  builder: (ctx, val, _) => Text(
                    'Gagal: $val',
                    style: TextStyle(
                      color: val > 0 ? Colors.red : Colors.black,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ValueListenableBuilder<bool>(
                  valueListenable: isFinishedNotifier,
                  builder: (ctx, isFinished, _) {
                    if (!isFinished) return const SizedBox.shrink();
                    return ElevatedButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Tutup'),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );

    int successCount = 0;
    int failCount = 0;

    for (int i = 0; i < total; i++) {
      final record = revisiRecords[i];
      try {
        final result = await _gcService.cancelKonfirmasiUser(
          perusahaanId: record.perusahaanId,
        );

        // Asumsi result != null berarti sukses (karena method service sudah handle error catch null)
        // Dan kita anggap 'Cancelled' message atau JSON apapun sebagai success untuk reset status lokal
        if (result != null) {
          // Sukses cancel di server, reset status di DB & Lokal
          final resetSuccess = await _supabaseService.resetRevisiStatus(
            record.idsbr,
          );
          if (resetSuccess) {
            successCount++;
            // Update in-memory list agar UI langsung berubah tanpa reload
            final idx = _allRecords.indexWhere((r) => r.idsbr == record.idsbr);
            if (idx != -1) {
              _allRecords[idx] = _allRecords[idx].copyWith(
                isUploaded: false,
                isRevisi: false,
              );
            }
          } else {
            failCount++;
            debugPrint('Gagal reset status lokal untuk ${record.idsbr}');
          }
        } else {
          failCount++;
          debugPrint('Gagal cancelKonfirmasiUser untuk ${record.idsbr}');
          // Jika ditolak/gagal cancel, set allow_cancel = false
          await _supabaseService.disableAllowCancel(record.idsbr);

          final idx = _allRecords.indexWhere((r) => r.idsbr == record.idsbr);
          if (idx != -1) {
            _allRecords[idx] = _allRecords[idx].copyWith(allowCancel: false);
          }
        }
      } catch (e) {
        failCount++;
        debugPrint('Exception cancel GC: $e');
        // Jika error exception, mungkin koneksi, jangan disable allow_cancel dulu?
        // User bilang "klo ditolak", asumsi rejected by server response, bukan network error.
        // Jadi di block ini kita skip disableAllowCancel kecuali kita yakin itu penolakan server.
      }

      progressNotifier.value = i + 1;
      successNotifier.value = successCount;
      failNotifier.value = failCount;

      // Small delay
      if (i < total - 1) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }

    isFinishedNotifier.value = true;
    _dataGridController.selectedRows = [];

    // Refresh UI
    _refreshFilteredData();

    // Refresh Map
    try {
      MapRepositoryImpl().invalidatePlacesCache();
      if (mounted) {
        context.read<MapBloc>().add(const PlacesRequested());
      }
    } catch (_) {}
  }

  Future<void> _handleBulkDeleteNew() async {
    final selectedRows = _dataGridController.selectedRows;
    if (selectedRows.isEmpty) return;

    // Filter only TEMP- records
    final tempIds = <String>[];
    if (_dataSource != null) {
      for (final row in selectedRows) {
        final r = _dataSource!.getRecord(row);
        if (r != null && r.idsbr.toUpperCase().startsWith('TEMP-')) {
          tempIds.add(r.idsbr);
        }
      }
    }

    if (tempIds.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus Data Baru'),
        content: Text(
          'Yakin ingin menghapus ${tempIds.length} data baru yang dipilih?\n'
          'Data akan dihapus dari server dan lokal.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() {
        _isDeletingNew = true;
      });

      final success = await _supabaseService.deleteRecords(tempIds);

      if (mounted) {
        setState(() {
          _isDeletingNew = false;
        });

        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Data berhasil dihapus'),
              backgroundColor: Colors.green,
            ),
          );
          _dataGridController.selectedRows = [];
          setState(() {});

          // Refresh data
          final records = await _supabaseService.loadLocalRecords();
          _processRecords(records);

          // Refresh Map
          try {
            MapRepositoryImpl().invalidatePlacesCache();
            if (mounted) {
              context.read<MapBloc>().add(const PlacesRequested());
            }
          } catch (_) {}
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Gagal menghapus data'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<_GeocodeResult?> _geocodeAddress(String address) async {
    const apiKey = 'AIzaSyDnmzg1NGiODI5clNzFd0G3SkpQm_HavUE';
    try {
      // Pastikan konteks wilayah Parepare disertakan dalam query
      String searchAddress = address;
      if (!searchAddress.toLowerCase().contains('parepare')) {
        searchAddress = '$searchAddress, Parepare';
      }
      searchAddress = '$searchAddress, Sulawesi Selatan, Indonesia';

      // Gunakan komponen filter untuk membatasi hasil di Parepare
      final url = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
        'address': searchAddress,
        'components': 'locality:Parepare|country:ID',
        'key': apiKey,
      });

      debugPrint('[Geocoding] Request: $url');

      final response = await http.get(url);

      debugPrint('[Geocoding] Response Code: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'OK') {
          final results = data['results'] as List;
          if (results.isNotEmpty) {
            final geometry = results[0]['geometry'];
            final location = geometry['location'];
            final lat = location['lat'];
            final lng = location['lng'];

            LatLng? ne;
            LatLng? sw;
            if (geometry['viewport'] != null) {
              final viewport = geometry['viewport'];
              ne = LatLng(
                viewport['northeast']['lat'],
                viewport['northeast']['lng'],
              );
              sw = LatLng(
                viewport['southwest']['lat'],
                viewport['southwest']['lng'],
              );
            }

            debugPrint('[Geocoding] Success: $lat, $lng (Address: $address)');
            return _GeocodeResult(
              LatLng(lat, lng),
              viewportNE: ne,
              viewportSW: sw,
            );
          }
        } else {
          debugPrint('[Geocoding] API Error Status: ${data['status']}');
          debugPrint('[Geocoding] Error Message: ${data['error_message']}');
        }
      } else {
        debugPrint('[Geocoding] HTTP Error: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[Geocoding] Error: $e');
    }
    return null;
  }

  Future<String?> _reverseGeocodeGoogleRoute(double lat, double lng) async {
    const apiKey = 'AIzaSyDnmzg1NGiODI5clNzFd0G3SkpQm_HavUE';
    try {
      final url = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
        'latlng': '$lat,$lng',
        'language': 'id',
        'key': apiKey,
      });

      debugPrint('[ReverseGeocoding][Google] Request: $url');

      final response = await http.get(url);
      debugPrint(
        '[ReverseGeocoding][Google] Response Code: ${response.statusCode}',
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'OK') {
          final results = data['results'] as List;
          if (results.isNotEmpty) {
            String? street;

            for (final r in results) {
              if (r is Map<String, dynamic>) {
                final comps = r['address_components'];
                if (comps is List) {
                  for (final c in comps) {
                    if (c is Map<String, dynamic>) {
                      final types =
                          (c['types'] as List?)?.cast<String>() ?? <String>[];
                      if (types.contains('route')) {
                        final name = (c['long_name'] ?? c['short_name'] ?? '')
                            .toString()
                            .trim();
                        if (name.isNotEmpty) {
                          street = name;
                          break;
                        }
                      }
                    }
                  }
                }
              }
              if (street != null && street!.isNotEmpty) break;
            }

            if (street == null || street!.isEmpty) {
              final first = results[0];
              if (first is Map<String, dynamic>) {
                final comps = first['address_components'];
                if (comps is List && comps.isNotEmpty) {
                  final c0 = comps[0];
                  if (c0 is Map<String, dynamic>) {
                    final ln = (c0['long_name'] ?? '').toString().trim();
                    final types0 =
                        (c0['types'] as List?)?.cast<String>() ?? <String>[];
                    final isAdmin = types0.any(
                      (t) =>
                          t.startsWith('administrative_area_level') ||
                          t == 'country' ||
                          t == 'postal_code',
                    );
                    if (ln.isNotEmpty && !isAdmin) {
                      street = ln;
                    }
                  }
                }
              }
            }

            if (street == null || street!.isEmpty) {
              debugPrint(
                '[ReverseGeocoding][Google] No suitable street for ($lat, $lng).',
              );
              return null;
            }

            debugPrint(
              '[ReverseGeocoding][Google] Success (route): $street ($lat, $lng)',
            );
            return street;
          }
        } else {
          debugPrint(
            '[ReverseGeocoding][Google] API Error Status: ${data['status']}',
          );
          debugPrint(
            '[ReverseGeocoding][Google] Error Message: ${data['error_message']}',
          );
        }
      } else {
        debugPrint(
          '[ReverseGeocoding][Google] HTTP Error: ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('[ReverseGeocoding][Google] Error: $e');
    }
    return null;
  }

  Future<String?> _reverseGeocodeGoogleRoads(double lat, double lng) async {
    const apiKey = 'AIzaSyDnmzg1NGiODI5clNzFd0G3SkpQm_HavUE';
    try {
      final url = Uri.https('roads.googleapis.com', '/v1/nearestRoads', {
        'points': '$lat,$lng',
        'key': apiKey,
      });

      debugPrint('[ReverseGeocoding][Roads] Request: $url');

      final response = await http.get(url);
      debugPrint(
        '[ReverseGeocoding][Roads] Response Code: ${response.statusCode}',
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final snapped = data['snappedPoints'];
        if (snapped is List && snapped.isNotEmpty) {
          final first = snapped[0] as Map<String, dynamic>;
          final loc = first['location'] as Map<String, dynamic>?;
          if (loc != null) {
            final snappedLat = (loc['latitude'] as num).toDouble();
            final snappedLng = (loc['longitude'] as num).toDouble();
            debugPrint(
              '[ReverseGeocoding][Roads] Snapped to $snappedLat,$snappedLng',
            );
            return _reverseGeocodeGoogleRoute(snappedLat, snappedLng);
          }
        } else {
          debugPrint(
            '[ReverseGeocoding][Roads] No snappedPoints for ($lat,$lng)',
          );
        }
      } else {
        debugPrint(
          '[ReverseGeocoding][Roads] HTTP Error: ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('[ReverseGeocoding][Roads] Error: $e');
    }
    return null;
  }

  Future<String?> _reverseGeocodeOsm(double lat, double lng) async {
    try {
      final url = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'format': 'jsonv2',
        'lat': '$lat',
        'lon': '$lng',
        'zoom': '18',
        'addressdetails': '1',
      });

      debugPrint('[ReverseGeocoding][OSM] Request: $url');

      final response = await http.get(
        url,
        headers: {'User-Agent': 'direktori-app/1.0'},
      );

      debugPrint(
        '[ReverseGeocoding][OSM] Response Code: ${response.statusCode}',
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final addr = data['address'] as Map<String, dynamic>?;
        if (addr != null) {
          final candidates =
              [
                    addr['road'],
                    addr['pedestrian'],
                    addr['footway'],
                    addr['cycleway'],
                    addr['path'],
                  ]
                  .whereType<String>()
                  .map((e) => e.trim())
                  .where((e) => e.isNotEmpty)
                  .toList();

          if (candidates.isNotEmpty) {
            final street = candidates.first;
            debugPrint(
              '[ReverseGeocoding][OSM] Success (road): $street ($lat, $lng)',
            );
            return street;
          }
        }
      } else {
        debugPrint(
          '[ReverseGeocoding][OSM] HTTP Error: ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('[ReverseGeocoding][OSM] Error: $e');
    }
    return null;
  }

  Future<String?> _reverseGeocode(double lat, double lng) async {
    final fromGoogleRoute = await _reverseGeocodeGoogleRoute(lat, lng);
    if (fromGoogleRoute != null && fromGoogleRoute.isNotEmpty) {
      return fromGoogleRoute;
    }

    final fromRoads = await _reverseGeocodeGoogleRoads(lat, lng);
    if (fromRoads != null && fromRoads.isNotEmpty) {
      return fromRoads;
    }

    final fromOsm = await _reverseGeocodeOsm(lat, lng);
    if (fromOsm != null && fromOsm.isNotEmpty) {
      return fromOsm;
    }

    return null;
  }

  // Helper untuk mencari polygon yang sesuai dengan kode wilayah
  List<_SlsPolygon> _findTargetPolygons(String kodeWilayah) {
    String recCode = kodeWilayah.replaceAll('.', '').trim();
    List<_SlsPolygon> matches = [];

    for (var poly in _polygons) {
      String polyCode = poly.idsls.trim();
      bool isMatch = false;

      if (recCode.length >= 10 && polyCode.length >= 10) {
        if (recCode.substring(0, 10) == polyCode.substring(0, 10))
          isMatch = true;
      } else if (recCode.length >= 7 && polyCode.length >= 7) {
        if (recCode.substring(0, 7) == polyCode.substring(0, 7)) isMatch = true;
      } else {
        if (polyCode.startsWith(recCode) || recCode.startsWith(polyCode))
          isMatch = true;
      }

      if (isMatch) matches.add(poly);
    }
    return matches;
  }

  // Helper untuk mencari titik terdekat di dalam polygon dari sebuah titik referensi
  LatLng _findClosestPointInPolygon(LatLng target, List<LatLng> polygon) {
    double minDistance = double.infinity;
    LatLng closest = polygon[0];

    for (var p in polygon) {
      // Hitung jarak Euclidean sederhana (cukup untuk skala kecil)
      double dist =
          (p.latitude - target.latitude) * (p.latitude - target.latitude) +
          (p.longitude - target.longitude) * (p.longitude - target.longitude);
      if (dist < minDistance) {
        minDistance = dist;
        closest = p;
      }
    }
    return closest;
  }

  // Helper cek intersection antara bounding box polygon dan viewport
  bool _isPolygonInViewport(List<LatLng> polygon, LatLng ne, LatLng sw) {
    // Hitung bounds polygon
    double minLat = 90, maxLat = -90, minLng = 180, maxLng = -180;
    for (var p in polygon) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    // Cek overlap bounding box
    // Viewport bounds:
    double vMinLat = sw.latitude;
    double vMaxLat = ne.latitude;
    double vMinLng = sw.longitude;
    double vMaxLng = ne.longitude;

    bool latOverlap = (minLat <= vMaxLat) && (maxLat >= vMinLat);
    bool lngOverlap = (minLng <= vMaxLng) && (maxLng >= vMinLng);

    return latOverlap && lngOverlap;
  }

  // Helper: Ekstrak RT/RW dari alamat dan normalisasi ke format "RT 001 RW 002"
  String? _extractRtRw(String address) {
    // Regex untuk menangkap RT dan RW (case insensitive)
    // Contoh match: "RT 01 RW 02", "Rt.1 Rw.2", "RT 001/RW 002"
    final regex = RegExp(
      r'RT\s*[.]?\s*(\d+).*?RW\s*[.]?\s*(\d+)',
      caseSensitive: false,
    );
    final match = regex.firstMatch(address);

    if (match != null) {
      String rt = match.group(1)!;
      String rw = match.group(2)!;

      // Pad dengan 0 di depan jika panjang < 3
      rt = rt.padLeft(3, '0');
      rw = rw.padLeft(3, '0');

      return 'RT $rt RW $rw';
    }
    return null;
  }

  // Helper: Bersihkan alamat dari RT/RW agar lebih ramah Google Maps
  String _cleanAddressForGoogleMaps(String address) {
    // Hapus pola RT 1 RW 2, RT.001 RW.002, RT/RW, dll.
    // Termasuk menangani RT 0/RW 0, RT - / RW - (dummy data)

    // Regex:
    // \b(rt|rw)\b : Kata RT atau RW
    // [.\s/-]* : Pemisah (titik, spasi, slash, dash) boleh ada boleh tidak
    // [\d-]* : Angka atau dash (untuk menangani RT -)
    final rtRwRegex = RegExp(
      r'\b(rt|rw)\b[.\s/-]*[\d-]*',
      caseSensitive: false,
    );

    // Hapus RT/RW beserta angkanya
    String cleaned = address.replaceAll(rtRwRegex, '');

    // Bersihkan sisa karakter pemisah yang berlebihan (koma ganda, spasi ganda, slash sisa)
    cleaned = cleaned.replaceAll(
      RegExp(r'\s+'),
      ' ',
    ); // Spasi ganda -> satu spasi
    cleaned = cleaned.replaceAll(
      RegExp(r'[,/.-]\s*[,/.-]'),
      ',',
    ); // Tanda baca beruntun -> satu koma
    cleaned = cleaned.replaceAll(
      RegExp(r'^[\s,./-]+|[\s,./-]+$'),
      '',
    ); // Trim koma/spasi/slash di awal/akhir

    return cleaned.trim();
  }

  // Helper: Cari polygon berdasarkan Kode Desa dan Nama SLS (RT/RW)
  _SlsPolygon? _findPolygonBySls(String kodeWilayah, String nmsls) {
    // Pastikan kodeWilayah minimal 10 digit (Kode Desa)
    String cleanKode = kodeWilayah.replaceAll('.', '').trim();
    if (cleanKode.length < 10) return null;
    final kodeDesa = cleanKode.substring(0, 10);

    for (final poly in _polygons) {
      if (poly.idsls.startsWith(kodeDesa) &&
          poly.nmsls.toUpperCase() == nmsls.toUpperCase()) {
        return poly;
      }
    }
    return null;
  }

  // Helper: Dapatkan titik representatif dalam polygon (Centroid atau titik pertama)
  LatLng _getFallbackPoint(List<LatLng> points) {
    if (points.isEmpty) return const LatLng(0, 0);

    // Hitung centroid sederhana
    double sumLat = 0;
    double sumLng = 0;
    for (var p in points) {
      sumLat += p.latitude;
      sumLng += p.longitude;
    }
    final centroid = LatLng(sumLat / points.length, sumLng / points.length);

    // Cek apakah centroid ada di dalam polygon
    if (_isPointInPolygon(centroid, points)) {
      return centroid;
    }

    // Jika tidak (polygon cekung ekstrem), kembalikan titik pertama saja
    return points.first;
  }

  // Helper validasi hasil geocoding terhadap wilayah
  ({bool isValid, LatLng? point, String message}) _validateLocation(
    String kodeWilayah,
    _GeocodeResult result,
  ) {
    LatLng finalPoint = result.location;
    String logMsg = "";
    bool isValid = false;

    // Validasi Wilayah
    final targetPolys = _findTargetPolygons(kodeWilayah);

    if (targetPolys.isNotEmpty) {
      // 1. Cek apakah titik utama masuk SALAH SATU polygon?
      bool inAnyPoly = false;
      for (final poly in targetPolys) {
        if (_isPointInPolygon(finalPoint, poly.points)) {
          inAnyPoly = true;
          break;
        }
      }

      if (inAnyPoly) {
        isValid = true;
        logMsg = "Titik masuk polygon wilayah.";
      } else {
        // 2. Jika tidak masuk, cek Range (Viewport) terhadap SEMUA polygon
        if (result.viewportNE != null && result.viewportSW != null) {
          _SlsPolygon? closestPoly;
          double minPolyDist = double.infinity;

          for (final poly in targetPolys) {
            if (_isPolygonInViewport(
              poly.points,
              result.viewportNE!,
              result.viewportSW!,
            )) {
              // Cari titik terdekat di dalam polygon ini
              final closestInPoly = _findClosestPointInPolygon(
                finalPoint,
                poly.points,
              );
              // Hitung jarak squared (cukup untuk perbandingan)
              final dLat = closestInPoly.latitude - finalPoint.latitude;
              final dLng = closestInPoly.longitude - finalPoint.longitude;
              final distSq = dLat * dLat + dLng * dLng;

              if (distSq < minPolyDist) {
                minPolyDist = distSq;
                closestPoly = poly;
              }
            }
          }

          if (closestPoly != null) {
            // Gunakan titik terdekat dari polygon yang paling dekat
            finalPoint = _findClosestPointInPolygon(
              finalPoint,
              closestPoly.points,
            );
            isValid = true;
            logMsg =
                "Titik digeser ke polygon ${closestPoly.nmsls} (jarak terdekat).";
          } else {
            logMsg = "Titik di luar wilayah dan di luar range.";
          }
        } else {
          logMsg = "Titik di luar wilayah (tidak ada info range).";
        }
      }
    } else {
      // Jika polygon target tidak ditemukan di metadata kita
      logMsg = "Polygon wilayah target tidak ditemukan.";
    }

    return (
      isValid: isValid,
      point: isValid ? finalPoint : null,
      message: logMsg,
    );
  }

  Future<void> _handleBulkLapor() async {
    // Pastikan GCID map termuat
    await _loadGcidMap();

    if (!mounted) return;

    final selected = _dataGridController.selectedRows;
    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih data terlebih dahulu.')),
      );
      return;
    }

    final records = <GroundcheckRecord>[];
    if (_dataSource != null) {
      for (final row in selected) {
        final r = _dataSource!.getRecord(row);
        if (r != null) records.add(r);
      }
    }

    if (records.isEmpty) return;

    // Show Dialog to choose status
    final int? selectedStatus = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Pilih Status Laporan'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 4),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('4. Ganda (Duplicate)'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 3),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('3. Tutup (Closed)'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 1),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('1. Ada (Active)'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 2),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('2. Tutup Sementara'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 5),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('5. Usaha Baru'),
            ),
          ),
        ],
      ),
    );

    if (selectedStatus == null) return;

    if (!mounted) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Lapor ${records.length} Data?'),
        content: Text(
          'Anda akan melaporkan ${records.length} data dengan status $selectedStatus. Proses ini akan mengirim data ke server.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Lapor'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // Progress Dialog
    final ValueNotifier<int> progressNotifier = ValueNotifier(0);
    final ValueNotifier<int> successNotifier = ValueNotifier(0);
    final ValueNotifier<int> failNotifier = ValueNotifier(0);
    final ValueNotifier<String> statusNotifier = ValueNotifier('Menyiapkan...');
    bool isCancelled = false;

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => PopScope(
          canPop: false,
          child: AlertDialog(
            title: const Text('Proses Lapor GC'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ValueListenableBuilder<String>(
                  valueListenable: statusNotifier,
                  builder: (_, val, __) =>
                      Text(val, textAlign: TextAlign.center),
                ),
                const SizedBox(height: 16),
                ValueListenableBuilder<int>(
                  valueListenable: progressNotifier,
                  builder: (_, val, __) => LinearProgressIndicator(
                    value: records.isNotEmpty ? val / records.length : 0,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ValueListenableBuilder<int>(
                      valueListenable: successNotifier,
                      builder: (_, val, __) => Column(
                        children: [
                          const Text(
                            'Sukses',
                            style: TextStyle(color: Colors.green),
                          ),
                          Text('$val'),
                        ],
                      ),
                    ),
                    ValueListenableBuilder<int>(
                      valueListenable: failNotifier,
                      builder: (_, val, __) => Column(
                        children: [
                          const Text(
                            'Gagal',
                            style: TextStyle(color: Colors.red),
                          ),
                          Text('$val'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  isCancelled = true;
                  Navigator.pop(ctx);
                },
                child: const Text('Batal'),
              ),
            ],
          ),
        ),
      );
    }

    // Pastikan session service up-to-date
    if (_gcCookie != null && _userAgent != null) {
      _gcService.setCredentials(
        cookie: _gcCookie!,
        csrfToken: _csrfToken ?? '',
        gcToken: _gcToken ?? '',
        userAgent: _userAgent!,
      );
    }

    for (var i = 0; i < records.length; i++) {
      if (isCancelled) break;
      final record = records[i];

      statusNotifier.value = 'Memproses ${record.namaUsaha}...';

      // Gunakan GCID dari parepare_comparison.json
      final gcid = _idsbrToGcid[record.idsbr];
      if (gcid == null || gcid.isEmpty) {
        debugPrint('GCID not found for IDSBR: ${record.idsbr}. Skipping.');
        failNotifier.value++;
        progressNotifier.value = i + 1;
        // Skip record ini karena tidak ada GCID
        continue;
      }

      try {
        final result = await _gcService.reportGcUser(
          refIdTable: gcid,
          statusHasilGc: selectedStatus.toString(),
          latitude: record.latitude,
          longitude: record.longitude,
          namaUsahaGc: record.namaUsaha,
          alamatUsahaGc: record.alamatUsaha,
        );

        if (result != null && result['status'] == 'success') {
          successNotifier.value++;

          // Update status lokal
          await _supabaseService.updateGcsResult(
            record.idsbr,
            selectedStatus.toString(),
            userId: _currentLoginId ?? _currentUser,
          );
        } else {
          failNotifier.value++;
          debugPrint('Lapor failed for ${record.idsbr}: $result');
        }
      } catch (e) {
        failNotifier.value++;
        debugPrint('Lapor error for ${record.idsbr}: $e');
      }

      progressNotifier.value = i + 1;
      await Future.delayed(
        const Duration(milliseconds: 100),
      ); // Rate limit slightly
    }

    if (mounted && !isCancelled) {
      Navigator.pop(context); // Close progress dialog

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Selesai. Sukses: ${successNotifier.value}, Gagal: ${failNotifier.value}',
          ),
        ),
      );

      // Refresh data
      _refreshFilteredData();
    }
  }

  Future<void> _handleBulkGeocoding() async {
    final selected = _dataGridController.selectedRows;
    if (selected.isEmpty) return;

    final records = <GroundcheckRecord>[];
    if (_dataSource != null) {
      for (final row in selected) {
        final r = _dataSource!.getRecord(row);
        if (r != null) records.add(r);
      }
    }

    if (records.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Geocoding ${records.length} Data'),
        content: const Text(
          'Akan mencari koordinat dengan prioritas:\n'
          '1. Pencocokan RT/RW (SLS) Lokal\n'
          '2. Google Maps API (Nama Usaha + Alamat)\n'
          '3. Google Maps API (Alamat saja)\n'
          '4. Google Maps API (Nama Usaha saja)\n\n'
          'Sistem akan memprioritaskan titik tengah RT/RW jika ditemukan. Jika tidak, akan menggunakan Google Maps dengan validasi wilayah (harus masuk polygon atau dekat).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Mulai'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // Progress Dialog Setup
    final ValueNotifier<int> progressNotifier = ValueNotifier(0);
    final ValueNotifier<int> successNotifier = ValueNotifier(0);
    final ValueNotifier<int> failNotifier = ValueNotifier(0);
    final ValueNotifier<String> statusNotifier = ValueNotifier('Menyiapkan...');
    bool isCancelled = false;

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => PopScope(
          canPop: false,
          child: AlertDialog(
            title: const Text('Proses Geocoding'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ValueListenableBuilder<String>(
                  valueListenable: statusNotifier,
                  builder: (_, val, __) =>
                      Text(val, textAlign: TextAlign.center),
                ),
                const SizedBox(height: 16),
                ValueListenableBuilder<int>(
                  valueListenable: progressNotifier,
                  builder: (_, val, __) => LinearProgressIndicator(
                    value: records.isNotEmpty ? val / records.length : 0,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ValueListenableBuilder<int>(
                      valueListenable: successNotifier,
                      builder: (_, val, __) => Column(
                        children: [
                          const Text(
                            'Sukses',
                            style: TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text('$val'),
                        ],
                      ),
                    ),
                    ValueListenableBuilder<int>(
                      valueListenable: failNotifier,
                      builder: (_, val, __) => Column(
                        children: [
                          const Text(
                            'Gagal',
                            style: TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text('$val'),
                        ],
                      ),
                    ),
                    Column(
                      children: [
                        const Text(
                          'Total',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text('${records.length}'),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () {
                    isCancelled = true;
                    Navigator.pop(ctx);
                  },
                  child: const Text('Batal'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    int success = 0;
    int fail = 0;

    for (int i = 0; i < records.length; i++) {
      if (isCancelled) break;
      final record = records[i];

      statusNotifier.value =
          'Memproses (${i + 1}/${records.length})\n${record.namaUsaha}';

      bool recordSuccess = false;
      String lastLogMsg = "Tidak ada strategi pencarian yang valid.";

      // Strategi 1: Hybrid SLS + Google Maps
      // 1. Cari polygon SLS target
      // 2. Cari di Google Maps
      // 3. Jika Google Maps ketemu & masuk polygon SLS -> Pakai Google Maps (Akurat)
      // 4. Jika Google Maps ketemu tapi luar polygon -> Pakai titik tengah SLS (Estimasi)
      // 5. Jika Google Maps gagal -> Pakai titik tengah SLS (Estimasi)

      if (!isCancelled) {
        debugPrint('[Geocoding] Trying SLS Matching for ${record.namaUsaha}');
        final nmsls = _extractRtRw(record.alamatUsaha);

        _SlsPolygon? targetSlsPoly;
        if (nmsls != null) {
          targetSlsPoly = _findPolygonBySls(record.kodeWilayah, nmsls);
        }

        // Jika SLS ditemukan, kita punya "target area" yang lebih spesifik
        if (targetSlsPoly != null) {
          debugPrint(
            '[Geocoding] SLS Polygon found: $nmsls. Trying Google Maps for precision...',
          );

          // Coba cari di Google Maps dulu untuk presisi
          LatLng? googlePoint;
          bool googlePointValid = false;

          final strategies = <String>[];
          final cleanAddress = _cleanAddressForGoogleMaps(record.alamatUsaha);

          if (record.namaUsaha.isNotEmpty && cleanAddress.isNotEmpty) {
            strategies.add('${record.namaUsaha}, $cleanAddress');
          }
          if (cleanAddress.isNotEmpty) {
            strategies.add(cleanAddress);
          }

          for (final query in strategies) {
            if (isCancelled) break;
            final result = await _geocodeAddress(query);
            if (result != null) {
              // 1. Cek Exact Match: Apakah titik pusat Google Maps ada di dalam Polygon SLS?
              if (_isPointInPolygon(result.location, targetSlsPoly.points)) {
                googlePoint = result.location;
                googlePointValid = true;
                debugPrint(
                  '[Geocoding] Google Maps point is INSIDE target SLS. Using high precision point.',
                );
                break;
              }
              // 2. Cek Intersection: Apakah Area Jalan (Viewport) beririsan dengan Polygon SLS?
              else if (result.viewportNE != null && result.viewportSW != null) {
                if (_isPolygonInViewport(
                  targetSlsPoly.points,
                  result.viewportNE!,
                  result.viewportSW!,
                )) {
                  // Jalan melintasi SLS! Ambil titik di dalam SLS yang paling dekat dengan pusat jalan.
                  final closestInPoly = _findClosestPointInPolygon(
                    result.location,
                    targetSlsPoly.points,
                  );

                  googlePoint = closestInPoly;
                  googlePointValid = true;
                  debugPrint(
                    '[Geocoding] Google Maps Viewport INTERSECTS target SLS. Snapped to closest point in SLS.',
                  );
                  break;
                } else {
                  debugPrint(
                    '[Geocoding] Google Maps Viewport DOES NOT intersect target SLS.',
                  );
                }
              } else {
                debugPrint(
                  '[Geocoding] Google Maps point is OUTSIDE target SLS and no Viewport info. Ignoring.',
                );
              }
            }
            await Future.delayed(const Duration(milliseconds: 200));
          }

          // Tentukan titik akhir: Google Maps (jika valid) atau Fallback SLS
          final LatLng finalPoint = googlePointValid
              ? googlePoint!
              : _getFallbackPoint(targetSlsPoly.points);

          final msg = googlePointValid
              ? "Ditemukan presisi via Google Maps di dalam SLS $nmsls"
              : "Ditemukan via estimasi titik tengah SLS $nmsls (Google Maps tidak akurat/gagal)";

          final newRecord = record.copyWith(
            latitude: finalPoint.latitude.toString(),
            longitude: finalPoint.longitude.toString(),
          );

          try {
            await _supabaseService.updateRecord(newRecord);
            await _supabaseService.updateLocalRecord(newRecord);
            debugPrint('[Geocoding] Success: $msg');
            success++;
            recordSuccess = true;
            lastLogMsg = msg;
          } catch (e) {
            debugPrint('[Geocoding] DB Error: $e');
            lastLogMsg = "Error simpan DB: $e";
          }
        }
      }

      if (recordSuccess) {
        progressNotifier.value = i + 1;
        continue;
      }

      // Strategi Pencarian Google (Fallback)
      final strategies = <String>[];
      final cleanAddress = _cleanAddressForGoogleMaps(record.alamatUsaha);

      // Gunakan alamat bersih (tanpa RT/RW dummy) untuk strategi pencarian
      if (record.namaUsaha.isNotEmpty && cleanAddress.isNotEmpty) {
        strategies.add('${record.namaUsaha}, $cleanAddress');
      }
      if (cleanAddress.isNotEmpty) {
        strategies.add(cleanAddress);
      }
      // Tetap simpan alamat asli sebagai cadangan jika bersihnya jadi kosong (jarang terjadi)
      if (strategies.isEmpty && record.alamatUsaha.isNotEmpty) {
        strategies.add(record.alamatUsaha);
      }

      if (record.namaUsaha.isNotEmpty) {
        strategies.add(record.namaUsaha);
      }

      // Hapus duplikat dan kosong
      final activeStrategies = strategies
          .where((s) => s.trim().isNotEmpty)
          .toSet()
          .toList();

      if (activeStrategies.isEmpty) {
        debugPrint(
          '[Geocoding] Skipped: No search terms for ${record.namaUsaha}',
        );
        fail++;
        progressNotifier.value = i + 1;
        continue;
      }

      for (final query in activeStrategies) {
        if (isCancelled) break;

        debugPrint('[Geocoding] Trying: $query');
        final result = await _geocodeAddress(query);

        if (result != null) {
          final validation = _validateLocation(record.kodeWilayah, result);
          if (validation.isValid) {
            final finalPoint = validation.point!;
            final newRecord = record.copyWith(
              latitude: finalPoint.latitude.toString(),
              longitude: finalPoint.longitude.toString(),
            );

            try {
              await _supabaseService.updateRecord(newRecord);
              await _supabaseService.updateLocalRecord(newRecord);
              debugPrint(
                '[Geocoding] Success: ${validation.message} (${record.namaUsaha})',
              );
              success++;
              successNotifier.value = success;
              recordSuccess = true;
              lastLogMsg = validation.message;
            } catch (e) {
              debugPrint('[Geocoding] DB Error: $e');
              lastLogMsg = "Error simpan DB: $e";
            }
            break; // Keluar dari loop strategi
          } else {
            lastLogMsg = validation.message;
          }
        } else {
          lastLogMsg = "Tidak ditemukan di Google Maps.";
        }

        // Delay antar strategi
        await Future.delayed(const Duration(milliseconds: 200));
      }

      if (!recordSuccess) {
        debugPrint('[Geocoding] Failed: $lastLogMsg (${record.namaUsaha})');
        fail++;
        failNotifier.value = fail;
      }

      progressNotifier.value = i + 1;
    }

    if (!isCancelled && mounted) {
      Navigator.pop(context); // Close progress dialog

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Geocoding selesai: $success sukses, $fail gagal. Cek debug console untuk detail.',
          ),
          backgroundColor: success > 0 ? Colors.green : Colors.orange,
        ),
      );

      // Refresh Data & Map
      _loadData();
    }
  }

  Future<void> _handleBulkTambahAlamat() async {
    final selected = _dataGridController.selectedRows;
    if (selected.isEmpty) return;

    final records = <GroundcheckRecord>[];
    if (_dataSource != null) {
      for (final row in selected) {
        final r = _dataSource!.getRecord(row);
        if (r != null) records.add(r);
      }
    }

    if (records.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Tambah Alamat dari Koordinat (${records.length})'),
        content: const Text(
          'Sistem akan mencari alamat (reverse geocoding) berdasarkan titik koordinat yang sudah ada.\n'
          'Hanya record dengan koordinat valid yang akan diproses.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Mulai'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final ValueNotifier<int> progressNotifier = ValueNotifier(0);
    final ValueNotifier<int> successNotifier = ValueNotifier(0);
    final ValueNotifier<int> failNotifier = ValueNotifier(0);
    final ValueNotifier<String> statusNotifier = ValueNotifier('Menyiapkan...');
    bool isCancelled = false;

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => PopScope(
          canPop: false,
          child: AlertDialog(
            title: const Text('Proses Tambah Alamat'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ValueListenableBuilder<String>(
                  valueListenable: statusNotifier,
                  builder: (_, val, __) =>
                      Text(val, textAlign: TextAlign.center),
                ),
                const SizedBox(height: 16),
                ValueListenableBuilder<int>(
                  valueListenable: progressNotifier,
                  builder: (_, val, __) => LinearProgressIndicator(
                    value: records.isNotEmpty ? val / records.length : 0,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ValueListenableBuilder<int>(
                      valueListenable: successNotifier,
                      builder: (_, val, __) => Column(
                        children: [
                          const Text(
                            'Berhasil',
                            style: TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text('$val'),
                        ],
                      ),
                    ),
                    ValueListenableBuilder<int>(
                      valueListenable: failNotifier,
                      builder: (_, val, __) => Column(
                        children: [
                          const Text(
                            'Gagal',
                            style: TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text('$val'),
                        ],
                      ),
                    ),
                    Column(
                      children: [
                        const Text(
                          'Total',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text('${records.length}'),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () {
                    isCancelled = true;
                    Navigator.pop(ctx);
                  },
                  child: const Text('Batal'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    int success = 0;
    int fail = 0;

    for (int i = 0; i < records.length; i++) {
      if (isCancelled) break;
      final record = records[i];

      statusNotifier.value =
          'Memproses (${i + 1}/${records.length})\n${record.namaUsaha}';

      final lat = double.tryParse(record.latitude);
      final lng = double.tryParse(record.longitude);

      if (lat == null ||
          lng == null ||
          lat == 0 ||
          lng == 0 ||
          lat < -90 ||
          lat > 90 ||
          lng < -180 ||
          lng > 180) {
        debugPrint(
          '[ReverseGeocoding] Skip: Koordinat tidak valid untuk ${record.idsbr}',
        );
        fail++;
        failNotifier.value = fail;
        progressNotifier.value = i + 1;
        continue;
      }

      try {
        final address = await _reverseGeocode(lat, lng);
        if (address == null || address.isEmpty) {
          fail++;
          failNotifier.value = fail;
        } else {
          final newRecord = record.copyWith(alamatUsaha: address);
          await _supabaseService.updateRecord(newRecord);
          await _supabaseService.updateLocalRecord(newRecord);
          success++;
          successNotifier.value = success;
        }
      } catch (e) {
        debugPrint('[ReverseGeocoding] DB Error: $e');
        fail++;
        failNotifier.value = fail;
      }

      progressNotifier.value = i + 1;
      await Future.delayed(const Duration(milliseconds: 200));
    }

    if (!isCancelled && mounted) {
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Tambah Alamat selesai: $success berhasil, $fail gagal.',
          ),
          backgroundColor: success > 0 ? Colors.green : Colors.orange,
        ),
      );

      _loadData();
    }
  }

  Future<void> _handleBulkTambahUsaha() async {
    final selected = _dataGridController.selectedRows;
    if (selected.isEmpty) return;

    // Filter record yang gcsResult == '5' DAN belum di-upload
    final validRecords = <GroundcheckRecord>[];
    int skippedCount = 0;
    int skippedUploadedCount = 0;
    int skippedNon5Count = 0;

    if (_dataSource != null) {
      for (final row in selected) {
        final record = _dataSource!.getRecord(row);
        if (record != null) {
          if (record.isUploaded) {
            skippedUploadedCount++;
          } else if (record.gcsResult == '5') {
            validRecords.add(record);
          } else {
            // Not code 5
            skippedNon5Count++;
          }
        }
      }
    }

    if (validRecords.isEmpty) {
      if (mounted) {
        String msg = 'Tidak ada data Tambah Usaha (Kode 5) valid.';
        if (skippedUploadedCount > 0) {
          msg = '$skippedUploadedCount data dilewati karena sudah terupload.';
        } else if (skippedNon5Count > 0) {
          msg = 'Data terpilih bukan Kode 5 (Alih Usaha).';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.orange),
        );
      }
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Bulk Tambah Usaha: ${validRecords.length} Data'),
          content: SingleChildScrollView(
            child: ListBody(
              children: [
                Text(
                  'Akan mengirim ${validRecords.length} data Tambah Usaha (Kode 5).',
                ),
                if (skippedUploadedCount > 0 || skippedNon5Count > 0)
                  const SizedBox(height: 12),
                if (skippedUploadedCount > 0)
                  Text(
                    '$skippedUploadedCount data dilewati karena SUDAH terupload.',
                    style: const TextStyle(color: Colors.blue, fontSize: 12),
                  ),
                if (skippedNon5Count > 0)
                  Text(
                    '$skippedNon5Count data dilewati karena BUKAN kode 5.',
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Kirim'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    final configOk = await _ensureGcConfig();
    if (!configOk) return;

    // Setup Progress Dialog
    final ValueNotifier<int> successNotifier = ValueNotifier(0);
    final ValueNotifier<int> failNotifier = ValueNotifier(0);
    final ValueNotifier<String> statusNotifier = ValueNotifier('Menyiapkan...');
    final ValueNotifier<bool> isFinishedNotifier = ValueNotifier(false);
    final ValueNotifier<bool> isCancelledNotifier = ValueNotifier(false);
    bool isDialogVisible = true;

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          return PopScope(
            canPop: false,
            child: AlertDialog(
              title: const Text('Mengirim Tambah Usaha...'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ValueListenableBuilder<String>(
                    valueListenable: statusNotifier,
                    builder: (context, val, child) {
                      return Text(val, textAlign: TextAlign.center);
                    },
                  ),
                  const SizedBox(height: 16),
                  const LinearProgressIndicator(),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ValueListenableBuilder<int>(
                        valueListenable: successNotifier,
                        builder: (context, val, child) {
                          return Column(
                            children: [
                              const Icon(
                                Icons.check_circle,
                                color: Colors.green,
                              ),
                              Text('$val Sukses'),
                            ],
                          );
                        },
                      ),
                      ValueListenableBuilder<int>(
                        valueListenable: failNotifier,
                        builder: (context, val, child) {
                          return Column(
                            children: [
                              const Icon(Icons.error, color: Colors.red),
                              Text('$val Gagal'),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ValueListenableBuilder<bool>(
                    valueListenable: isFinishedNotifier,
                    builder: (context, isFinished, child) {
                      if (!isFinished) {
                        return OutlinedButton(
                          onPressed: () {
                            isCancelledNotifier.value = true;
                            statusNotifier.value = 'Membatalkan...';
                          },
                          child: const Text('Batal'),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                  ValueListenableBuilder<bool>(
                    valueListenable: isFinishedNotifier,
                    builder: (context, isFinished, child) {
                      if (isFinished) {
                        return TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Tutup'),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ).then((_) {
        isDialogVisible = false;
      });
    }

    List<GroundcheckRecord> pendingRecords = List.from(validRecords);
    int maxRetries = 3;
    int successCount = 0;
    int failCount = 0;
    int total = validRecords.length;

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      if (isCancelledNotifier.value) break;
      if (pendingRecords.isEmpty) break;

      final currentBatch = List<GroundcheckRecord>.from(pendingRecords);
      pendingRecords.clear();

      for (int i = 0; i < currentBatch.length; i++) {
        if (isCancelledNotifier.value) break;
        final record = currentBatch[i];

        statusNotifier.value =
            'Percobaan $attempt/$maxRetries\nMengirim ${record.idsbr} (${i + 1}/${currentBatch.length})...';

        try {
          // --- REGION CODE PARSING LOGIC ---
          // 1. Ambil dari record jika ada
          String finalKecCode = record.kdKec ?? '';
          String finalDesaCode = record.kdDesa ?? '';

          // 2. Jika kosong, coba parse dari kodeWilayah (BPS Standard: PPKKKCCDDD)
          // Contoh: 7372030001 -> Kec: 030, Desa: 001
          // Panjang string biasanya 10 digit.
          if ((finalKecCode.isEmpty || finalDesaCode.isEmpty) &&
              record.kodeWilayah.length >= 10) {
            try {
              // PP KK KCC DDD
              // 01 23 456 789
              // Kec ada di index 4-6 (3 digit)
              // Desa ada di index 7-9 (3 digit)
              if (finalKecCode.isEmpty) {
                finalKecCode = record.kodeWilayah.substring(4, 7);
              }
              if (finalDesaCode.isEmpty) {
                finalDesaCode = record.kodeWilayah.substring(7, 10);
              }
            } catch (_) {
              // Ignore parsing error
            }
          }
          // ---------------------------------

          // Convert codes to server IDs
          final String serverProvId = WilayahMapping.serverProvinsiId;
          final String serverKabId = WilayahMapping.serverKabupatenId;
          final String serverKecId = WilayahMapping.getKecamatanId(
            finalKecCode,
          );
          final String serverDesaId = WilayahMapping.getDesaId(
            finalKecCode,
            finalDesaCode,
          );

          // --- DEBUG MODE: PAYLOAD CHECK (LOG ONLY) ---
          final debugPayload = {
            '_token': 'HIDDEN',
            'nama_usaha': record.namaUsaha,
            'alamat': record.alamatUsaha,
            'provinsi': serverProvId,
            'kabupaten': serverKabId,
            'kecamatan': serverKecId,
            'desa': serverDesaId,
            'latitude': record.latitude,
            'longitude': record.longitude,
            'confirmSubmit': true,
          };
          debugPrint('=== MENGIRIM DATA KE SERVER ===');
          debugPrint(const JsonEncoder.withIndent('  ').convert(debugPayload));

          final result = await _gcService.saveDraftTambahUsaha(
            namaUsaha: record.namaUsaha,
            alamat: record.alamatUsaha,
            provinsiId: serverProvId,
            kabupatenId: serverKabId,
            kecamatanId: serverKecId,
            desaId: serverDesaId,
            latitude: record.latitude,
            longitude: record.longitude,
          );

          if (result != null &&
              (result['status'] == 'success' || result['title'] == 'Sukses')) {
            successCount++;

            // Update status upload
            await _applyGcInput(
              record,
              record.gcsResult,
              double.tryParse(record.latitude),
              double.tryParse(record.longitude),
              isUploaded: true,
            );
          } else {
            // Failed
            pendingRecords.add(record);
          }
        } catch (e) {
          pendingRecords.add(record);
        }

        // Small delay
        if (i < currentBatch.length - 1) {
          await Future.delayed(const Duration(milliseconds: 200));
        }
      }

      if (pendingRecords.isNotEmpty && attempt < maxRetries) {
        statusNotifier.value = 'Menunggu sebelum retry...';
        await Future.delayed(const Duration(seconds: 2));
      }
    }

    failCount = total - successCount;
    failNotifier.value = failCount;
    statusNotifier.value = 'Selesai: $successCount Sukses, $failCount Gagal';
    isFinishedNotifier.value = true;

    // Refresh UI
    _dataGridController.selectedRows = [];
    _refreshFilteredData();

    // Refresh Map
    try {
      MapRepositoryImpl().invalidatePlacesCache();
      if (mounted) {
        context.read<MapBloc>().add(const PlacesRequested());
      }
    } catch (_) {}
  }

  Future<void> _handleBulkGc() async {
    // Guard: Jangan mulai upload baru jika ada yang sedang berjalan (hidden atau active)
    if (_activeProgressNotifier != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Harap selesaikan atau tutup proses upload yang sedang berjalan terlebih dahulu.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final selected = _dataGridController.selectedRows;
    if (selected.isEmpty) return;

    // Filter record yang punya hasil GC (gcsResult tidak kosong) DAN belum di-upload
    final validRecords = <GroundcheckRecord>[];
    int skippedCount = 0;
    int skippedUploadedCount = 0;

    if (_dataSource != null) {
      for (final row in selected) {
        final record = _dataSource!.getRecord(row);
        if (record != null) {
          if (record.isUploaded) {
            skippedUploadedCount++;
          } else if (record.gcsResult.isNotEmpty && record.gcsResult != '5') {
            validRecords.add(record);
          } else {
            skippedCount++;
          }
        }
      }
    }

    if (validRecords.isEmpty) {
      if (mounted) {
        String msg = 'Tidak ada data valid untuk dikirim.';
        if (skippedUploadedCount > 0 && skippedCount == 0) {
          msg = 'Semua data terpilih sudah terupload.';
        } else if (skippedCount > 0 && skippedUploadedCount == 0) {
          msg = 'Data terpilih belum memiliki Hasil GC.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.orange),
        );
      }
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Bulk GC: ${validRecords.length} Data Siap'),
          content: SingleChildScrollView(
            child: ListBody(
              children: [
                Text(
                  'Akan mengirim ${validRecords.length} data menggunakan hasil GC yang tersimpan di masing-masing record.',
                ),
                if (skippedCount > 0 || skippedUploadedCount > 0)
                  const SizedBox(height: 12),
                if (skippedUploadedCount > 0)
                  Text(
                    '$skippedUploadedCount data dilewati karena SUDAH terupload.',
                    style: const TextStyle(color: Colors.blue, fontSize: 12),
                  ),
                if (skippedCount > 0)
                  Text(
                    '$skippedCount data dilewati karena BELUM memiliki Hasil GC.',
                    style: const TextStyle(color: Colors.orange, fontSize: 12),
                  ),
                const SizedBox(height: 12),
                const Text('Lanjutkan?'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Kirim'),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      // Pastikan konfigurasi/kredensial siap
      final ok = await _ensureGcConfig();
      if (!ok) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Login BPS diperlukan untuk mengirim data.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      int successCount = 0;
      int itemsSentWithCurrentAccount = 0; // Counter untuk rotasi akun otomatis
      final total = validRecords.length;
      final random = Random();

      // Setup Progress Dialog Variables
      final progressNotifier = ValueNotifier<int>(0);
      final statusNotifier = ValueNotifier<String>('Menyiapkan...');
      final successNotifier = ValueNotifier<int>(0);
      final failNotifier = ValueNotifier<int>(0);
      final pendingUiNotifier = ValueNotifier<int>(
        total,
      ); // Data yang belum disentuh
      final isFinishedNotifier = ValueNotifier<bool>(false);
      final isCancelledNotifier = ValueNotifier<bool>(false);

      // Assign to class variables for "Resume" capability
      _activeProgressNotifier = progressNotifier;
      _activeStatusNotifier = statusNotifier;
      _activeSuccessNotifier = successNotifier;
      _activeFailNotifier = failNotifier;
      _activePendingUiNotifier = pendingUiNotifier;
      _activeIsFinishedNotifier = isFinishedNotifier;
      _activeIsCancelledNotifier = isCancelledNotifier;
      _activeTotalUploadCount = total;
      _isUploadHidden = false;

      if (mounted) {
        _showUploadProgressDialog();
      }

      List<GroundcheckRecord> pendingRecords = List.from(validRecords);
      int maxRetries = 1;

      for (int attempt = 1; attempt <= maxRetries; attempt++) {
        if (isCancelledNotifier.value) break;
        if (pendingRecords.isEmpty) break;

        final currentBatch = List<GroundcheckRecord>.from(pendingRecords);
        pendingRecords
            .clear(); // Kosongkan untuk menampung yang gagal di attempt ini

        for (int i = 0; i < currentBatch.length; i++) {
          if (isCancelledNotifier.value) break;
          final record = currentBatch[i];

          // Update status & counter sebelum proses
          statusNotifier.value =
              'Percobaan $attempt/$maxRetries\nMengirim ${record.idsbr}...';

          if (attempt == 1) {
            // Jika attempt 1, ambil dari stok 'Belum'
            if (pendingUiNotifier.value > 0) pendingUiNotifier.value--;
          } else {
            // Jika retry, ambil dari stok 'Gagal' (karena sedang diproses ulang)
            if (failNotifier.value > 0) failNotifier.value--;
          }

          bool isSuccess = false;
          try {
            // Logika baru: Validasi koordinat, kirim null/empty jika invalid (sesuai request user)
            // Referensi: gc_koprol.py (yang strict untuk hasilgc=1), tapi user minta "jadikan null saja"

            String latToSend = '';
            String lonToSend = '';

            final lat = double.tryParse(record.latitude);
            final lon = double.tryParse(record.longitude);

            if (lat != null && lon != null) {
              latToSend = record.latitude;
              lonToSend = record.longitude;
            } else {
              // Jika invalid/kosong, kirim string kosong (server mungkin terima sebagai null)
              latToSend = '';
              lonToSend = '';
            }

            final resp = await _gcService
                .konfirmasiUser(
                  perusahaanId: record.perusahaanId,
                  latitude: latToSend,
                  longitude: lonToSend,
                  hasilGc: record.gcsResult,
                )
                .timeout(const Duration(seconds: 30));

            if (resp != null) {
              // Handle Rate Limit (429)
              if (resp.containsKey('retry_after')) {
                final retryVal = resp['retry_after'];
                int waitSeconds = 20; // Default fallback
                if (retryVal is int) {
                  waitSeconds = retryVal;
                } else if (retryVal is String) {
                  waitSeconds = int.tryParse(retryVal) ?? 20;
                }

                // Parse message for explicit wait time (e.g. "tunggu 10 menit")
                final msg = resp['message']?.toString().toLowerCase() ?? '';
                try {
                  // Cek pola "X menit"
                  final minuteRegex = RegExp(r'(\d+)\s*menit');
                  final minuteMatch = minuteRegex.firstMatch(msg);
                  if (minuteMatch != null) {
                    final minutes =
                        int.tryParse(minuteMatch.group(1) ?? '') ?? 0;
                    if (minutes > 0) {
                      final secondsFromMsg = minutes * 60;
                      if (secondsFromMsg > waitSeconds) {
                        waitSeconds = secondsFromMsg;
                      }
                    }
                  }

                  // Cek pola "X detik"
                  final secondRegex = RegExp(r'(\d+)\s*detik');
                  final secondMatch = secondRegex.firstMatch(msg);
                  if (secondMatch != null) {
                    final seconds =
                        int.tryParse(secondMatch.group(1) ?? '') ?? 0;
                    if (seconds > waitSeconds) {
                      waitSeconds = seconds;
                    }
                  }
                } catch (_) {
                  // Ignore regex parsing errors
                }

                // Safety minimum wait
                if (waitSeconds < 1) waitSeconds = 5;

                // --- AUTO SWITCH ACCOUNT LOGIC ---
                if (AccountManagerService().accounts.isNotEmpty) {
                  // 1. Tandai akun saat ini terkena limit
                  if (_currentLoginId != null) {
                    AccountManagerService().markAccountRateLimited(
                      _currentLoginId!,
                      Duration(seconds: waitSeconds),
                    );
                  }

                  // 2. Cek apakah ada akun tersedia
                  if (AccountManagerService().isAllAccountsRateLimited) {
                    statusNotifier.value =
                        'Semua akun limit. Menghentikan proses...';
                    await Future.delayed(const Duration(seconds: 2));
                    throw 'Semua akun sedang dalam masa tunggu (limit). Silakan coba lagi nanti.';
                  }

                  // 3. Cari akun berikutnya
                  final nextAccount = AccountManagerService()
                      .getNextAvailableAccount(_currentLoginId);

                  if (nextAccount != null) {
                    statusNotifier.value =
                        'Akun limit (${waitSeconds}d). Ganti ke ${nextAccount.username}...';
                    await Future.delayed(const Duration(seconds: 1));

                    try {
                      // 1. Logout explicit
                      statusNotifier.value = 'Logout dari akun lama...';
                      await _gcService.logout();

                      // Clear local storage
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.remove('gc_token');
                      await prefs.remove('gc_cookie');
                      await prefs.remove('current_login_id');

                      // 2. Login new account
                      statusNotifier.value =
                          'Login ke akun ${nextAccount.username}...';
                      final loginResult = await _gcService.automatedLogin(
                        username: nextAccount.username,
                        password: nextAccount.password,
                      );

                      if (loginResult['status'] == 'success') {
                        itemsSentWithCurrentAccount = 0; // Reset counter rotasi
                        statusNotifier.value =
                            'Ganti akun berhasil: ${loginResult['userName']}';

                        // Update UI state local & Save Prefs
                        if (mounted) {
                          setState(() {
                            _currentUser = loginResult['userName'];
                            _currentLoginId = loginResult['loginId'];
                            _gcToken = loginResult['gcToken'];
                            _csrfToken = loginResult['csrfToken'];
                          });

                          // Save new credentials
                          if (_gcToken != null)
                            await prefs.setString('gc_token', _gcToken!);
                          if (_gcService.cookieHeader != null) {
                            await prefs.setString(
                              'gc_cookie',
                              _gcService.cookieHeader!,
                            );
                          }
                          if (_currentLoginId != null) {
                            await prefs.setString(
                              'current_login_id',
                              _currentLoginId!,
                            );
                          }
                        }

                        await Future.delayed(const Duration(seconds: 2));

                        // Retry immediately
                        i--;
                        continue;
                      } else {
                        statusNotifier.value =
                            'Ganti akun gagal: ${loginResult['message']}. Menunggu...';
                        await Future.delayed(const Duration(seconds: 2));
                      }
                    } catch (e) {
                      debugPrint('Error switching account: $e');
                    }
                  } else {
                    // Fallback jika tidak ada next account tapi belum semua limit
                    statusNotifier.value =
                        'Menunggu durasi limit (${waitSeconds}d)...';
                    await Future.delayed(Duration(seconds: waitSeconds));
                  }
                }
                // ---------------------------------

                // Tampilkan countdown
                for (int t = waitSeconds; t > 0; t--) {
                  if (isCancelledNotifier.value) break;
                  statusNotifier.value =
                      'Terlalu banyak permintaan.\nMenunggu ${t}s sebelum lanjut...';
                  await Future.delayed(const Duration(seconds: 1));
                }

                if (isCancelledNotifier.value) break;

                // Ulangi item ini (decrement index agar loop memproses index ini lagi)
                i--;
                continue;
              }

              final status = resp['status']?.toString().toLowerCase();
              final msg = resp['message']?.toString().toLowerCase() ?? '';
              if (status == 'success' ||
                  msg.contains('berhasil') ||
                  msg.contains('success')) {
                isSuccess = true;
              } else if (status == 'error' &&
                  msg.contains('sudah diground check')) {
                final data = resp['data'];
                if (data is Map) {
                  final serverResult = data['status_hasil_gc']?.toString();
                  if (serverResult != null && serverResult.isNotEmpty) {
                    await _applyGcInput(
                      record,
                      serverResult,
                      lat,
                      lon,
                      isUploaded: true,
                      allowCancel: false,
                    );
                    isSuccess = true;
                  }
                }
              }
            }

            if (isSuccess) {
              await _applyGcInput(
                record,
                record.gcsResult,
                lat,
                lon,
                isUploaded: true,
              );
              successCount++;
              successNotifier.value = successCount;
              progressNotifier.value = successCount;

              // --- PROACTIVE ROTATION LOGIC (Every 30 items) ---
              itemsSentWithCurrentAccount++;
              // Hanya rotasi jika ada lebih dari 1 akun tersedia
              if (itemsSentWithCurrentAccount >= 12289 &&
                  AccountManagerService().accounts.length > 1) {
                final nextAccount = AccountManagerService()
                    .getNextAvailableAccount(_currentLoginId);

                if (nextAccount != null) {
                  statusNotifier.value =
                      'Rotasi akun rutin (30 data). Ganti ke ${nextAccount.username}...';
                  await Future.delayed(const Duration(seconds: 1));

                  try {
                    statusNotifier.value = 'Logout dari akun lama...';
                    await _gcService.logout();

                    final prefs = await SharedPreferences.getInstance();
                    await prefs.remove('gc_token');
                    await prefs.remove('gc_cookie');
                    await prefs.remove('current_login_id');

                    statusNotifier.value =
                        'Login ke akun ${nextAccount.username}...';
                    final loginResult = await _gcService.automatedLogin(
                      username: nextAccount.username,
                      password: nextAccount.password,
                    );

                    if (loginResult['status'] == 'success') {
                      itemsSentWithCurrentAccount = 0; // Reset counter
                      if (mounted) {
                        setState(() {
                          _currentUser = loginResult['userName'];
                          _currentLoginId = loginResult['loginId'];
                          _gcToken = loginResult['gcToken'];
                          _csrfToken = loginResult['csrfToken'];
                        });

                        if (_gcToken != null)
                          await prefs.setString('gc_token', _gcToken!);
                        if (_gcService.cookieHeader != null) {
                          await prefs.setString(
                            'gc_cookie',
                            _gcService.cookieHeader!,
                          );
                        }
                        if (_currentLoginId != null) {
                          await prefs.setString(
                            'current_login_id',
                            _currentLoginId!,
                          );
                        }
                      }
                      statusNotifier.value =
                          'Rotasi berhasil: ${_currentUser}. Lanjut proses...';
                    } else {
                      statusNotifier.value =
                          'Rotasi gagal: ${loginResult['message']}. Lanjut akun lama...';
                    }
                  } catch (e) {
                    debugPrint('Error rotating account: $e');
                  }
                }
              }
            } else {
              debugPrint('Bulk GC Gagal untuk ${record.idsbr}: $resp');
              pendingRecords.add(
                record,
              ); // Masukkan kembali ke antrean untuk retry berikutnya
              failNotifier.value++; // Tambah counter gagal
            }
          } catch (e) {
            if (e is TimeoutException) {
              debugPrint('Bulk GC Timeout (15s) untuk ${record.idsbr}');
            } else {
              debugPrint('Bulk GC Exception untuk ${record.idsbr}: $e');
            }
            pendingRecords.add(record); // Masukkan kembali ke antrean
            failNotifier.value++; // Tambah counter gagal
          }

          // Jeda 10 detik antar record (Wajib untuk semua item)
          for (int t = 1; t > 0; t--) {
            if (isCancelledNotifier.value) break;
            statusNotifier.value =
                'Cooldown ${t}s sebelum proses berikutnya...';
            await Future.delayed(const Duration(seconds: 1));
          }
        }

        if (isCancelledNotifier.value) break;

        // Setelah batch selesai, cek apakah perlu retry
        if (pendingRecords.isNotEmpty && attempt < maxRetries) {
          // Jeda antar attempt (agak lama agar natural)
          // Misal 5 detik
          for (int t = 5; t > 0; t--) {
            if (isCancelledNotifier.value) break;
            statusNotifier.value =
                'Menunggu ${t}s sebelum mencoba ulang ${pendingRecords.length} data gagal...';
            await Future.delayed(const Duration(seconds: 1));
          }
        }
      }

      if (isCancelledNotifier.value) {
        statusNotifier.value = 'Proses Dibatalkan.';
      } else {
        statusNotifier.value = 'Selesai! Silakan tutup dialog.';
      }

      progressNotifier.value =
          total; // Penuhi bar di akhir (meski ada yang gagal, proses selesai)

      // Update status akhir
      isFinishedNotifier.value = true;

      _dataGridController.selectedRows = [];
      setState(() {});

      if (_isUploadHidden && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Bulk GC Selesai. Sukses: $successCount, Gagal: ${failNotifier.value}',
            ),
          ),
        );
      }
    }
  }

  Widget _buildFilterBar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                decoration: InputDecoration(
                  labelText: 'Cari',
                  hintText: 'Cari ID, nama usaha, alamat, kode wilayah',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  isDense: true,
                ),
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value.trim();
                  });
                  _refreshFilteredData();
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: _refreshLocalData,
              icon: const Icon(Icons.sync),
              tooltip: 'Sinkronkan Data Lokal',
            ),
            const SizedBox(width: 8),
            if (_isLoadingParepare)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            if (!_isLoadingParepare) ...[
              IconButton(
                onPressed: () async {
                  if (_parepareComparison.isEmpty) {
                    await _loadParepareComparison();
                  }
                  setState(() {
                    _showParepareDiff = !_showParepareDiff;
                  });
                  _refreshFilteredData();
                },
                icon: Icon(
                  _showParepareDiff
                      ? Icons.difference_rounded
                      : Icons.compare_arrows,
                  color: _showParepareDiff ? Colors.purple : null,
                ),
                tooltip: _showParepareDiff
                    ? 'Tampilkan Semua Data'
                    : 'Bandingkan dengan Excel Parepare (Cari Perbedaan)',
              ),
              IconButton(
                onPressed: _syncGcUsernameFromParepareJson,
                icon: const Icon(Icons.person_add_alt_1),
                tooltip: 'Lengkapi GC Username dari JSON',
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _statusFilter ?? '',
                decoration: const InputDecoration(
                  labelText: 'Status Perusahaan',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<String>(
                    value: '',
                    child: Text('Semua Status'),
                  ),
                  ..._statusOptions.map(
                    (s) => DropdownMenuItem<String>(value: s, child: Text(s)),
                  ),
                ],
                onChanged: (value) {
                  setState(() {
                    _statusFilter = value != null && value.isNotEmpty
                        ? value
                        : null;
                  });
                  _refreshFilteredData();
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _gcsFilter ?? '',
                decoration: const InputDecoration(
                  labelText: 'GCS Result',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<String>(
                    value: '',
                    child: Text('Semua GCS'),
                  ),
                  const DropdownMenuItem<String>(
                    value: 'NULL',
                    child: Text('Belum GC'),
                  ),
                  ..._gcsOptions.map(
                    (s) => DropdownMenuItem<String>(value: s, child: Text(s)),
                  ),
                ],
                onChanged: (value) {
                  setState(() {
                    _gcsFilter = value != null && value.isNotEmpty
                        ? value
                        : null;
                  });
                  _refreshFilteredData();
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String?>(
                value: _sumberDataFilter,
                decoration: const InputDecoration(
                  labelText: 'Sumber Data',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Semua Sumber'),
                  ),
                  const DropdownMenuItem<String?>(
                    value: '',
                    child: Text('Tidak Ada Sumber'),
                  ),
                  ..._sumberDataOptions.map(
                    (s) => DropdownMenuItem<String?>(value: s, child: Text(s)),
                  ),
                ],
                onChanged: (value) {
                  setState(() {
                    _sumberDataFilter = value;
                  });
                  _refreshFilteredData();
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String?>(
                value: _isUploadedFilter,
                decoration: const InputDecoration(
                  labelText: 'Status Upload',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem<String?>(value: null, child: Text('Semua')),
                  DropdownMenuItem<String?>(
                    value: 'uploaded',
                    child: Text('Sudah Upload'),
                  ),
                  DropdownMenuItem<String?>(
                    value: 'not_uploaded',
                    child: Text('Belum Upload'),
                  ),
                  DropdownMenuItem<String?>(
                    value: 'revisi',
                    child: Text('Perlu Revisi'),
                  ),
                ],
                onChanged: (value) {
                  setState(() {
                    _isUploadedFilter = value;
                  });
                  _refreshFilteredData();
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String?>(
                value: _petugasFilter,
                decoration: const InputDecoration(
                  labelText: 'Petugas',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Semua Petugas'),
                  ),
                  const DropdownMenuItem<String?>(
                    value: '',
                    child: Text('Belum Ada Petugas'),
                  ),
                  ..._petugasOptions.map(
                    (p) => DropdownMenuItem<String?>(value: p, child: Text(p)),
                  ),
                ],
                onChanged: (value) {
                  setState(() {
                    _petugasFilter = value;
                  });
                  _refreshFilteredData();
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String?>(
                value: _regionFilter,
                decoration: const InputDecoration(
                  labelText: 'Wilayah',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Semua Wilayah'),
                  ),
                  ..._regionOptions.map(
                    (r) => DropdownMenuItem<String?>(
                      value: r,
                      child: Text(r, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
                onChanged: _isSpatialLoading
                    ? null
                    : (value) {
                        setState(() {
                          _regionFilter = value;
                        });
                        _refreshFilteredData();
                      },
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Builder(
          builder: (context) {
            final total = _allRecords.length;
            final shown = _filteredRecords().length;
            return Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue[100]!),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.list_alt, color: Colors.blue),
                        const SizedBox(width: 8),
                        Text(
                          'Jumlah data groundcheck: $total | Ditampilkan: $shown',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value, {bool isGood = true}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 12,
                color: isGood ? Colors.black87 : Colors.red,
              ),
            ),
          ),
          Icon(
            isGood ? Icons.check_circle_outline : Icons.error_outline,
            size: 16,
            color: isGood ? Colors.green : Colors.red,
          ),
        ],
      ),
    );
  }

  void _showUploadProgressDialog() {
    if (_activeProgressNotifier == null) return;

    // Reset hidden flag because we are showing it now
    _isUploadHidden = false;

    setState(() {
      _isDialogShowing = true;
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return WillPopScope(
          onWillPop: () async => false,
          child: AlertDialog(
            title: ValueListenableBuilder<bool>(
              valueListenable: _activeIsFinishedNotifier!,
              builder: (context, isFinished, child) {
                return Text(
                  isFinished ? 'Selesai Mengirim Data' : 'Mengirim Data',
                );
              },
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ValueListenableBuilder<int>(
                  valueListenable: _activeProgressNotifier!,
                  builder: (context, val, child) {
                    return LinearProgressIndicator(
                      value: _activeTotalUploadCount > 0
                          ? val / _activeTotalUploadCount
                          : 0,
                      backgroundColor: Colors.grey[200],
                    );
                  },
                ),
                const SizedBox(height: 16),
                ValueListenableBuilder<String>(
                  valueListenable: _activeStatusNotifier!,
                  builder: (context, val, child) {
                    return Text(
                      val,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    );
                  },
                ),
                const SizedBox(height: 8),
                ValueListenableBuilder<int>(
                  valueListenable: _activeProgressNotifier!,
                  builder: (context, val, child) {
                    return Text(
                      '$val dari $_activeTotalUploadCount data sukses',
                      style: const TextStyle(color: Colors.grey),
                    );
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Kolom Sukses
                    ValueListenableBuilder<int>(
                      valueListenable: _activeSuccessNotifier!,
                      builder: (context, val, child) {
                        return Column(
                          children: [
                            const Text(
                              'Sukses',
                              style: TextStyle(color: Colors.green),
                            ),
                            Text(
                              '$val',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    // Kolom Gagal
                    ValueListenableBuilder<int>(
                      valueListenable: _activeFailNotifier!,
                      builder: (context, val, child) {
                        return Column(
                          children: [
                            const Text(
                              'Gagal',
                              style: TextStyle(color: Colors.red),
                            ),
                            Text(
                              '$val',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    // Kolom Belum
                    ValueListenableBuilder<int>(
                      valueListenable: _activePendingUiNotifier!,
                      builder: (context, val, child) {
                        return Column(
                          children: [
                            const Text(
                              'Belum',
                              style: TextStyle(color: Colors.grey),
                            ),
                            Text(
                              '$val',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              ValueListenableBuilder<bool>(
                valueListenable: _activeIsFinishedNotifier!,
                builder: (context, isFinished, child) {
                  if (!isFinished) {
                    return TextButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        setState(() {
                          _isUploadHidden = true;
                          _isDialogShowing = false;
                        });
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Pengiriman berjalan di latar belakang...',
                              ),
                            ),
                          );
                        }
                      },
                      child: const Text('Sembunyikan'),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
              ValueListenableBuilder<bool>(
                valueListenable: _activeIsFinishedNotifier!,
                builder: (context, isFinished, child) {
                  if (!isFinished) {
                    return TextButton(
                      onPressed: () {
                        _activeIsCancelledNotifier!.value = true;
                      },
                      child: const Text(
                        'Batal',
                        style: TextStyle(color: Colors.red),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
              ValueListenableBuilder<bool>(
                valueListenable: _activeIsFinishedNotifier!,
                builder: (context, isFinished, child) {
                  if (isFinished) {
                    return TextButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        setState(() {
                          _isDialogShowing = false;
                          _isUploadHidden = false;
                          // Clear active state
                          _activeProgressNotifier = null;
                        });
                      },
                      child: const Text('Tutup'),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _handleSidrapPaste() async {
    showDialog(
      context: context,
      builder: (ctx) => _SidrapManagerDialog(
        gcService: _gcService,
        onProcessAll: (data) {
          Navigator.pop(ctx);
          _processSidrapQueue(data);
        },
        gcToken: _gcToken,
        gcCookie: _gcCookie,
        userAgent: _userAgent,
        csrfToken: _csrfToken,
      ),
    );
  }

  Future<void> _processSidrapQueue(List<Map<String, String>> queue) async {
    // Setup Notifiers untuk Progress Dialog
    _activeProgressNotifier = ValueNotifier<int>(0);
    _activeStatusNotifier = ValueNotifier<String>('');
    _activeSuccessNotifier = ValueNotifier<int>(0);
    _activeFailNotifier = ValueNotifier<int>(0);
    _activePendingUiNotifier = ValueNotifier<int>(queue.length);
    _activeIsFinishedNotifier = ValueNotifier<bool>(false);
    _activeIsCancelledNotifier = ValueNotifier<bool>(false);
    _activeTotalUploadCount = queue.length;

    // Pastikan session service up-to-date
    if (_gcCookie != null && _userAgent != null) {
      _gcService.setCredentials(
        cookie: _gcCookie!,
        csrfToken: _csrfToken ?? '',
        gcToken: _gcToken ?? '',
        userAgent: _userAgent!,
      );
    }

    // Tampilkan Dialog
    _showUploadProgressDialog();

    final total = queue.length;
    int successCount = 0;
    int failCount = 0;

    for (var i = 0; i < total; i++) {
      // Cek pembatalan
      if (_activeIsCancelledNotifier!.value) {
        break;
      }

      final item = queue[i];
      final namaUsaha = item['nama_usaha'] ?? '';
      final rawKode = item['kode_wilayah'] ?? '';

      // Update UI
      _activeStatusNotifier!.value = 'Mengirim: $namaUsaha';
      _activeProgressNotifier!.value =
          i; // Progress indicator expects processed count? Wait.
      // Looking at _showUploadProgressDialog: val / _activeTotalUploadCount
      // So if I process 1, val should be 1.
      // I'll update it at the end of loop iteration.

      try {
        // Konversi Kode Wilayah (Format: 7314060007)
        // 73 = Prov, 14 = Kab, 060 = Kec (index 4-7), 007 = Desa (index 7-10)
        if (rawKode.length < 10) throw 'Kode wilayah tidak valid';

        final kecCode = rawKode.substring(4, 7);
        final desaCode = rawKode.substring(7, 10);

        final serverKecId = WilayahMappingSidrap.getKecamatanId(kecCode);
        final serverDesaId = WilayahMappingSidrap.getDesaId(kecCode, desaCode);

        // Kirim ke Server
        final result = await _gcService.saveDraftTambahUsaha(
          namaUsaha: namaUsaha,
          alamat: item['alamat'] ?? '',
          provinsiId: WilayahMappingSidrap.serverProvinsiId,
          kabupatenId: WilayahMappingSidrap.serverKabupatenId,
          kecamatanId: serverKecId,
          desaId: serverDesaId,
          latitude: item['latitude'] ?? '0',
          longitude: item['longitude'] ?? '0',
        );

        if (result != null && result['success'] == true) {
          successCount++;
          _activeSuccessNotifier!.value = successCount;
        } else {
          failCount++;
          _activeFailNotifier!.value = failCount;
          debugPrint('Gagal Sidrap: ${result?['message'] ?? 'Unknown error'}');
        }
      } catch (e) {
        failCount++;
        _activeFailNotifier!.value = failCount;
        debugPrint('Error Sidrap: $e');
      }

      _activePendingUiNotifier!.value = total - (i + 1);
      _activeProgressNotifier!.value = i + 1;

      // Delay rate limit sederhana
      await Future.delayed(const Duration(milliseconds: 500));
    }

    // Selesai
    _activeProgressNotifier!.value = total;
    _activeStatusNotifier!.value = 'Selesai';
    _activeIsFinishedNotifier!.value = true;
    _loadData(); // Reload map
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<MapBloc, MapState>(
      listenWhen: (previous, current) =>
          previous.status != current.status &&
          current.status == MapStatus.success,
      listener: (context, state) {
        // Hanya reload jika data lokal masih kosong dan peta sukses memuat data
        // Ini mencegah reload berulang saat geser peta (perubahan bounds)
        if (state.status == MapStatus.success && _allRecords.isEmpty) {
          _loadData();
        }
      },
      child: Scaffold(
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
        floatingActionButton: _dataGridController.selectedRows.isNotEmpty
            ? Builder(
                builder: (context) {
                  // Cek kondisi tombol
                  bool showCancel = false;
                  bool showDeleteNew = false;
                  bool showKirimGc = false;
                  bool showTambahUsaha = false;
                  int countKirimGc = 0;
                  int countTambahUsaha = 0;

                  if (_dataSource != null) {
                    for (final row in _dataGridController.selectedRows) {
                      final r = _dataSource!.getRecord(row);
                      if (r != null) {
                        if (!showCancel &&
                            (r.isRevisi || r.isUploaded) &&
                            r.allowCancel) {
                          showCancel = true;
                        }
                        if (!showDeleteNew &&
                            r.idsbr.toUpperCase().startsWith('TEMP-')) {
                          showDeleteNew = true;
                        }

                        // Logic tombol Kirim GC vs Tambah Usaha
                        if (!r.isUploaded) {
                          if (r.gcsResult == '5') {
                            showTambahUsaha = true;
                            countTambahUsaha++;
                          } else if (r.gcsResult.isNotEmpty) {
                            showKirimGc = true;
                            countKirimGc++;
                          }
                        }
                      }
                    }
                  }

                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FloatingActionButton.extended(
                        heroTag: 'fab_deselect',
                        onPressed: () {
                          setState(() {
                            _dataGridController.selectedRows = [];
                          });
                        },
                        icon: const Icon(Icons.close),
                        label: const Text('Batal Pilih'),
                        backgroundColor: Colors.grey,
                      ),
                      const SizedBox(width: 16),
                      FloatingActionButton.extended(
                        heroTag: 'fab_add_address',
                        onPressed: _handleBulkTambahAlamat,
                        icon: const Icon(Icons.place),
                        label: const Text('Tambah Alamat'),
                        backgroundColor: Colors.indigo,
                      ),
                      const SizedBox(width: 16),
                      FloatingActionButton.extended(
                        heroTag: 'fab_geocode',
                        onPressed: _handleBulkGeocoding,
                        icon: const Icon(Icons.map),
                        label: const Text('Geocoding'),
                        backgroundColor: Colors.teal,
                      ),
                      const SizedBox(width: 16),
                      FloatingActionButton.extended(
                        heroTag: 'fab_lapor',
                        onPressed: _handleBulkLapor,
                        icon: const Icon(Icons.report),
                        label: const Text('Lapor'),
                        backgroundColor: Colors.redAccent,
                      ),
                      const SizedBox(width: 16),
                      if (!showCancel) ...[
                        FloatingActionButton.extended(
                          heroTag: 'fab_edit',
                          onPressed: _handleBulkEditStatus,
                          icon: const Icon(Icons.edit),
                          label: const Text('Ubah Status'),
                          backgroundColor: Colors.orange,
                        ),
                        const SizedBox(width: 16),
                        if (showKirimGc) ...[
                          FloatingActionButton.extended(
                            heroTag: 'fab_send',
                            onPressed: _handleBulkGc,
                            icon: const Icon(Icons.send),
                            label: Text('Kirim GC ($countKirimGc)'),
                          ),
                          const SizedBox(width: 16),
                        ],
                        if (showTambahUsaha) ...[
                          FloatingActionButton.extended(
                            heroTag: 'fab_add_business',
                            onPressed: _handleBulkTambahUsaha,
                            icon: const Icon(
                              Icons.add_business,
                              color: Colors.white,
                            ),
                            label: Text(
                              'Tambah Usaha ($countTambahUsaha)',
                              style: const TextStyle(color: Colors.white),
                            ),
                            backgroundColor: Colors.black,
                          ),
                          const SizedBox(width: 16),
                        ],
                      ] else
                        FloatingActionButton.extended(
                          heroTag: 'fab_cancel',
                          onPressed: _handleBulkCancelGc,
                          icon: const Icon(Icons.cancel_schedule_send),
                          label: Text(
                            'Batalkan Kirim (${_dataGridController.selectedRows.length})',
                          ),
                          backgroundColor: Colors.red,
                        ),
                      if (showDeleteNew) ...[
                        FloatingActionButton.extended(
                          heroTag: 'fab_delete_new',
                          onPressed: _isDeletingNew
                              ? null
                              : _handleBulkDeleteNew,
                          icon: _isDeletingNew
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.delete_forever),
                          label: Text(_isDeletingNew ? '' : 'Hapus Baru'),
                          backgroundColor: Colors.red[900],
                        ),
                      ],
                      if (_isUploadHidden) ...[
                        const SizedBox(width: 16),
                        FloatingActionButton.extended(
                          heroTag: 'fab_resume_upload_selected',
                          onPressed: _showUploadProgressDialog,
                          icon: const Icon(Icons.upload_file),
                          label: const Text('Lihat Upload'),
                          backgroundColor: Colors.blue,
                        ),
                      ],
                    ],
                  );
                },
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FloatingActionButton.extended(
                    heroTag: 'fab_sidrap_paste',
                    onPressed: _handleSidrapPaste,
                    icon: const Icon(Icons.paste, color: Colors.white),
                    label: const Text(
                      'Sidrap Paste',
                      style: TextStyle(color: Colors.white),
                    ),
                    backgroundColor: Colors.indigo,
                  ),
                  if (_isUploadHidden) ...[
                    const SizedBox(width: 16),
                    FloatingActionButton.extended(
                      heroTag: 'fab_resume_upload',
                      onPressed: _showUploadProgressDialog,
                      icon: const Icon(Icons.upload_file),
                      label: const Text('Lihat Proses Upload'),
                      backgroundColor: Colors.blue,
                    ),
                  ],
                ],
              ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? Center(
                  child: Text(
                    'Gagal memuat data: $_error',
                    textAlign: TextAlign.center,
                  ),
                )
              : Column(
                  children: [
                    if (_currentUser != null)
                      Card(
                        color: Colors.green[50],
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.green.shade200),
                        ),
                        child: ExpansionTile(
                          tilePadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          leading: const CircleAvatar(
                            backgroundColor: Colors.green,
                            child: Icon(Icons.person, color: Colors.white),
                          ),
                          title: const Text(
                            'Login Berhasil',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Text(
                            _currentUser!,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Colors.black87,
                            ),
                          ),
                          children: [
                            Container(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              alignment: Alignment.centerLeft,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Divider(),
                                  const Text(
                                    'Detail Sesi (Siap untuk Konfirmasi)',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  _buildInfoRow(
                                    'GC Token',
                                    _gcToken != null && _gcToken!.length > 10
                                        ? '${_gcToken!.substring(0, 10)}...${_gcToken!.substring(_gcToken!.length - 5)}'
                                        : 'Tidak tersedia',
                                    isGood: _gcToken != null,
                                  ),
                                  _buildInfoRow(
                                    'Cookie',
                                    _gcCookie != null ? 'Tersedia' : 'Kosong',
                                    isGood: _gcCookie != null,
                                  ),
                                  _buildInfoRow(
                                    'Mode',
                                    _userAgent != null &&
                                            _userAgent!.contains('Android')
                                        ? 'Mobile (Android 16)'
                                        : 'Desktop / Default',
                                    isGood:
                                        _userAgent != null &&
                                        _userAgent!.contains('Android'),
                                  ),
                                  const SizedBox(height: 12),
                                  SizedBox(
                                    width: double.infinity,
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            onPressed: _handleRefreshSession,
                                            icon: const Icon(
                                              Icons.refresh,
                                              size: 18,
                                              color: Colors.blue,
                                            ),
                                            label: const Text(
                                              'Refresh',
                                              style: TextStyle(
                                                color: Colors.blue,
                                              ),
                                            ),
                                            style: OutlinedButton.styleFrom(
                                              side: const BorderSide(
                                                color: Colors.blue,
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 12,
                                                  ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            onPressed:
                                                _showAccountManagerDialog,
                                            icon: const Icon(
                                              Icons.manage_accounts,
                                              size: 18,
                                              color: Colors.green,
                                            ),
                                            label: const Text(
                                              'Akun',
                                              style: TextStyle(
                                                color: Colors.green,
                                              ),
                                            ),
                                            style: OutlinedButton.styleFrom(
                                              side: const BorderSide(
                                                color: Colors.green,
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 12,
                                                  ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            onPressed: _handleLogout,
                                            icon: const Icon(
                                              Icons.logout,
                                              size: 18,
                                              color: Colors.red,
                                            ),
                                            label: const Text(
                                              'Logout',
                                              style: TextStyle(
                                                color: Colors.red,
                                              ),
                                            ),
                                            style: OutlinedButton.styleFrom(
                                              side: const BorderSide(
                                                color: Colors.red,
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 12,
                                                  ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: ElevatedButton.icon(
                                onPressed: _showBpsLoginDialog,
                                icon: const Icon(Icons.login),
                                label: const Text('Login BPS'),
                                style: ElevatedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(48),
                                  backgroundColor: Colors.blue,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _showAccountManagerDialog,
                                icon: const Icon(Icons.manage_accounts),
                                label: const Text('Akun'),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(48),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    _buildFilterBar(),
                    const SizedBox(height: 12),
                    Expanded(
                      child: _allRecords.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.cloud_off,
                                    size: 64,
                                    color: Colors.grey,
                                  ),
                                  const SizedBox(height: 16),
                                  const Text(
                                    'Belum ada data Groundcheck tersimpan.',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Silakan download data untuk memulai.',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  ElevatedButton.icon(
                                    onPressed: () async {
                                      setState(() {
                                        _isLoading = true;
                                      });
                                      try {
                                        final records = await _supabaseService
                                            .syncRecords();
                                        if (mounted) {
                                          _processRecords(records);
                                        }
                                      } catch (e) {
                                        if (mounted) {
                                          setState(() {
                                            _isLoading = false;
                                            _error = e.toString();
                                          });
                                        }
                                      }
                                    },
                                    icon: const Icon(Icons.download),
                                    label: const Text('Download Data'),
                                  ),
                                ],
                              ),
                            )
                          : Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.grey.withValues(alpha: 0.1),
                                    spreadRadius: 1,
                                    blurRadius: 3,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: SfDataGrid(
                                  source: _dataSource!,
                                  controller: _dataGridController,
                                  selectionMode: SelectionMode.multiple,
                                  showCheckboxColumn: true,
                                  onSelectionChanged: (added, removed) =>
                                      setState(() {}),
                                  verticalScrollController: _scrollController,
                                  rowHeight: 56,
                                  headerGridLinesVisibility:
                                      GridLinesVisibility.horizontal,
                                  gridLinesVisibility:
                                      GridLinesVisibility.horizontal,
                                  columnWidthMode: ColumnWidthMode.fill,
                                  allowSorting: true,
                                  columns: [
                                    GridColumn(
                                      columnName: 'idsbr',
                                      label: Container(
                                        alignment: Alignment.centerLeft,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                        ),
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
                                      columnName: 'nama_usaha',
                                      label: Container(
                                        alignment: Alignment.centerLeft,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                        ),
                                        color: Colors.blue[50],
                                        child: const Text(
                                          'Nama Usaha',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            color: Colors.black87,
                                          ),
                                        ),
                                      ),
                                    ),
                                    GridColumn(
                                      columnName: 'alamat_usaha',
                                      label: Container(
                                        alignment: Alignment.centerLeft,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                        ),
                                        color: Colors.blue[50],
                                        child: const Text(
                                          'Alamat Usaha',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            color: Colors.black87,
                                          ),
                                        ),
                                      ),
                                    ),
                                    GridColumn(
                                      columnName: 'kode_wilayah',
                                      label: Container(
                                        alignment: Alignment.centerLeft,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                        ),
                                        color: Colors.blue[50],
                                        child: const Text(
                                          'Kode Wilayah',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            color: Colors.black87,
                                          ),
                                        ),
                                      ),
                                    ),
                                    GridColumn(
                                      columnName: 'gcs_result_excel',
                                      label: Container(
                                        alignment: Alignment.centerLeft,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                        ),
                                        color: Colors.blue[50],
                                        child: const Text(
                                          'GCS Excel',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            color: Colors.black87,
                                          ),
                                        ),
                                      ),
                                    ),
                                    GridColumn(
                                      columnName: 'sumber_data',
                                      label: Container(
                                        alignment: Alignment.centerLeft,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                        ),
                                        color: Colors.blue[50],
                                        child: const Text(
                                          'Sumber Data',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            color: Colors.black87,
                                          ),
                                        ),
                                      ),
                                    ),
                                    GridColumn(
                                      columnName: 'isUploaded',
                                      width: 80,
                                      label: Container(
                                        alignment: Alignment.center,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                        ),
                                        color: Colors.blue[50],
                                        child: const Text(
                                          'Up?',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            color: Colors.black87,
                                          ),
                                        ),
                                      ),
                                    ),
                                    GridColumn(
                                      columnName: 'gcs_result',
                                      label: Container(
                                        alignment: Alignment.centerLeft,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                        ),
                                        color: Colors.blue[50],
                                        child: const Text(
                                          'GCS Result',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            color: Colors.black87,
                                          ),
                                        ),
                                      ),
                                    ),
                                    GridColumn(
                                      columnName: 'gc_username',
                                      width: 120,
                                      label: Container(
                                        alignment: Alignment.centerLeft,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                        ),
                                        color: Colors.blue[50],
                                        child: const Text(
                                          'Petugas',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            color: Colors.black87,
                                          ),
                                        ),
                                      ),
                                    ),
                                    GridColumn(
                                      columnName: 'gc_action',
                                      width: 120,
                                      label: Container(
                                        alignment: Alignment.center,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                        ),
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
                  ],
                ),
        ),
      ),
    );
  }
}
