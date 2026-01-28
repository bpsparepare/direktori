import 'dart:async';
import 'package:flutter/material.dart';
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
  });

  @override
  State<MapControls> createState() => _MapControlsState();
}

class _MapControlsState extends State<MapControls> {
  bool _isLoadingLocation = false;
  String _appVersion = '';
  bool _hasPromptedDownload = false;
  StreamSubscription<Position>? _positionStreamSubscription;

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
