import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/map_bloc.dart';
import '../bloc/map_event.dart';
import '../../data/repositories/map_repository_impl.dart';
import '../../data/services/bps_gc_service.dart';
import 'compass_widget.dart';
import '../../domain/entities/polygon_data.dart';
import 'map_type.dart';

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
  });

  @override
  State<MapControls> createState() => _MapControlsState();
}

class _MapControlsState extends State<MapControls> {
  bool _isLoadingLocation = false;

  @override
  void initState() {
    super.initState();
    // Auto-detect location when widget is initialized
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _getCurrentLocation();
    });
  }

  Future<void> _getCurrentLocation() async {
    setState(() {
      _isLoadingLocation = true;
    });

    try {
      // Cek apakah location service aktif
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showLocationError('Layanan lokasi tidak aktif. Silakan aktifkan GPS.');
        return;
      }

      // Cek permission
      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        // Request permission
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
        // Buka pengaturan aplikasi
        await Geolocator.openAppSettings();
        return;
      }

      Position position;
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 30),
        );
      } catch (_) {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null) {
          position = last;
        } else {
          position = await Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.low,
              distanceFilter: 10,
            ),
          ).first.timeout(const Duration(seconds: 30));
        }
      }

      // Pindahkan peta ke lokasi saat ini
      final currentLocation = LatLng(position.latitude, position.longitude);
      widget.mapController.move(
        currentLocation,
        15.0, // Zoom level untuk lokasi saat ini
      );

      // Update location marker via callback
      if (widget.onLocationUpdate != null) {
        widget.onLocationUpdate!(currentLocation);
      }

      // Tampilkan pesan sukses
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Lokasi berhasil ditemukan'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      String errorMessage = 'Gagal mendapatkan lokasi';

      if (e.toString().contains('location_service_disabled')) {
        errorMessage = 'Layanan lokasi tidak aktif. Silakan aktifkan GPS.';
      } else if (e.toString().contains('permission_denied')) {
        errorMessage = 'Izin lokasi diperlukan untuk fitur ini.';
      } else if (e.toString().contains('timeout')) {
        errorMessage = 'Timeout mendapatkan lokasi. Coba lagi.';
      } else if (e.toString().contains('kCLErrorDomain') ||
          e.toString().contains('LOCATION UPDATE FAILURE')) {
        errorMessage = 'Lokasi belum tersedia. Coba lagi beberapa saat.';
      } else {
        errorMessage = 'Gagal mendapatkan lokasi: ${e.toString()}';
      }

      _showLocationError(errorMessage);
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingLocation = false;
        });
      }
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

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 16,
      top: 100,
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
                                label: widget.currentOffsetX.toStringAsFixed(1),
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
                                label: widget.currentOffsetY.toStringAsFixed(1),
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
            child: IconButton(
              onPressed: () {
                MapRepositoryImpl().invalidatePlacesCache();
                context.read<MapBloc>().add(const PlacesRequested());
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Marker diperbarui'),
                    duration: Duration(milliseconds: 800),
                  ),
                );
              },
              icon: const Icon(Icons.refresh, color: Colors.black87),
              tooltip: 'Refresh Marker',
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
        ],
      ),
    );
  }

  void _showPolygonSelection() async {
    if (widget.polygonsMeta.isEmpty) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true, // Memungkinkan modal full screen
      useSafeArea: true, // Menggunakan safe area
      builder: (modalContext) {
        String query = '';
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final filtered =
                widget.polygonsMeta.where((p) {
                  final q = query.toLowerCase();
                  final n = (p.name ?? '').toLowerCase();
                  final kc = (p.kecamatan ?? '').toLowerCase();
                  final ds = (p.desa ?? '').toLowerCase();
                  return n.contains(q) || kc.contains(q) || ds.contains(q);
                }).toList()..sort((a, b) {
                  // Sort by idsls field
                  final aIdsls = a.idsls ?? '';
                  final bIdsls = b.idsls ?? '';
                  return aIdsls.compareTo(bIdsls);
                });
            return DraggableScrollableSheet(
              initialChildSize: 0.9, // Mulai dengan 90% tinggi layar
              minChildSize: 0.5, // Minimum 50% tinggi layar
              maxChildSize: 0.95, // Maximum 95% tinggi layar
              expand: false,
              builder: (context, scrollController) {
                return Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                  child: Column(
                    children: [
                      // Handle bar untuk drag
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
                            const Icon(Icons.search, color: Colors.grey),
                            const SizedBox(width: 8),
                            const Text(
                              'Pilih Polygon',
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
                      // Search field
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: TextField(
                          autofocus:
                              false, // Auto focus untuk UX yang lebih baik
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.search),
                            hintText: 'Cari nmsls / nmkec / nmdesa',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: Colors.grey[50],
                          ),
                          onChanged: (v) => setModalState(() => query = v),
                        ),
                      ),
                      // Results list
                      Expanded(
                        child: ListView.builder(
                          controller:
                              scrollController, // Menggunakan scroll controller
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          itemCount: filtered.length,
                          itemBuilder: (ctx2, i) {
                            final item = filtered[i];
                            final idx = widget.polygonsMeta.indexOf(item);
                            final name = item.name ?? 'Polygon ${idx + 1}';
                            final subtitle =
                                'Kec: ${item.kecamatan ?? '-'} • Desa: ${item.desa ?? '-'}';
                            return Card(
                              margin: const EdgeInsets.symmetric(
                                vertical: 2,
                                horizontal: 8,
                              ),
                              child: ListTile(
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.blue[50],
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    Icons.polyline,
                                    color: Colors.blue[700],
                                  ),
                                ),
                                title: Text(
                                  name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                subtitle: Text(subtitle),
                                trailing: const Icon(
                                  Icons.arrow_forward_ios,
                                  size: 16,
                                ),
                                onTap: () {
                                  Navigator.of(modalContext).pop();
                                  widget.onPolygonSelected?.call(idx);
                                },
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
