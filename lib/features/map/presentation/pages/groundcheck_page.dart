import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/services/bps_gc_service.dart';
import '../../data/services/groundcheck_supabase_service.dart';
import '../widgets/python_login_dialog.dart';
import '../widgets/inappwebview_login_dialog.dart';
import '../bloc/map_bloc.dart';
import '../bloc/map_event.dart';
import '../../data/repositories/map_repository_impl.dart';

// Optional bootstrap via --dart-define (removed)

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
  final bool isUploaded;
  final bool isRevisi;

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
    this.isUploaded = false,
    this.isRevisi = false,
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
      isUploaded: json['isUploaded'] == true,
      isRevisi: json['is_revisi'] == true || json['isRevisi'] == true,
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
      'isUploaded': isUploaded,
      'isRevisi': isRevisi,
    };
  }

  GroundcheckRecord copyWith({
    String? idsbr,
    String? namaUsaha,
    String? alamatUsaha,
    String? kodeWilayah,
    String? statusPerusahaan,
    String? skalaUsaha,
    String? gcsResult,
    String? latitude,
    String? longitude,
    String? perusahaanId,
    String? userId,
    bool? isUploaded,
    bool? isRevisi,
  }) {
    return GroundcheckRecord(
      idsbr: idsbr ?? this.idsbr,
      namaUsaha: namaUsaha ?? this.namaUsaha,
      alamatUsaha: alamatUsaha ?? this.alamatUsaha,
      kodeWilayah: kodeWilayah ?? this.kodeWilayah,
      statusPerusahaan: statusPerusahaan ?? this.statusPerusahaan,
      skalaUsaha: skalaUsaha ?? this.skalaUsaha,
      gcsResult: gcsResult ?? this.gcsResult,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      perusahaanId: perusahaanId ?? this.perusahaanId,
      userId: userId ?? this.userId,
      isUploaded: isUploaded ?? this.isUploaded,
      isRevisi: isRevisi ?? this.isRevisi,
    );
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
  String _searchQuery = '';
  String? _statusFilter;
  String? _gcsFilter;
  bool? _isUploadedFilter;
  bool _isLoading = true;
  String? _error;
  String? _gcCookie;
  String? _gcToken;
  String? _currentUser;
  String? _userAgent;
  String? _csrfToken;

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
      } else {
        // Jika data lokal kosong, JANGAN otomatis sync (karena akan trigger full download).
        // Biarkan user melakukan inisiasi download via tombol refresh atau UI kosong.
        // Initialize empty data to prevent UI crash
        if (mounted) {
          _processRecords([]);
        }
        return;
      }

      // 2. Sync with server (fetch only updates)
      // Hanya jalankan auto-sync jika kita sudah punya data lokal (incremental sync)
      try {
        final records = await _supabaseService.syncRecords();
        if (mounted) {
          if (records.isEmpty && _allRecords.isNotEmpty) {
            // Jika sync mengembalikan list kosong (error) tapi kita punya data lokal,
            // JANGAN ditimpa. Pertahankan data lokal yang sudah tampil.
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Gagal sinkronisasi data terbaru. Menggunakan data lokal.',
                ),
                backgroundColor: Colors.orange,
              ),
            );
          } else {
            _processRecords(records);
          }
        }
      } catch (e) {
        debugPrint('Error during background sync: $e');
        // Ignore error, keep showing local data
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
    super.dispose();
  }

  Future<void> _loadStoredGcCredentials() async {
    debugPrint('proses kirim: Menunggu login/input manual untuk kredensial.');
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _gcToken = prefs.getString('gc_token');
      _gcCookie = prefs.getString('gc_cookie');
    });
  }

  Future<void> _saveStoredGcCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    if (_gcToken != null) await prefs.setString('gc_token', _gcToken!);
    if (_gcCookie != null) await prefs.setString('gc_cookie', _gcCookie!);
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
      debugPrint('Mengupdate status upload untuk ${record.idsbr}...');
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
    String userName,
  ) async {
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

  Future<void> _showBpsLoginDialog() async {
    if (!mounted) return;

    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pilih Metode Login'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.web),
              title: const Text('Login via WebView'),
              subtitle: const Text(
                'Metode standar. Jika gagal kirim (419), gunakan metode Python.',
              ),
              onTap: () => Navigator.pop(ctx, 'webview'),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.terminal),
              title: const Text('Login via Python Script'),
              subtitle: const Text(
                'Jalankan script python & input hasil JSON. (Paling Stabil)',
              ),
              onTap: () => Navigator.pop(ctx, 'python'),
            ),
          ],
        ),
      ),
    );

    if (choice == null || !mounted) return;

    if (choice == 'python') {
      await showDialog(
        context: context,
        builder: (ctx) => PythonLoginDialog(
          onLoginSuccess: (data) async {
            final cookie = data['cookie_header'] ?? '';
            final gcToken = data['gc_token'] ?? '';
            final csrfToken = data['csrf_token'] ?? '';
            final userAgent = data['user_agent'] ?? '';
            final userName = data['user_name'] ?? 'Python User';

            await _handleLoginSuccess(
              cookie,
              gcToken,
              csrfToken,
              userAgent,
              userName,
            );
          },
        ),
      );
      return;
    }

    if (choice == 'webview') {
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
      return;
    }
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
      if (_isUploadedFilter != null && r.isUploaded != _isUploadedFilter) {
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
        _dataGridController.selectedRows.clear();
      }
    }
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
          } else if (record.gcsResult.isNotEmpty) {
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

            final resp = await _gcService.konfirmasiUser(
              perusahaanId: record.perusahaanId,
              latitude: lat.toString(),
              longitude: lon.toString(),
              hasilGc: record.gcsResult,
            );

            if (resp != null) {
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
            } else {
              debugPrint('Bulk GC Gagal untuk ${record.idsbr}: $resp');
              pendingRecords.add(
                record,
              ); // Masukkan kembali ke antrean untuk retry berikutnya
              failNotifier.value++; // Tambah counter gagal
            }
          } catch (e) {
            debugPrint('Bulk GC Exception untuk ${record.idsbr}: $e');
            pendingRecords.add(record); // Masukkan kembali ke antrean
            failNotifier.value++; // Tambah counter gagal
          }

          // Jeda antar record (tetap ada agar tidak spam)
          // Kecuali ini record terakhir di batch
          if (i < currentBatch.length - 1) {
            final delay = 1000 + random.nextInt(1001); // 1-2 detik
            await Future.delayed(Duration(milliseconds: delay));
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

      _dataGridController.selectedRows.clear();
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
              onPressed: _reloadFromSupabase,
              icon: const Icon(Icons.refresh),
              tooltip: 'Muat ulang data',
            ),
            IconButton(
              onPressed: () => _ensureGcConfig(forceShow: true),
              icon: const Icon(Icons.settings),
              tooltip: 'Pengaturan GC',
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
              child: DropdownButtonFormField<bool?>(
                value: _isUploadedFilter,
                decoration: const InputDecoration(
                  labelText: 'Status Upload',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem<bool?>(value: null, child: Text('Semua')),
                  DropdownMenuItem<bool?>(
                    value: true,
                    child: Text('Sudah Upload'),
                  ),
                  DropdownMenuItem<bool?>(
                    value: false,
                    child: Text('Belum Upload'),
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
    return Scaffold(
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: _dataGridController.selectedRows.isNotEmpty
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FloatingActionButton.extended(
                  heroTag: 'fab_edit',
                  onPressed: _handleBulkEditStatus,
                  icon: const Icon(Icons.edit),
                  label: const Text('Ubah Status'),
                  backgroundColor: Colors.orange,
                ),
                const SizedBox(width: 16),
                FloatingActionButton.extended(
                  heroTag: 'fab_send',
                  onPressed: _handleBulkGc,
                  icon: const Icon(Icons.send),
                  label: Text(
                    'Kirim GC (${_dataGridController.selectedRows.length})',
                  ),
                ),
              ],
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
                                            'Refresh Sesi',
                                            style: TextStyle(
                                              color: Colors.blue,
                                            ),
                                          ),
                                          style: OutlinedButton.styleFrom(
                                            side: const BorderSide(
                                              color: Colors.blue,
                                            ),
                                            padding: const EdgeInsets.symmetric(
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
                                            style: TextStyle(color: Colors.red),
                                          ),
                                          style: OutlinedButton.styleFrom(
                                            side: const BorderSide(
                                              color: Colors.red,
                                            ),
                                            padding: const EdgeInsets.symmetric(
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
                      child: ElevatedButton.icon(
                        onPressed: _showBpsLoginDialog,
                        icon: const Icon(Icons.login),
                        label: const Text('Login ke BPS (Matchapro)'),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                        ),
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
    );
  }
}
