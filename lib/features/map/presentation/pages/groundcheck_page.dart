import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart' as dotenv;
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/services/bps_gc_service.dart';
import '../../data/services/gc_credentials_service.dart';
import '../../data/services/groundcheck_supabase_service.dart';
import '../bloc/map_bloc.dart';
import '../bloc/map_event.dart';
import '../../data/repositories/map_repository_impl.dart';

// Optional bootstrap via --dart-define (keamanan: tidak commit rahasia ke repo)
const String kInitialGcCookie = String.fromEnvironment(
  'GC_COOKIE',
  defaultValue: '',
);
const String kInitialGcToken = String.fromEnvironment(
  'GC_TOKEN',
  defaultValue: '',
);

class GroundcheckRecord {
  final String idsbr;
  final String namaUsaha;
  final String alamatUsaha;
  final String kodeWilayah;
  final String statusPerusahaan;
  final String skalaUsaha;
  final String gcsResult;
  final String latitude;
  final String longitude;
  final String perusahaanId;
  final String? userId;

  GroundcheckRecord({
    required this.idsbr,
    required this.namaUsaha,
    required this.alamatUsaha,
    required this.kodeWilayah,
    required this.statusPerusahaan,
    required this.skalaUsaha,
    required this.gcsResult,
    required this.latitude,
    required this.longitude,
    required this.perusahaanId,
    this.userId,
  });

  factory GroundcheckRecord.fromJson(Map<String, dynamic> json) {
    final lat = (json['latitude'] ?? '').toString();
    final lon = (json['longitude'] ?? '').toString();
    final perusahaan = (json['perusahaan_id'] ?? json['idsbr'] ?? '')
        .toString();
    return GroundcheckRecord(
      idsbr: (json['idsbr'] ?? '').toString(),
      namaUsaha: (json['nama_usaha'] ?? '').toString(),
      alamatUsaha: (json['alamat_usaha'] ?? '').toString(),
      kodeWilayah: (json['kode_wilayah'] ?? '').toString(),
      statusPerusahaan: (json['status_perusahaan'] ?? '').toString(),
      skalaUsaha: (json['skala_usaha'] ?? '').toString(),
      gcsResult: (json['gcs_result'] ?? '').toString(),
      latitude: lat,
      longitude: lon,
      perusahaanId: perusahaan,
      userId: json['user_id']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'idsbr': idsbr,
      'nama_usaha': namaUsaha,
      'alamat_usaha': alamatUsaha,
      'kode_wilayah': kodeWilayah,
      'status_perusahaan': statusPerusahaan,
      'skala_usaha': skalaUsaha,
      'gcs_result': gcsResult,
      'latitude': latitude,
      'longitude': longitude,
      'perusahaan_id': perusahaanId,
      'user_id': userId,
    };
  }
}

class GroundcheckDataSource extends DataGridSource {
  late List<DataGridRow> _rows;
  final Map<DataGridRow, GroundcheckRecord> _rowToRecord = {};
  final void Function(GroundcheckRecord record)? onGcPressed;
  final void Function(GroundcheckRecord record)? onGoToMap;

  GroundcheckDataSource({
    required List<GroundcheckRecord> data,
    this.onGcPressed,
    this.onGoToMap,
  }) {
    _buildRows(data);
  }

  @override
  List<DataGridRow> get rows => _rows;

  @override
  DataGridRowAdapter buildRow(DataGridRow row) {
    final record = _rowToRecord[row];
    return DataGridRowAdapter(
      cells: row.getCells().map((cell) {
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
          } else if (lower == '0' || lower.contains('tidak ditemukan')) {
            code = '0';
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
          } else {
            label = raw;
            base = Colors.blueGrey;
          }
          return Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Chip(
              label: Text(
                code.isNotEmpty ? '$code. $label' : label,
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
        if (cell.columnName == 'status_perusahaan') {
          final raw = (cell.value ?? '').toString().trim();
          final lower = raw.toLowerCase();
          final codeMatch = RegExp(r'^\s*(\d+)').firstMatch(raw);
          int? code = codeMatch != null
              ? int.tryParse(codeMatch.group(1)!)
              : null;
          String label = raw.isEmpty ? 'Tidak diketahui' : raw;
          final Map<int, String> statusMap = {
            1: 'Aktif',
            2: 'Tutup Sementara',
            3: 'Belum Beroperasi/Berproduksi',
            4: 'Tutup',
            5: 'Alih Usaha',
            6: 'Tidak Ditemukan',
            7: 'Aktif Pindah',
            8: 'Aktif Nonrespon',
            9: 'Duplikat',
            10: 'Salah Kode Wilayah',
          };
          MaterialColor base = Colors.grey;
          if (code != null && statusMap.containsKey(code)) {
            label = '${code}. ${statusMap[code]}';
            switch (code) {
              case 1:
                base = Colors.green;
                break;
              case 2:
                base = Colors.amber;
                break;
              case 3:
                base = Colors.blue;
                break;
              case 4:
                base = Colors.red;
                break;
              case 5:
                base = Colors.deepPurple;
                break;
              case 6:
                base = Colors.red;
                break;
              case 7:
                base = Colors.teal;
                break;
              case 8:
                base = Colors.orange;
                break;
              case 9:
                base = Colors.orange;
                break;
              case 10:
                base = Colors.brown;
                break;
              default:
                base = Colors.grey;
            }
          } else {
            if (lower.contains('aktif non')) {
              base = Colors.orange;
              label = '8. Aktif Nonrespon';
            } else if (lower.contains('aktif pindah')) {
              base = Colors.teal;
              label = '7. Aktif Pindah';
            } else if (lower.contains('alih usaha')) {
              base = Colors.deepPurple;
              label = '5. Alih Usaha';
            } else if (lower.contains('tutup sementara')) {
              base = Colors.amber;
              label = '2. Tutup Sementara';
            } else if (lower.contains('belum beroperasi') ||
                lower.contains('belum berproduksi')) {
              base = Colors.blue;
              label = '3. Belum Beroperasi/Berproduksi';
            } else if (lower.contains('tutup')) {
              base = Colors.red;
              label = '4. Tutup';
            } else if (lower.contains('tidak ditemukan')) {
              base = Colors.red;
              label = '6. Tidak Ditemukan';
            } else if (lower.contains('duplikat') || lower.contains('ganda')) {
              base = Colors.orange;
              label = '9. Duplikat';
            } else if (lower.contains('salah kode wilayah')) {
              base = Colors.brown;
              label = '10. Salah Kode Wilayah';
            } else if (lower.contains('aktif')) {
              base = Colors.green;
              label = 'Aktif';
            } else {
              base = Colors.grey;
            }
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
          DataGridCell<String>(
            columnName: 'status_perusahaan',
            value: e.statusPerusahaan,
          ),
          DataGridCell<String>(columnName: 'skala_usaha', value: e.skalaUsaha),
          DataGridCell<String>(columnName: 'gcs_result', value: e.gcsResult),
          DataGridCell<String>(columnName: 'latitude', value: e.latitude),
          DataGridCell<String>(columnName: 'longitude', value: e.longitude),
          DataGridCell<String>(columnName: 'gc_action', value: e.perusahaanId),
        ],
      );
      _rowToRecord[row] = e;
      return row;
    }).toList();
  }
}

class GroundcheckPage extends StatefulWidget {
  final void Function(GroundcheckRecord)? onGoToMap;

  const GroundcheckPage({super.key, this.onGoToMap});

  @override
  State<GroundcheckPage> createState() => _GroundcheckPageState();
}

class _GroundcheckPageState extends State<GroundcheckPage> {
  final ScrollController _scrollController = ScrollController();
  final BpsGcService _gcService = BpsGcService();
  final GcCredentialsService _gcCredsService = GcCredentialsService();
  final GroundcheckSupabaseService _supabaseService =
      GroundcheckSupabaseService();
  GroundcheckDataSource? _dataSource;
  List<GroundcheckRecord> _allRecords = [];
  List<String> _statusOptions = [];
  List<String> _gcsOptions = [];
  String _searchQuery = '';
  String? _statusFilter;
  String? _gcsFilter;
  bool _isLoading = true;
  bool _isConfirming = false;
  String? _error;
  String? _gcCookie;
  String? _gcToken;
  Timer? _keepAliveTimer;

  @override
  void initState() {
    super.initState();
    _loadStoredGcCredentials().then((_) {
      _loadData();
    });
  }

  Future<void> _loadData() async {
    setState(() {
      if (_allRecords.isEmpty) _isLoading = true;
      _error = null;
    });
    try {
      // 1. Load from local cache immediately
      final local = await _supabaseService.loadLocalRecords();
      if (local.isNotEmpty && mounted) {
        _processRecords(local);
      }

      // 2. Sync with server (fetch only updates)
      final records = await _supabaseService.syncRecords();
      if (mounted) {
        _processRecords(records);
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _processRecords(List<GroundcheckRecord> records) {
    _allRecords = records;
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

  Future<void> _reloadFromSupabase() async {
    await _loadData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Data dimuat ulang dari Supabase'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _keepAliveTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadStoredGcCredentials() async {
    try {
      // 1. Coba load dari Supabase Global
      final remote = await _gcCredsService.loadGlobal();
      if (remote != null) {
        final rc = remote['gc_cookie']?.trim() ?? '';
        final rt = remote['gc_token']?.trim() ?? '';
        if (rc.isNotEmpty) _gcCookie = rc;
        if (rt.isNotEmpty) _gcToken = rt;
      }

      // 2. Fallback .env
      if (_gcCookie == null || _gcCookie!.isEmpty) {
        final envCookie = dotenv.dotenv.env['GC_COOKIE'];
        if (envCookie?.trim().isNotEmpty ?? false) {
          _gcCookie = envCookie!.trim();
        }
      }
      if (_gcToken == null || _gcToken!.isEmpty) {
        final envToken = dotenv.dotenv.env['GC_TOKEN'];
        if (envToken?.trim().isNotEmpty ?? false) {
          _gcToken = envToken!.trim();
        }
      }

      // 3. Fallback dart-define
      if ((_gcCookie == null || _gcCookie!.isEmpty) &&
          kInitialGcCookie.isNotEmpty) {
        _gcCookie = kInitialGcCookie;
      }
      if ((_gcToken == null || _gcToken!.isEmpty) &&
          kInitialGcToken.isNotEmpty) {
        _gcToken = kInitialGcToken;
      }

      // 4. Default Placeholder (sesuai request user)
      if (_gcCookie == null || _gcCookie!.isEmpty) {
        _gcCookie = 'PASTE_COOKIE_HEADER';
      }
      if (_gcToken == null || _gcToken!.isEmpty) {
        _gcToken = 'PASTE_TOKEN';
      }

      // 5. Simpan/Sync kembali ke Supabase agar terisi (jika kosong di DB)
      // Upsert akan membuat row baru jika belum ada, atau update jika sudah ada
      await _gcCredsService.upsertGlobal(
        gcCookie: _gcCookie,
        gcToken: _gcToken,
      );

      // 6. Set ke Service
      if (_gcCookie != null && _gcCookie!.isNotEmpty) {
        _gcService.setCookiesFromHeader(_gcCookie!);
        await _gcService.autoGetCsrfToken();
        final updatedCookie = _gcService.cookieHeader;
        if (updatedCookie != null &&
            updatedCookie.isNotEmpty &&
            updatedCookie != _gcCookie) {
          _gcCookie = updatedCookie;
          await _saveStoredGcCredentials();
        }
        _keepAliveTimer?.cancel();
        _keepAliveTimer = Timer.periodic(const Duration(minutes: 10), (
          _,
        ) async {
          try {
            await _gcService.keepAlive();
            final refreshedCookie = _gcService.cookieHeader;
            if (refreshedCookie != null &&
                refreshedCookie.isNotEmpty &&
                refreshedCookie != _gcCookie) {
              _gcCookie = refreshedCookie;
              await _saveStoredGcCredentials();
            }
          } catch (_) {
            // Ignore keepAlive errors
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _saveStoredGcCredentials() async {
    try {
      await _gcCredsService.upsertGlobal(
        gcCookie: _gcCookie,
        gcToken: _gcToken,
      );
    } catch (_) {}
  }

  Future<void> _showGcInputDialog(GroundcheckRecord record) async {
    final hasilOptions = <Map<String, String>>[
      {'code': '', 'label': '-- Pilih --'},
      {'code': '0', 'label': '0. Tidak Ditemukan'},
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
                            case '0':
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
                      final laInput = double.tryParse(
                        latController.text.trim(),
                      );
                      final loInput = double.tryParse(
                        lonController.text.trim(),
                      );
                      if (selectedHasil.isEmpty) {
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
                      final ok = await _ensureGcConfig();
                      if (!ok) {
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
                        debugPrint(
                          'GC request => perusahaanId=${record.perusahaanId}, hasilGc=$selectedHasil, lat=${laFinal ?? '-'}, lon=${loFinal ?? '-'}',
                        );
                        final resp = await _gcService.konfirmasiUserWithRetry(
                          perusahaanId: record.perusahaanId,
                          latitude: laFinal != null ? laFinal.toString() : '',
                          longitude: loFinal != null ? loFinal.toString() : '',
                          hasilGc: selectedHasil,
                          gcToken: _gcToken ?? '',
                        );
                        if (resp == null || resp['status'] != 'success') {
                          if (resp != null) {
                            final pretty = const JsonEncoder.withIndent(
                              '  ',
                            ).convert(_sanitizeResponse(resp));
                            debugPrint('GC response (failed) =>\n$pretty');
                            await _showResponseDialog(_sanitizeResponse(resp));
                          } else {
                            debugPrint('GC response => null (no response)');
                            await _showResponseDialog({
                              'status': 'error',
                              'message':
                                  'Tidak ada respons atau sesi kadaluarsa',
                            });
                          }
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
                        final pretty = const JsonEncoder.withIndent(
                          '  ',
                        ).convert(_sanitizeResponse(resp));
                        debugPrint('GC response (success) =>\n$pretty');
                        final newToken = resp['new_gc_token'] as String?;
                        if (newToken != null && newToken.isNotEmpty) {
                          _gcToken = newToken;
                          await _saveStoredGcCredentials();
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
                      } catch (e) {
                        setStateSB(() {
                          isSubmitting = false;
                        });
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
    double? lon,
  ) async {
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
    );
    final idx = _allRecords.indexWhere((r) => r.idsbr == record.idsbr);
    if (idx != -1) {
      _allRecords[idx] = updated;
    }
    _refreshFilteredData();
    // Simpan perubahan ke cache lokal agar tetap ada saat restart (optimistic update)
    await _supabaseService.saveLocalRecords(_allRecords);

    await _supabaseService.updateRecord(updated);
    try {
      MapRepositoryImpl().invalidatePlacesCache();
      if (mounted) {
        context.read<MapBloc>().add(const PlacesRequested());
      }
    } catch (_) {}
  }

  Future<bool> _ensureGcConfig({bool forceShow = false}) async {
    // Jika kredensial sudah ada, pastikan sesi valid tanpa prompt (kecuali dipaksa)
    if (!forceShow &&
        _gcCookie != null &&
        _gcCookie!.isNotEmpty &&
        _gcToken != null &&
        _gcToken!.isNotEmpty) {
      try {
        await _gcService.autoGetCsrfToken();
        final valid = await _gcService.isSessionValid();
        if (valid) return true;
        // Sesi kadaluarsa: beri info lalu buka dialog
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Sesi GC kadaluarsa. Mohon perbarui Cookie/Token.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } catch (_) {}
    }

    // Bootstrap dari dart-define jika belum ada
    if ((_gcCookie == null || _gcCookie!.isEmpty) &&
        kInitialGcCookie.isNotEmpty) {
      _gcCookie = kInitialGcCookie;
      _gcService.setCookiesFromHeader(kInitialGcCookie);
    }
    if ((_gcToken == null || _gcToken!.isEmpty) && kInitialGcToken.isNotEmpty) {
      _gcToken = kInitialGcToken;
    }
    // Fallback dari .env jika dart-define kosong
    final envCookie = dotenv.dotenv.env['GC_COOKIE'];
    if ((_gcCookie == null || _gcCookie!.isEmpty) &&
        (envCookie?.trim().isNotEmpty ?? false)) {
      _gcCookie = envCookie!.trim();
      _gcService.setCookiesFromHeader(_gcCookie!);
    }
    final envToken = dotenv.dotenv.env['GC_TOKEN'];
    if ((_gcToken == null || _gcToken!.isEmpty) &&
        (envToken?.trim().isNotEmpty ?? false)) {
      _gcToken = envToken!.trim();
    }
    // Fallback Supabase per-user
    if ((_gcCookie == null || _gcCookie!.isEmpty) ||
        (_gcToken == null || _gcToken!.isEmpty)) {
      final remote = await _gcCredsService.loadGlobal();
      if (remote != null) {
        final rc = remote['gc_cookie']?.trim() ?? '';
        final rt = remote['gc_token']?.trim() ?? '';
        if (rc.isNotEmpty && (_gcCookie == null || _gcCookie!.isEmpty)) {
          _gcCookie = rc;
          _gcService.setCookiesFromHeader(rc);
        }
        if (rt.isNotEmpty && (_gcToken == null || _gcToken!.isEmpty)) {
          _gcToken = rt;
        }
      }
    }
    if (_gcCookie != null && _gcCookie!.isNotEmpty) {
      try {
        await _gcService.autoGetCsrfToken();
        final valid = await _gcService.isSessionValid();
        if (valid && _gcToken != null && _gcToken!.isNotEmpty) {
          await _saveStoredGcCredentials();
          return true;
        }
      } catch (_) {}
    }

    final cookieController = TextEditingController(text: _gcCookie ?? '');
    final tokenController = TextEditingController(text: _gcToken ?? '');

    final result = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Konfigurasi Groundcheck'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: cookieController,
                decoration: const InputDecoration(
                  labelText: 'Cookie',
                  hintText: 'Paste header Cookie dari browser',
                ),
                minLines: 1,
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: tokenController,
                decoration: const InputDecoration(labelText: 'GC Token'),
              ),
            ],
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

    if (result != true) {
      return false;
    }

    final cookie = cookieController.text.trim();
    final token = tokenController.text.trim();

    if (cookie.isEmpty || token.isEmpty) {
      return false;
    }

    _gcCookie = cookie;
    _gcToken = token;
    _gcService.setCookiesFromHeader(cookie);
    await _gcService.autoGetCsrfToken();
    await _saveStoredGcCredentials();
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(const Duration(minutes: 10), (_) async {
      await _gcService.keepAlive();
    });
    // Simpan juga ke Supabase
    await _gcCredsService.upsertGlobal(gcCookie: _gcCookie, gcToken: _gcToken);
    return true;
  }

  Future<void> _onGcPressed(GroundcheckRecord record) async {
    await _showGcInputDialog(record);
  }

  List<GroundcheckRecord> _filteredRecords() {
    return _allRecords.where((r) {
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
      if (_gcsFilter != null &&
          _gcsFilter!.isNotEmpty &&
          r.gcsResult != _gcsFilter) {
        return false;
      }
      return true;
    }).toList();
  }

  void _refreshFilteredData() {
    if (_dataSource == null) {
      return;
    }
    final filtered = _filteredRecords();
    _dataSource!.updateData(filtered);
  }

  Widget _buildFilterBar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          decoration: InputDecoration(
            labelText: 'Cari',
            hintText: 'Cari ID, nama usaha, alamat, kode wilayah',
            prefixIcon: const Icon(Icons.search),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            isDense: true,
          ),
          onChanged: (value) {
            setState(() {
              _searchQuery = value.trim();
            });
            _refreshFilteredData();
          },
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Groundcheck'),
        actions: [
          IconButton(
            icon: const Icon(Icons.cloud_upload),
            tooltip: 'Muat ulang dari Supabase',
            onPressed: _reloadFromSupabase,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Pengaturan GC',
            onPressed: () async {
              await _ensureGcConfig(forceShow: true);
            },
          ),
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
                  _buildFilterBar(),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Container(
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
                          verticalScrollController: _scrollController,
                          rowHeight: 56,
                          headerGridLinesVisibility:
                              GridLinesVisibility.horizontal,
                          gridLinesVisibility: GridLinesVisibility.horizontal,
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
                              columnName: 'status_perusahaan',
                              label: Container(
                                alignment: Alignment.centerLeft,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                color: Colors.blue[50],
                                child: const Text(
                                  'Status Perusahaan',
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
                              label: Container(
                                alignment: Alignment.centerLeft,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                color: Colors.blue[50],
                                child: const Text(
                                  'Skala Usaha',
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
                              columnName: 'latitude',
                              label: Container(
                                alignment: Alignment.centerLeft,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                color: Colors.blue[50],
                                child: const Text(
                                  'Latitude',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                            ),
                            GridColumn(
                              columnName: 'longitude',
                              label: Container(
                                alignment: Alignment.centerLeft,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                color: Colors.blue[50],
                                child: const Text(
                                  'Longitude',
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
    );
  }
}
