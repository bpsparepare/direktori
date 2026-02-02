import 'dart:convert';
import 'dart:math';
import 'dart:async';

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

  GroundcheckDataSource({
    required List<GroundcheckRecord> data,
    this.onGcPressed,
    this.onGoToMap,
  }) {
    _buildRows(data);
  }

  @override
  List<DataGridRow> get rows => _rows;

  GroundcheckRecord? getRecord(DataGridRow row) => _rowToRecord[row];

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
          DataGridCell<String>(
            columnName: 'status_perusahaan',
            value: e.statusPerusahaan,
          ),
          DataGridCell<String>(columnName: 'sumber_data', value: e.sumberData),
          DataGridCell<bool>(columnName: 'isUploaded', value: e.isUploaded),
          DataGridCell<String>(columnName: 'gcs_result', value: e.gcsResult),
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
  bool _isLoading = true;
  bool _isDeletingNew = false;
  String? _error;
  String? _gcCookie;
  String? _gcToken;
  String? _currentUser;
  String? _currentLoginId; // Username login asli (e.g. muharram-pppk)
  String? _userAgent;
  String? _csrfToken;
  bool _isDialogShowing = false;

  @override
  void initState() {
    super.initState();
    _loadStoredGcCredentials().then((_) {
      _loadData();
    });
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
    _sumberDataOptions =
        records
            .map((e) => e.sumberData.trim())
            .where((v) => v.isNotEmpty)
            .toSet()
            .toList()
          ..sort();

    // Validasi filter saat ini agar tetap konsisten dengan opsi baru (trim)
    if (_sumberDataFilter != null) {
      final trimmed = _sumberDataFilter!.trim();
      if (_sumberDataOptions.contains(trimmed)) {
        _sumberDataFilter = trimmed;
      } else {
        // Jika opsi yang dipilih tidak ada lagi (misal data berubah total), reset
        _sumberDataFilter = null;
      }
    }

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
      if (_sumberDataFilter != null &&
          _sumberDataFilter!.isNotEmpty &&
          r.sumberData.trim() != _sumberDataFilter) {
        return false;
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
      // setState(() {
      //   _isLoading = true;
      // });

      int count = 0;
      for (final row in selected) {
        final record = _dataSource?.getRecord(row);
        if (record != null) {
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

      if (mounted) {
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
      bool isDialogVisible = true;

      if (mounted) {
        // Show Progress Dialog
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) {
            return WillPopScope(
              onWillPop: () async => false,
              child: AlertDialog(
                title: ValueListenableBuilder<bool>(
                  valueListenable: isFinishedNotifier,
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
                      valueListenable: progressNotifier,
                      builder: (context, val, child) {
                        return LinearProgressIndicator(
                          value: total > 0 ? val / total : 0,
                          backgroundColor: Colors.grey[200],
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    ValueListenableBuilder<String>(
                      valueListenable: statusNotifier,
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
                      valueListenable: progressNotifier,
                      builder: (context, val, child) {
                        // Tampilkan info progress yang lebih detail jika perlu
                        return Text(
                          '$val dari $total data sukses',
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
                          valueListenable: successNotifier,
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
                          valueListenable: failNotifier,
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
                          valueListenable: pendingUiNotifier,
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
                    valueListenable: isFinishedNotifier,
                    builder: (context, isFinished, child) {
                      if (!isFinished) {
                        return TextButton(
                          onPressed: () {
                            Navigator.pop(ctx);
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
                    valueListenable: isFinishedNotifier,
                    builder: (context, isFinished, child) {
                      if (!isFinished) {
                        return TextButton(
                          onPressed: () {
                            isCancelledNotifier.value = true;
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
            );
          },
        ).then((_) {
          isDialogVisible = false;
        });
      }

      List<GroundcheckRecord> pendingRecords = List.from(validRecords);
      int maxRetries = 3;

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
            // Gunakan koordinat yang ada di record jika valid, atau fallback ke 0
            final lat = double.tryParse(record.latitude) ?? 0.0;
            final lon = double.tryParse(record.longitude) ?? 0.0;

            final resp = await _gcService
                .konfirmasiUser(
                  perusahaanId: record.perusahaanId,
                  latitude: lat.toString(),
                  longitude: lon.toString(),
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
              if (itemsSentWithCurrentAccount >= 30 &&
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
          for (int t = 4; t > 0; t--) {
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

      if (!isDialogVisible && mounted) {
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
              child: DropdownButtonFormField<String>(
                value: _sumberDataFilter ?? '',
                decoration: const InputDecoration(
                  labelText: 'Sumber Data',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<String>(
                    value: '',
                    child: Text('Semua Sumber'),
                  ),
                  ..._sumberDataOptions.map(
                    (s) => DropdownMenuItem<String>(value: s, child: Text(s)),
                  ),
                ],
                onChanged: (value) {
                  setState(() {
                    _sumberDataFilter = value != null && value.isNotEmpty
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
                    ],
                  );
                },
              )
            : null,
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
