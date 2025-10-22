import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:latlong2/latlong.dart';
import '../bloc/map_bloc.dart';
import '../bloc/map_event.dart';
import '../bloc/map_state.dart';
import '../../data/repositories/map_repository_impl.dart';
import '../../domain/usecases/get_initial_map_config.dart';
import '../../domain/usecases/get_places.dart';
import '../../domain/usecases/get_first_polygon_meta_from_geojson.dart';
import '../../domain/usecases/get_all_polygons_meta_from_geojson.dart';
import '../widgets/map_view.dart';

class MapPage extends StatelessWidget {
  const MapPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Direktori Map')),
      body: BlocProvider(
        create: (_) =>
            MapBloc(
                getInitialMapConfig: GetInitialMapConfig(MapRepositoryImpl()),
                getPlaces: GetPlaces(MapRepositoryImpl()),
                getFirstPolygonMeta: GetFirstPolygonMetaFromGeoJson(
                  MapRepositoryImpl(),
                ),
                getAllPolygonsMeta: GetAllPolygonsMetaFromGeoJson(
                  MapRepositoryImpl(),
                ),
              )
              ..add(const MapInitRequested())
              ..add(const PlacesRequested())
              ..add(const PolygonRequested())
              ..add(const PolygonsListRequested()),
        child: BlocBuilder<MapBloc, MapState>(
          builder: (context, state) {
            switch (state.status) {
              case MapStatus.loading:
                return const Center(child: CircularProgressIndicator());
              case MapStatus.failure:
                return Center(child: Text(state.error ?? 'Terjadi kesalahan'));
              case MapStatus.success:
                final config = state.config!;
                return Stack(
                  children: [
                    MapView(
                      config: state.config!,
                      places: state.places,
                      polygon: state.polygon,
                      polygonLabel: state.polygonLabel,
                      temporaryMarker: state.temporaryMarker,
                      onPlaceTap: (p) =>
                          context.read<MapBloc>().add(PlaceSelected(p)),
                      onLongPress: (point) => _showContextMenu(context, point),
                    ),
                    if (state.selectedPlace != null)
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Card(
                            elevation: 6,
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.place, color: Colors.red),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          state.selectedPlace!.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(state.selectedPlace!.description),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.close),
                                    onPressed: () => context
                                        .read<MapBloc>()
                                        .add(const PlaceCleared()),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    // Info polygon terpilih: nmsls, nmkec, nmdesa
                    if (state.selectedPolygonMeta != null)
                      Positioned(
                        left: 16,
                        bottom: state.selectedPlace != null ? 96 : 16,
                        child: Card(
                          elevation: 4,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.label,
                                      size: 18,
                                      color: Colors.blueAccent,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      state.selectedPolygonMeta!.name ?? '-',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Kecamatan: ${state.selectedPolygonMeta!.kecamatan ?? '-'}',
                                ),
                                Text(
                                  'Desa/Kelurahan: ${state.selectedPolygonMeta!.desa ?? '-'}',
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    // FAB: pilih polygon
                    Positioned(
                      right: 16,
                      bottom: state.selectedPlace != null ? 96 : 16,
                      child: FloatingActionButton.extended(
                        onPressed: () async {
                          final bloc = context.read<MapBloc>();
                          final list = bloc.state.polygonsMeta;
                          await showModalBottomSheet(
                            context: context,
                            isScrollControlled:
                                true, // Memungkinkan modal full screen
                            useSafeArea: true, // Menggunakan safe area
                            builder: (_) {
                              String query = '';
                              return StatefulBuilder(
                                builder: (ctx, setModalState) {
                                  final filtered =
                                      list.where((p) {
                                        final q = query.toLowerCase();
                                        final n = (p.name ?? '').toLowerCase();
                                        final kc = (p.kecamatan ?? '')
                                            .toLowerCase();
                                        final ds = (p.desa ?? '').toLowerCase();
                                        return n.contains(q) ||
                                            kc.contains(q) ||
                                            ds.contains(q);
                                      }).toList()..sort((a, b) {
                                        // Sort by idsls field
                                        final aIdsls = a.idsls ?? '';
                                        final bIdsls = b.idsls ?? '';
                                        return aIdsls.compareTo(bIdsls);
                                      });
                                  return DraggableScrollableSheet(
                                    initialChildSize:
                                        0.9, // Mulai dengan 90% tinggi layar
                                    minChildSize:
                                        0.5, // Minimum 50% tinggi layar
                                    maxChildSize:
                                        0.95, // Maximum 95% tinggi layar
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
                                              margin:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 8,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.grey[300],
                                                borderRadius:
                                                    BorderRadius.circular(2),
                                              ),
                                            ),
                                            // Header
                                            Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 16,
                                                    vertical: 8,
                                                  ),
                                              child: Row(
                                                children: [
                                                  const Icon(
                                                    Icons.search,
                                                    color: Colors.grey,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  const Text(
                                                    'Pilih Polygon',
                                                    style: TextStyle(
                                                      fontSize: 18,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                  const Spacer(),
                                                  IconButton(
                                                    onPressed: () =>
                                                        Navigator.pop(context),
                                                    icon: const Icon(
                                                      Icons.close,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            // Search field
                                            Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 16,
                                                    vertical: 8,
                                                  ),
                                              child: TextField(
                                                autofocus:
                                                    false, // Auto focus untuk UX yang lebih baik
                                                decoration: InputDecoration(
                                                  prefixIcon: const Icon(
                                                    Icons.search,
                                                  ),
                                                  hintText:
                                                      'Cari nmsls / nmkec / nmdesa',
                                                  border: OutlineInputBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                  ),
                                                  filled: true,
                                                  fillColor: Colors.grey[50],
                                                ),
                                                onChanged: (v) => setModalState(
                                                  () => query = v,
                                                ),
                                              ),
                                            ),
                                            // Results list
                                            Expanded(
                                              child: ListView.builder(
                                                controller:
                                                    scrollController, // Menggunakan scroll controller
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                    ),
                                                itemCount: filtered.length,
                                                itemBuilder: (ctx2, i) {
                                                  final item = filtered[i];
                                                  final idx = list.indexOf(
                                                    item,
                                                  );
                                                  final name =
                                                      item.name ??
                                                      'Polygon ${idx + 1}';
                                                  final subtitle =
                                                      '${item.kecamatan ?? '-'} • ${item.desa ?? '-'}';
                                                  return Card(
                                                    margin:
                                                        const EdgeInsets.symmetric(
                                                          vertical: 2,
                                                          horizontal: 8,
                                                        ),
                                                    child: ListTile(
                                                      leading: Container(
                                                        padding:
                                                            const EdgeInsets.all(
                                                              8,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color:
                                                              Colors.blue[50],
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                8,
                                                              ),
                                                        ),
                                                        child: Icon(
                                                          Icons.polyline,
                                                          color:
                                                              Colors.blue[700],
                                                        ),
                                                      ),
                                                      title: Text(
                                                        name,
                                                        style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.w500,
                                                        ),
                                                      ),
                                                      subtitle: Text(subtitle),
                                                      trailing: const Icon(
                                                        Icons.arrow_forward_ios,
                                                        size: 16,
                                                      ),
                                                      onTap: () {
                                                        Navigator.of(
                                                          ctx2,
                                                        ).pop();
                                                        bloc.add(
                                                          PolygonSelectedByIndex(
                                                            idx,
                                                          ),
                                                        );
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
                        },
                        icon: const Icon(Icons.select_all),
                        label: const Text('Pilih Polygon'),
                      ),
                    ),
                  ],
                );
              case MapStatus.initial:
              default:
                return const SizedBox.shrink();
            }
          },
        ),
      ),
    );
  }

  void _showContextMenu(BuildContext context, LatLng point) {
    // Set temporary marker
    context.read<MapBloc>().add(TemporaryMarkerSet(point));
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            
            // Title
            const Text(
              'Pilih Aksi',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            
            // Menu options
            ListTile(
              leading: const Icon(Icons.info, color: Colors.blue),
              title: const Text('Info'),
              subtitle: const Text('Lihat informasi koordinat dan SLS'),
              onTap: () {
                Navigator.pop(context);
                _showInfoDialog(context, point);
              },
            ),
            ListTile(
              leading: const Icon(Icons.folder_open, color: Colors.green),
              title: const Text('Tambah Direktori'),
              subtitle: const Text('Tambah direktori baru'),
              onTap: () {
                Navigator.pop(context);
                _showTambahDirektoriDialog(context, point);
              },
            ),
            ListTile(
              leading: const Icon(Icons.navigation, color: Colors.orange),
              title: const Text('Navigasi'),
              subtitle: const Text('Navigasi ke lokasi'),
              onTap: () {
                Navigator.pop(context);
                _showNavigasiDialog(context, point);
              },
            ),
            
            const SizedBox(height: 20),
          ],
        ),
      ),
    ).whenComplete(() {
      // Clear temporary marker when bottom sheet is closed
      context.read<MapBloc>().add(const TemporaryMarkerCleared());
    });
  }

  void _showInfoDialog(BuildContext context, LatLng point) {
    // Convert decimal coordinates to DMS format
    final String latDMS = _convertToDMS(point.latitude, true);
    final String lngDMS = _convertToDMS(point.longitude, false);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Informasi Koordinat'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Koordinat Desimal:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text('Latitude: ${point.latitude.toStringAsFixed(6)}'),
            Text('Longitude: ${point.longitude.toStringAsFixed(6)}'),
            const SizedBox(height: 16),
            
            const Text(
              'Koordinat DMS:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text('Latitude: $latDMS'),
            Text('Longitude: $lngDMS'),
            const SizedBox(height: 16),
            
            const Text(
              'SLS Terpilih:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            FutureBuilder<String?>(
              future: _findPolygonAtPoint(point, context),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Row(
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 8),
                      Text('Mencari SLS...'),
                    ],
                  );
                } else if (snapshot.hasData && snapshot.data != null) {
                  return Text('SLS: ${snapshot.data}');
                } else {
                  return const Text('Tidak ada SLS di lokasi ini');
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tutup'),
          ),
          if (context.mounted)
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                // Add a small delay to ensure dialog is closed
                await Future.delayed(const Duration(milliseconds: 100));
                if (context.mounted) {
                  _selectPolygonAtPoint(context, point);
                }
              },
              child: const Text('Pilih SLS'),
            ),
        ],
      ),
    );
  }

  String _convertToDMS(double decimal, bool isLatitude) {
    final bool isNegative = decimal < 0;
    final double absDecimal = decimal.abs();
    
    final int degrees = absDecimal.floor();
    final double minutesDecimal = (absDecimal - degrees) * 60;
    final int minutes = minutesDecimal.floor();
    final double seconds = (minutesDecimal - minutes) * 60;
    
    String direction;
    if (isLatitude) {
      direction = isNegative ? 'S' : 'N';
    } else {
      direction = isNegative ? 'W' : 'E';
    }
    
    return '${degrees}° ${minutes}\' ${seconds.toStringAsFixed(2)}" $direction';
  }

  Future<String?> _findPolygonAtPoint(LatLng point, BuildContext context) async {
    try {
      final bloc = context.read<MapBloc>();
      final polygons = bloc.state.polygonsMeta; // Gunakan data yang sudah ada di state
      
      for (final polygon in polygons) {
        if (_isPointInPolygon(point, polygon.points)) {
          return '${polygon.name} (${polygon.idsls})';
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  bool _isPointInPolygon(LatLng point, List<LatLng> polygon) {
    int intersectCount = 0;
    for (int j = 0, i = 1; i < polygon.length; j = i++) {
      if (((polygon[i].latitude > point.latitude) != (polygon[j].latitude > point.latitude)) &&
          (point.longitude < (polygon[j].longitude - polygon[i].longitude) * 
           (point.latitude - polygon[i].latitude) / (polygon[j].latitude - polygon[i].latitude) + polygon[i].longitude)) {
        intersectCount++;
      }
    }
    return (intersectCount % 2) == 1;
  }

  void _selectPolygonAtPoint(BuildContext context, LatLng point) async {
    try {
      final bloc = context.read<MapBloc>();
      final polygons = bloc.state.polygonsMeta; // Gunakan data yang sudah ada di state
      
      debugPrint('_selectPolygonAtPoint: Checking ${polygons.length} polygons for point $point');
      
      for (int i = 0; i < polygons.length; i++) {
        final polygon = polygons[i];
        if (_isPointInPolygon(point, polygon.points)) {
          debugPrint('_selectPolygonAtPoint: Found polygon at index $i: ${polygon.name}');
          
          // Select the polygon by index seperti pilih polygon biasa
          bloc.add(PolygonSelectedByIndex(i));
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('SLS ${polygon.name} telah dipilih'),
              backgroundColor: Colors.green,
            ),
          );
          return;
        }
      }
      
      debugPrint('_selectPolygonAtPoint: No polygon found at point $point');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tidak ada SLS di lokasi ini'),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (e) {
      debugPrint('_selectPolygonAtPoint: Error occurred: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Terjadi kesalahan saat memilih SLS: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showTambahDirektoriDialog(BuildContext context, LatLng point) {
    // TODO: Implement tambah direktori functionality
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Fitur Tambah Direktori akan segera hadir'),
      ),
    );
  }

  void _showNavigasiDialog(BuildContext context, LatLng point) {
    // TODO: Implement navigasi functionality
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Fitur Navigasi akan segera hadir'),
      ),
    );
  }
}