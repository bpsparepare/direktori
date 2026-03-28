import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/map_bloc.dart';
import '../bloc/map_event.dart';
import '../bloc/map_state.dart';
import '../../data/repositories/map_repository_impl.dart';
import '../../data/services/bps_gc_service.dart';
import 'compass_widget.dart';
import '../../domain/entities/polygon_data.dart';
import 'map_type.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../utils/map_download_helper.dart';

class _ClipboardParsedRow {
  final int no;
  final String name;
  final String address;
  final String rawLatitude;
  final String rawLongitude;
  final double? latitude;
  final double? longitude;
  final String? error;

  const _ClipboardParsedRow({
    required this.no,
    required this.name,
    required this.address,
    required this.rawLatitude,
    required this.rawLongitude,
    required this.latitude,
    required this.longitude,
    required this.error,
  });

  bool get isValid => error == null && latitude != null && longitude != null;
}

class MapControls extends StatefulWidget {
  final MapController mapController;
  final VoidCallback? onResetPosition;
  final LatLng? initialCenter;
  final double rotation;
  final Function(LatLng)? onLocationUpdate; // Add location update callback
  final VoidCallback? onPolygonSelection; // Add polygon selection callback
  final List<PolygonData> polygonsMeta; // Add polygons metadata
  final Function(int)?
  onPolygonSelected; // Add callback for when polygon is selected
  final Function(List<PolygonData>)?
  onMultiplePolygonsSelected; // Add callback for multiple polygons
  final MapType currentMapType; // Add current map type
  final Function(MapType)? onMapTypeChanged; // Add map type change callback
  final Function(double, double)? onOffsetChanged; // Add offset change callback
  final double currentOffsetX; // Current X offset
  final double currentOffsetY; // Current Y offset
  final bool showGroundcheckMarkers;
  final Function(bool)? onToggleGroundcheckMarkers;
  final bool showDirectoryMarkers;
  final Function(bool)? onToggleDirectoryMarkers;
  final bool showMarkerLabels;
  final Function(bool)? onToggleMarkerLabels;
  final bool showNonVerifiedGroundchecks;
  final Function(bool)? onToggleNonVerifiedGroundchecks;
  final bool isPolygonSelected; // Boolean to track if a polygon is selected
  final VoidCallback? onToggleFontSize; // Callback for font size toggle
  final void Function(LatLng point, String label)? onClipboardPointSelected;

  const MapControls({
    super.key,
    required this.mapController,
    this.onResetPosition,
    this.initialCenter,
    required this.rotation,
    this.onLocationUpdate, // Add to constructor
    this.onPolygonSelection, // Add to constructor
    this.polygonsMeta = const [], // Add to constructor
    this.onPolygonSelected, // Add to constructor
    this.onMultiplePolygonsSelected, // Add to constructor
    required this.currentMapType, // Add to constructor
    this.onMapTypeChanged, // Add to constructor
    this.onOffsetChanged, // Add to constructor
    this.currentOffsetX = 0.0, // Add to constructor
    this.currentOffsetY = 0.0, // Add to constructor
    this.showGroundcheckMarkers = true,
    this.onToggleGroundcheckMarkers,
    this.showDirectoryMarkers = true,
    this.onToggleDirectoryMarkers,
    this.showMarkerLabels = true,
    this.onToggleMarkerLabels,
    this.showNonVerifiedGroundchecks = true,
    this.onToggleNonVerifiedGroundchecks,
    this.isPolygonSelected = false, // Initialize
    this.onToggleFontSize,
    this.onClipboardPointSelected,
  });

  @override
  State<MapControls> createState() => _MapControlsState();
}

class _MapControlsState extends State<MapControls> {
  bool _isLoadingLocation = false;
  String _appVersion = '';
  bool _hasPromptedDownload = false;
  StreamSubscription<Position>? _positionStreamSubscription;
  String _cachedClipboardText = '';
  List<_ClipboardParsedRow> _cachedClipboardRows = const [];

  double? _tryParseCoordinate(String input) {
    final match = RegExp(r'(-?\d+(?:[.,]\d+)?)').firstMatch(input);
    if (match == null) return null;
    final normalized = match.group(1)!.replaceAll(',', '.').trim();
    return double.tryParse(normalized);
  }

  ({String name, String address, double latitude, double longitude})?
  _tryParseClipboardText(String raw) {
    final text = raw.replaceAll('\u00A0', ' ').replaceAll('\r', '\n').trim();
    if (text.isEmpty) return null;

    final latMatch = RegExp(
      r'(?:\blat(?:itude)?\b)[^\d-]*(-?\d+(?:[.,]\d+)?)',
      caseSensitive: false,
    ).firstMatch(text);
    final lngMatch = RegExp(
      r'(?:\b(?:lng|lon|long|longitude)\b)[^\d-]*(-?\d+(?:[.,]\d+)?)',
      caseSensitive: false,
    ).firstMatch(text);

    double? lat;
    double? lng;
    if (latMatch != null) {
      lat = _tryParseCoordinate(latMatch.group(1) ?? '');
    }
    if (lngMatch != null) {
      lng = _tryParseCoordinate(lngMatch.group(1) ?? '');
    }

    final lines = text
        .split(RegExp(r'[\n\t]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    if ((lat == null || lng == null) && lines.length >= 4) {
      lat ??= _tryParseCoordinate(lines[2]);
      lng ??= _tryParseCoordinate(lines[3]);
    }

    if ((lat == null || lng == null) && text.contains('|')) {
      final parts = text
          .split('|')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (parts.length >= 4) {
        lat ??= _tryParseCoordinate(parts[2]);
        lng ??= _tryParseCoordinate(parts[3]);
      }
    }

    String name = '';
    String address = '';
    if (lines.isNotEmpty) {
      name = lines[0];
      if (lines.length >= 2) address = lines[1];
    }

    if ((lat == null || lng == null) && RegExp(r'[-\d]').hasMatch(text)) {
      final allMatches = RegExp(
        r'(-?\d+(?:[.,]\d+)?)',
      ).allMatches(text).toList();
      final numbers = allMatches
          .map((m) => m.group(1)!.replaceAll(',', '.'))
          .map(double.tryParse)
          .whereType<double>()
          .toList();

      for (var i = 0; i + 1 < numbers.length; i++) {
        final a = numbers[i];
        final b = numbers[i + 1];
        final aLatOk = a >= -90 && a <= 90;
        final bLngOk = b >= -180 && b <= 180;
        if (aLatOk && bLngOk) {
          lat ??= a;
          lng ??= b;
          break;
        }
      }
    }

    if (name.trim().isEmpty || address.trim().isEmpty) return null;
    if (lat == null || lng == null) return null;
    if (lat < -90 || lat > 90) return null;
    if (lng < -180 || lng > 180) return null;

    return (name: name, address: address, latitude: lat, longitude: lng);
  }

  List<_ClipboardParsedRow> _parseClipboardRows(String raw) {
    final text = raw.replaceAll('\u00A0', ' ').replaceAll('\r', '\n').trim();
    if (text.isEmpty) return [];

    _ClipboardParsedRow buildRow({
      required int no,
      required String name,
      required String address,
      required String rawLatitude,
      required String rawLongitude,
    }) {
      final n = name.trim();
      final a = address.trim();
      final lat = _tryParseCoordinate(rawLatitude);
      final lng = _tryParseCoordinate(rawLongitude);

      String? error;
      if (n.isEmpty) {
        error = 'Nama kosong';
      } else if (a.isEmpty) {
        error = 'Alamat kosong';
      } else if (lat == null || lng == null) {
        error = 'Koordinat tidak valid';
      } else if (lat < -90 || lat > 90) {
        error = 'Latitude di luar range';
      } else if (lng < -180 || lng > 180) {
        error = 'Longitude di luar range';
      }

      return _ClipboardParsedRow(
        no: no,
        name: n,
        address: a,
        rawLatitude: rawLatitude.trim(),
        rawLongitude: rawLongitude.trim(),
        latitude: lat,
        longitude: lng,
        error: error,
      );
    }

    if (text.contains('\t')) {
      final lines = text
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      final rows = <_ClipboardParsedRow>[];
      for (var i = 0; i < lines.length; i++) {
        final cols = lines[i]
            .split(RegExp(r'\t+'))
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
        if (cols.length < 4) {
          rows.add(
            _ClipboardParsedRow(
              no: i + 1,
              name: cols.isNotEmpty ? cols[0] : '',
              address: cols.length >= 2 ? cols[1] : '',
              rawLatitude: cols.length >= 3 ? cols[2] : '',
              rawLongitude: cols.length >= 4 ? cols[3] : '',
              latitude: null,
              longitude: null,
              error: 'Kolom kurang (butuh 4 kolom)',
            ),
          );
          continue;
        }

        rows.add(
          buildRow(
            no: i + 1,
            name: cols[0],
            address: cols[1],
            rawLatitude: cols[2],
            rawLongitude: cols[3],
          ),
        );
      }
      return rows;
    }

    final lines = text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    if (lines.length >= 4 && lines.length % 4 == 0) {
      final rows = <_ClipboardParsedRow>[];
      for (var i = 0; i < lines.length; i += 4) {
        final no = (i ~/ 4) + 1;
        rows.add(
          buildRow(
            no: no,
            name: lines[i],
            address: lines[i + 1],
            rawLatitude: lines[i + 2],
            rawLongitude: lines[i + 3],
          ),
        );
      }
      return rows;
    }

    if (lines.any((l) => l.contains('|'))) {
      final rows = <_ClipboardParsedRow>[];
      final candidates = lines
          .where((l) => l.contains('|'))
          .map((l) => l.trim())
          .toList();
      for (var i = 0; i < candidates.length; i++) {
        final parts = candidates[i]
            .split('|')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
        if (parts.length < 4) {
          rows.add(
            _ClipboardParsedRow(
              no: i + 1,
              name: parts.isNotEmpty ? parts[0] : '',
              address: parts.length >= 2 ? parts[1] : '',
              rawLatitude: parts.length >= 3 ? parts[2] : '',
              rawLongitude: parts.length >= 4 ? parts[3] : '',
              latitude: null,
              longitude: null,
              error: 'Kolom kurang (butuh 4 kolom)',
            ),
          );
          continue;
        }
        rows.add(
          buildRow(
            no: i + 1,
            name: parts[0],
            address: parts[1],
            rawLatitude: parts[2],
            rawLongitude: parts[3],
          ),
        );
      }
      if (rows.isNotEmpty) return rows;
    }

    final single = _tryParseClipboardText(text);
    if (single != null) {
      return [
        _ClipboardParsedRow(
          no: 1,
          name: single.name,
          address: single.address,
          rawLatitude: single.latitude.toString(),
          rawLongitude: single.longitude.toString(),
          latitude: single.latitude,
          longitude: single.longitude,
          error: null,
        ),
      ];
    }

    return [];
  }

  Future<void> _showClipboardCheckDialog() async {
    List<_ClipboardParsedRow> rows = const [];
    String? errorText;
    final controller = TextEditingController();

    try {
      controller.text = _cachedClipboardText;
      rows = _cachedClipboardRows;
      if (rows.isEmpty && controller.text.trim().isNotEmpty) {
        rows = _parseClipboardRows(controller.text);
      }
      if (rows.isNotEmpty) {
        errorText = null;
      } else if (controller.text.trim().isNotEmpty) {
        errorText =
            'Data tidak valid / tidak terdeteksi. Pastikan formatnya benar.';
      }

      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              void recompute() {
                setDialogState(() {
                  rows = _parseClipboardRows(controller.text);
                  errorText = rows.isEmpty
                      ? 'Data tidak valid / tidak terdeteksi. Pastikan formatnya benar.'
                      : null;
                });
                _cachedClipboardText = controller.text;
                _cachedClipboardRows = rows;
              }

              final validCount = rows.where((r) => r.isValid).length;
              return AlertDialog(
                title: const Text('Cek Data Clipboard'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Format yang didukung: multi-row dari Excel (kolom dipisah tab): Nama, Alamat, Latitude, Longitude. Bisa juga 4 baris per data.',
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: () async {
                          final data = await Clipboard.getData(
                            Clipboard.kTextPlain,
                          );
                          controller.text = data?.text?.trim() ?? '';
                          recompute();
                        },
                        icon: const Icon(Icons.content_paste),
                        label: const Text('Ambil dari Clipboard'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        minLines: 3,
                        maxLines: 6,
                        decoration: const InputDecoration(
                          labelText: 'Teks clipboard',
                          border: OutlineInputBorder(),
                        ),
                        controller: controller,
                        onChanged: (_) => recompute(),
                      ),
                      if (rows.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text('Valid: $validCount / ${rows.length}'),
                      ],
                      if (errorText != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          errorText!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ],
                      if (rows.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            columns: const [
                              DataColumn(label: Text('No')),
                              DataColumn(label: Text('Nama')),
                              DataColumn(label: Text('Alamat')),
                              DataColumn(label: Text('Lat')),
                              DataColumn(label: Text('Lng')),
                              DataColumn(label: Text('Aksi')),
                            ],
                            rows: rows.map((r) {
                              final latText =
                                  r.latitude?.toStringAsFixed(6) ??
                                  (r.rawLatitude.isEmpty ? '-' : r.rawLatitude);
                              final lngText =
                                  r.longitude?.toStringAsFixed(6) ??
                                  (r.rawLongitude.isEmpty
                                      ? '-'
                                      : r.rawLongitude);
                              return DataRow(
                                cells: [
                                  DataCell(Text(r.no.toString())),
                                  DataCell(
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 220,
                                      ),
                                      child: Text(
                                        r.name.isEmpty ? '-' : r.name,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 280,
                                      ),
                                      child: Text(
                                        r.address.isEmpty ? '-' : r.address,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                  DataCell(Text(latText)),
                                  DataCell(Text(lngText)),
                                  DataCell(
                                    r.isValid
                                        ? ElevatedButton(
                                            onPressed: () {
                                              _cachedClipboardText =
                                                  controller.text;
                                              _cachedClipboardRows = rows;
                                              final target = LatLng(
                                                r.latitude!,
                                                r.longitude!,
                                              );
                                              Navigator.of(dialogContext).pop();
                                              widget.mapController.move(
                                                target,
                                                18.0,
                                              );
                                              widget.onClipboardPointSelected
                                                  ?.call(target, r.name);
                                              ScaffoldMessenger.of(
                                                this.context,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    'Menuju: ${r.name}',
                                                  ),
                                                  duration: const Duration(
                                                    milliseconds: 1200,
                                                  ),
                                                ),
                                              );
                                            },
                                            child: const Text('Menuju'),
                                          )
                                        : Text(
                                            r.error ?? 'Tidak valid',
                                            style: const TextStyle(
                                              color: Colors.red,
                                            ),
                                          ),
                                  ),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Tutup'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      controller.dispose();
    }
  }

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
    // Auto-detect location when widget is initialized
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startLiveLocationUpdates();
    });
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadAppVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _appVersion = 'v${info.version}';
      });
    }
  }

  Future<void> _startLiveLocationUpdates() async {
    setState(() {
      _isLoadingLocation = true;
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showLocationError('Layanan lokasi tidak aktif. Silakan aktifkan GPS.');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showLocationError(
            'Izin lokasi ditolak. Silakan berikan izin untuk menggunakan fitur ini.',
          );
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _showLocationError(
          'Izin lokasi ditolak permanen. Silakan aktifkan di pengaturan aplikasi.',
        );
        await Geolocator.openAppSettings();
        return;
      }

      // 1. Get initial position immediately
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 10),
        );
      } catch (_) {
        position = await Geolocator.getLastKnownPosition();
      }

      if (position != null) {
        final currentLocation = LatLng(position.latitude, position.longitude);
        widget.mapController.move(currentLocation, 15.0);
        if (widget.onLocationUpdate != null) {
          widget.onLocationUpdate!(currentLocation);
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Lokasi berhasil ditemukan'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }

      // 2. Start streaming for updates
      _positionStreamSubscription?.cancel();
      _positionStreamSubscription =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 10,
            ),
          ).listen(
            (Position position) {
              final currentLocation = LatLng(
                position.latitude,
                position.longitude,
              );
              // Only update marker, don't force move camera on every update (user might be panning)
              if (widget.onLocationUpdate != null) {
                widget.onLocationUpdate!(currentLocation);
              }
            },
            onError: (e) {
              debugPrint('Location stream error: $e');
            },
          );
    } catch (e) {
      debugPrint('Error getting location: $e');
      _showLocationError('Gagal mendapatkan lokasi: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingLocation = false;
        });
      }
    }
  }

  Future<void> _getCurrentLocation() async {
    // If stream is active, just recenter. If not, restart stream.
    if (_positionStreamSubscription != null &&
        !_positionStreamSubscription!.isPaused) {
      // Try to get current position for immediate recenter
      try {
        final position = await Geolocator.getCurrentPosition();
        final currentLocation = LatLng(position.latitude, position.longitude);
        widget.mapController.move(currentLocation, 15.0);
        widget.onLocationUpdate?.call(currentLocation);
      } catch (_) {
        // If fails, just restart stream logic
        _startLiveLocationUpdates();
      }
    } else {
      _startLiveLocationUpdates();
    }
  }

  void _showLocationError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    }
  }

  void _resetToNorth() {
    // Reset rotation to 0 (north) with animation
    widget.mapController.rotate(0.0);
    widget.onResetPosition?.call();
  }

  Future<void> _handleFullDownload(BuildContext context) async {
    // Gunakan helper yang sudah distandarisasi
    await MapDownloadHelper.showRedownloadDialog(context);
  }

  Future<String> _getLastIncrementalSyncText() async {
    final prefs = await SharedPreferences.getInstance();
    // Use the key defined in GroundcheckSupabaseService
    final lastSyncStr = prefs.getString('groundcheck_last_sync_time');
    if (lastSyncStr == null) return 'Belum pernah';

    final date = DateTime.tryParse(lastSyncStr);
    if (date == null) return 'Format waktu salah';

    // Convert to local time for display
    final localDate = date.toLocal();
    final now = DateTime.now();
    final diff = now.difference(localDate);

    if (diff.inMinutes < 1) return 'Baru saja';
    if (diff.inMinutes < 60) return '${diff.inMinutes} menit yang lalu';
    if (diff.inHours < 24) return '${diff.inHours} jam yang lalu';
    return '${localDate.day}/${localDate.month} ${localDate.hour}:${localDate.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _showInitialDownloadPrompt(BuildContext context) async {
    // DOUBLE CHECK: Cek repository langsung untuk memastikan data benar-benar kosong
    // Ini mencegah popup muncul saat BLoC belum selesai memuat data tapi status sudah success
    try {
      final repository = context.read<MapRepositoryImpl>();
      final places = await repository.getPlaces();
      if (places.isNotEmpty) {
        // Data sudah ada, batalkan popup
        return;
      }
    } catch (e) {
      debugPrint('Error checking repository in prompt: $e');
    }

    if (!mounted) return;

    // Gunakan helper yang sudah distandarisasi
    await MapDownloadHelper.showInitialDownloadDialog(context);
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 16,
      top: 100,
      child: BlocListener<MapBloc, MapState>(
        listener: (context, state) {
          // Disable auto-prompt for initial download to avoid duplicate dialogs with GroundcheckPage
          // User can manually trigger download from the menu button
          /*
          if (!_hasPromptedDownload &&
              state.status == MapStatus.success &&
              state.places.isEmpty) {
            _hasPromptedDownload = true;
            _showInitialDownloadPrompt(context);
          }
          */
        },
        child: Column(
          children: [
            // Map Type Selector
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: PopupMenuButton<MapType>(
                icon: const Icon(Icons.layers, color: Colors.black87),
                tooltip: 'Pilih Jenis Peta',
                onSelected: (MapType mapType) {
                  widget.onMapTypeChanged?.call(mapType);
                },
                itemBuilder: (BuildContext context) =>
                    MapType.values.map((MapType mapType) {
                      return PopupMenuItem<MapType>(
                        value: mapType,
                        child: Row(
                          children: [
                            Icon(
                              widget.currentMapType == mapType
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_unchecked,
                              color: widget.currentMapType == mapType
                                  ? Colors.blue
                                  : Colors.grey,
                            ),
                            const SizedBox(width: 8),
                            Text(mapType.name),
                          ],
                        ),
                      );
                    }).toList(),
              ),
            ),
            const SizedBox(height: 8),

            // Offset Controls (only show for Esri satellite)
            if (widget.currentMapType == MapType.satellite)
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: PopupMenuButton(
                  icon: const Icon(Icons.tune, color: Colors.black87),
                  tooltip: 'Sesuaikan Posisi Peta',
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      enabled: false,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Sesuaikan Posisi Peta',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 16),
                          // X Offset Control
                          Row(
                            children: [
                              const Text('X: '),
                              Expanded(
                                child: Slider(
                                  value: widget.currentOffsetX,
                                  min: -50.0,
                                  max: 50.0,
                                  divisions: 100,
                                  label: widget.currentOffsetX.toStringAsFixed(
                                    1,
                                  ),
                                  onChanged: (value) {
                                    widget.onOffsetChanged?.call(
                                      value,
                                      widget.currentOffsetY,
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                          // Y Offset Control
                          Row(
                            children: [
                              const Text('Y: '),
                              Expanded(
                                child: Slider(
                                  value: widget.currentOffsetY,
                                  min: -50.0,
                                  max: 50.0,
                                  divisions: 100,
                                  label: widget.currentOffsetY.toStringAsFixed(
                                    1,
                                  ),
                                  onChanged: (value) {
                                    widget.onOffsetChanged?.call(
                                      widget.currentOffsetX,
                                      value,
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                          // Reset Button
                          ElevatedButton(
                            onPressed: () {
                              widget.onOffsetChanged?.call(0.0, 0.0);
                            },
                            child: const Text('Reset'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),

            // Compass Widget
            CompassWidget(rotation: widget.rotation, onTap: _resetToNorth),
            const SizedBox(height: 8),

            // Current Location Button
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: IconButton(
                onPressed: _isLoadingLocation ? null : _getCurrentLocation,
                icon: _isLoadingLocation
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location, color: Colors.green),
                tooltip: 'Lokasi Saya',
              ),
            ),
            const SizedBox(height: 8),
            // Refresh Markers Button
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: PopupMenuButton<String>(
                icon: const Icon(Icons.refresh, color: Colors.black87),
                tooltip: 'Refresh Marker',
                onSelected: (value) {
                  if (value == 'all') {
                    _handleFullDownload(context);
                  } else if (value == 'refresh') {
                    // Incremental sync (default)
                    context.read<MapBloc>().add(const PlacesRefreshRequested());
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Mengambil data terbaru...'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  }
                },
                itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(
                    enabled: false,
                    child: FutureBuilder<String>(
                      future: _getLastIncrementalSyncText(),
                      builder: (context, snapshot) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Terakhir Update:',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                            Text(
                              snapshot.data ?? 'Memuat...',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem<String>(
                    value: 'refresh',
                    child: ListTile(
                      leading: Icon(Icons.sync),
                      title: Text('Refresh Data'),
                      subtitle: Text('Ambil update terbaru (Cepat)'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'all',
                    child: ListTile(
                      leading: Icon(Icons.cloud_download),
                      title: Text('Download Semua Data'),
                      subtitle: Text('Reset ulang database (Lama)'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Toggle Non-Verified Groundcheck Markers
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: IconButton(
                onPressed: () {
                  if (widget.onToggleNonVerifiedGroundchecks != null) {
                    widget.onToggleNonVerifiedGroundchecks!(
                      !widget.showNonVerifiedGroundchecks,
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          !widget.showNonVerifiedGroundchecks
                              ? 'Menampilkan semua hasil GC'
                              : 'Menampilkan hanya GC yang sudah selesai (Kode 1)',
                        ),
                        duration: const Duration(milliseconds: 1000),
                      ),
                    );
                  }
                },
                icon: Icon(
                  widget.showNonVerifiedGroundchecks
                      ? Icons.filter_alt_off
                      : Icons.filter_alt,
                  color: widget.showNonVerifiedGroundchecks
                      ? Colors.grey
                      : Colors.blue,
                ),
                tooltip: 'Filter Status GC (Kode 1)',
              ),
            ),
            const SizedBox(height: 8),
            // Toggle Font Size Button
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: IconButton(
                onPressed: widget.onToggleFontSize,
                icon: const Icon(Icons.text_fields, color: Colors.black87),
                tooltip: 'Ubah Ukuran Font',
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: IconButton(
                onPressed: _showClipboardCheckDialog,
                icon: const Icon(
                  Icons.assignment_turned_in,
                  color: Colors.black87,
                ),
                tooltip: 'Cek Data Clipboard',
              ),
            ),
            const SizedBox(height: 8),
            // Pilih Polygon FAB
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: _showPolygonSelection,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.select_all, color: Colors.blue, size: 20),
                        // SizedBox(width: 6),
                        // Text(
                        //   'Pilih Polygon',
                        //   style: TextStyle(
                        //     color: Colors.blue,
                        //     fontSize: 12,
                        //     fontWeight: FontWeight.w500,
                        //   ),
                        // ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (widget.isPolygonSelected) ...[
              const SizedBox(height: 8),
              // Hapus Pilihan FAB
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: _clearPolygonSelection,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.layers_clear, color: Colors.red, size: 20),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],

            // App Version Info (Small text at bottom)
            if (_appVersion.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _appVersion,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _clearPolygonSelection() {
    widget.onMultiplePolygonsSelected?.call([]);
  }

  void _showPolygonSelection() async {
    if (widget.polygonsMeta.isEmpty) return;

    // Pre-process for Kelurahan groups
    final Map<String, List<PolygonData>> kelurahanGroups = {};
    for (final p in widget.polygonsMeta) {
      final id = p.idsls ?? '';
      if (id.length >= 10) {
        final key = id.substring(0, 10);
        kelurahanGroups.putIfAbsent(key, () => []).add(p);
      }
    }

    // Sort Kelurahan keys
    final sortedKelurahanKeys = kelurahanGroups.keys.toList()
      ..sort((a, b) {
        final pa = kelurahanGroups[a]!.first;
        final pb = kelurahanGroups[b]!.first;
        final ka = pa.kecamatan ?? '';
        final kb = pb.kecamatan ?? '';
        final c = ka.compareTo(kb);
        if (c != 0) return c;
        return (pa.desa ?? '').compareTo(pb.desa ?? '');
      });

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (modalContext) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(modalContext).viewInsets.bottom,
          ),
          child: Container(
            height: MediaQuery.of(context).size.height * 0.9,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  // Handle bar
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // Header
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.map_outlined, color: Colors.grey),
                        const SizedBox(width: 8),
                        const Text(
                          'Pilih Wilayah',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: () => Navigator.pop(modalContext),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  // TabBar
                  const TabBar(
                    labelColor: Colors.blue,
                    unselectedLabelColor: Colors.grey,
                    indicatorColor: Colors.blue,
                    tabs: [
                      Tab(text: 'Per SLS'),
                      Tab(text: 'Per Kelurahan'),
                    ],
                  ),
                  // Content
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildSlsTab(modalContext),
                        _buildKelurahanTab(
                          modalContext,
                          kelurahanGroups,
                          sortedKelurahanKeys,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSlsTab(BuildContext modalContext) {
    String query = '';
    return StatefulBuilder(
      builder: (ctx, setState) {
        final filtered = widget.polygonsMeta.where((p) {
          final q = query.toLowerCase();
          final n = (p.name ?? '').toLowerCase();
          final kc = (p.kecamatan ?? '').toLowerCase();
          final ds = (p.desa ?? '').toLowerCase();
          return n.contains(q) || kc.contains(q) || ds.contains(q);
        }).toList()..sort((a, b) => (a.idsls ?? '').compareTo(b.idsls ?? ''));

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Cari SLS / Kelurahan / Kec',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                onChanged: (v) => setState(() => query = v),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: filtered.length,
                itemBuilder: (context, i) {
                  final item = filtered[i];
                  return Card(
                    margin: const EdgeInsets.symmetric(
                      vertical: 4,
                      horizontal: 8,
                    ),
                    elevation: 0,
                    color: Colors.grey[50],
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(color: Colors.grey[200]!),
                    ),
                    child: ListTile(
                      title: Text(
                        item.name ?? '-',
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      subtitle: Text(
                        'Kec: ${item.kecamatan ?? '-'} • Kel: ${item.desa ?? '-'}',
                      ),
                      trailing: const Icon(
                        Icons.chevron_right,
                        color: Colors.grey,
                      ),
                      onTap: () {
                        Navigator.pop(modalContext);
                        if (widget.onMultiplePolygonsSelected != null) {
                          widget.onMultiplePolygonsSelected!([item]);
                        } else {
                          // Fallback to single selection if multi not defined (though it should be)
                          final idx = widget.polygonsMeta.indexOf(item);
                          widget.onPolygonSelected?.call(idx);
                        }
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildKelurahanTab(
    BuildContext modalContext,
    Map<String, List<PolygonData>> kelurahanGroups,
    List<String> sortedKeys,
  ) {
    String query = '';
    return StatefulBuilder(
      builder: (ctx, setState) {
        final filteredKeys = sortedKeys.where((key) {
          final q = query.toLowerCase();
          final group = kelurahanGroups[key]!;
          final first = group.first;
          final kc = (first.kecamatan ?? '').toLowerCase();
          final ds = (first.desa ?? '').toLowerCase();
          return kc.contains(q) || ds.contains(q);
        }).toList();

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Cari Kelurahan / Kecamatan',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                onChanged: (v) => setState(() => query = v),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: filteredKeys.length,
                itemBuilder: (context, i) {
                  final key = filteredKeys[i];
                  final group = kelurahanGroups[key]!;
                  final first = group.first;

                  return Card(
                    margin: const EdgeInsets.symmetric(
                      vertical: 4,
                      horizontal: 8,
                    ),
                    elevation: 0,
                    color: Colors.blue[50],
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(color: Colors.blue[100]!),
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.blue[100],
                        child: Text(
                          group.length.toString(),
                          style: TextStyle(
                            color: Colors.blue[800],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      title: Text(
                        'Kelurahan ${first.desa ?? '-'}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text('Kecamatan ${first.kecamatan ?? '-'}'),
                      trailing: const Icon(Icons.layers, color: Colors.blue),
                      onTap: () {
                        Navigator.pop(modalContext);
                        widget.onMultiplePolygonsSelected?.call(group);
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
