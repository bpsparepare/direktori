import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
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
import '../widgets/map_controls.dart';
import '../../domain/entities/place.dart';

class MapPage extends StatelessWidget {
  final MapController? mapController;

  const MapPage({super.key, this.mapController});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MapBloc, MapState>(
      builder: (context, state) {
        switch (state.status) {
          case MapStatus.loading:
            return const Center(child: CircularProgressIndicator());
          case MapStatus.failure:
            return Center(child: Text(state.error ?? 'Terjadi kesalahan'));
          case MapStatus.success:
            final config = state.config!;
            return Scaffold(
              appBar: AppBar(title: const Text('Direktori Map')),
              body: Stack(
                children: [
                  MapView(
                    config: config,
                    places: state.places,
                    polygon: state.polygon,
                    polygonLabel: state.polygonLabel,
                    temporaryMarker: state.temporaryMarker,
                    polygonsMeta: state.polygonsMeta,
                    mapController: mapController, // Pass shared MapController
                    onPlaceTap: (place) {
                      context.read<MapBloc>().add(PlaceSelected(place));
                    },
                    onLongPress: (point) {
                      context.read<MapBloc>().add(TemporaryMarkerAdded(point));
                      _showContextMenu(context, point);
                    },
                    onPolygonSelected: (index) {
                      context.read<MapBloc>().add(
                        PolygonSelectedByIndex(index),
                      );
                    },
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
                                  onPressed: () => context.read<MapBloc>().add(
                                    const PlaceCleared(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                  // Info polygon terpilih: nmsls, nmkec, nmdesa
                ],
              ),
            );
          case MapStatus.initial:
          default:
            return const SizedBox.shrink();
        }
      },
    );
  }

  void _showContextMenu(BuildContext parentContext, LatLng point) {
    showModalBottomSheet(
      context: parentContext,
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
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),

            // Menu options
            ListTile(
              leading: const Icon(Icons.info, color: Colors.blue),
              title: const Text('Info'),
              subtitle: const Text('Lihat informasi koordinat dan SLS'),
              onTap: () {
                Navigator.pop(context);
                // Ambil MapBloc dari context yang memiliki akses ke provider
                final mapBloc = parentContext.read<MapBloc>();
                parentContext.read<MapBloc>().add(
                  const TemporaryMarkerRemoved(),
                );
                _showInfoDialog(parentContext, point, mapBloc);
              },
            ),
            ListTile(
              leading: const Icon(Icons.folder_open, color: Colors.green),
              title: const Text('Tambah Direktori'),
              subtitle: const Text('Tambah direktori baru'),
              onTap: () {
                Navigator.pop(context);
                parentContext.read<MapBloc>().add(
                  const TemporaryMarkerRemoved(),
                );
                _showTambahDirektoriDialog(context, point);
              },
            ),
            ListTile(
              leading: const Icon(Icons.navigation, color: Colors.orange),
              title: const Text('Navigasi'),
              subtitle: const Text('Navigasi ke lokasi'),
              onTap: () {
                Navigator.pop(context);
                parentContext.read<MapBloc>().add(
                  const TemporaryMarkerRemoved(),
                );
                _showNavigasiDialog(context, point);
              },
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _showInfoDialog(BuildContext context, LatLng point, MapBloc mapBloc) {
    // Convert decimal coordinates to DMS format
    final String latDMS = _convertToDMS(point.latitude, true);
    final String lngDMS = _convertToDMS(point.longitude, false);

    // Use the passed MapBloc instance
    final state = mapBloc.state;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
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
            Builder(
              builder: (builderContext) {
                String? polygonInfo;
                for (final polygon in state.polygonsMeta) {
                  if (_isPointInPolygon(point, polygon.points)) {
                    polygonInfo = '${polygon.name} (${polygon.idsls})';
                    break;
                  }
                }

                return polygonInfo != null
                    ? Text('SLS: $polygonInfo')
                    : const Text('Tidak ada SLS di lokasi ini');
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              context.read<MapBloc>().add(const TemporaryMarkerRemoved());
            },
            child: const Text('Tutup'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              context.read<MapBloc>().add(const TemporaryMarkerRemoved());
              // Cari polygon di state yang sudah ada
              for (int i = 0; i < state.polygonsMeta.length; i++) {
                final polygon = state.polygonsMeta[i];
                if (_isPointInPolygon(point, polygon.points)) {
                  // Select polygon menggunakan mapBloc yang sudah diambil
                  mapBloc.add(PolygonSelectedByIndex(i));

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('SLS ${polygon.name} telah dipilih'),
                      backgroundColor: Colors.green,
                    ),
                  );
                  return;
                }
              }

              // Jika tidak ditemukan
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Tidak ada SLS di lokasi ini'),
                  backgroundColor: Colors.orange,
                ),
              );
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

  Future<String?> _findPolygonAtPoint(
    LatLng point,
    BuildContext context,
  ) async {
    try {
      final bloc = context.read<MapBloc>();
      final polygons =
          bloc.state.polygonsMeta; // Gunakan data yang sudah ada di state

      print(
        'DEBUG: _findPolygonAtPoint called with point: ${point.latitude}, ${point.longitude}',
      );
      print('DEBUG: Total polygons in state for find: ${polygons.length}');

      for (final polygon in polygons) {
        if (_isPointInPolygon(point, polygon.points)) {
          print('DEBUG: Found polygon in _findPolygonAtPoint: ${polygon.name}');
          return '${polygon.name} (${polygon.idsls})';
        }
      }
      print('DEBUG: No polygon found in _findPolygonAtPoint');
      return null;
    } catch (e) {
      print('DEBUG: Error in _findPolygonAtPoint: $e');
      return null;
    }
  }

  bool _isPointInPolygon(LatLng point, List<LatLng> polygon) {
    int intersectCount = 0;
    for (int j = 0, i = 1; i < polygon.length; j = i++) {
      if (((polygon[i].latitude > point.latitude) !=
              (polygon[j].latitude > point.latitude)) &&
          (point.longitude <
              (polygon[j].longitude - polygon[i].longitude) *
                      (point.latitude - polygon[i].latitude) /
                      (polygon[j].latitude - polygon[i].latitude) +
                  polygon[i].longitude)) {
        intersectCount++;
      }
    }
    return (intersectCount % 2) == 1;
  }

  void _selectPolygonAtPoint(BuildContext context, LatLng point) async {
    try {
      final bloc = context.read<MapBloc>();
      final polygons =
          bloc.state.polygonsMeta; // Gunakan data yang sudah ada di state

      print(
        'DEBUG: _selectPolygonAtPoint called with point: ${point.latitude}, ${point.longitude}',
      );
      print('DEBUG: Total polygons in state: ${polygons.length}');

      for (int i = 0; i < polygons.length; i++) {
        final polygon = polygons[i];
        if (_isPointInPolygon(point, polygon.points)) {
          print('DEBUG: Found polygon at index $i: ${polygon.name}');
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

      print('DEBUG: No polygon found at point');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tidak ada SLS di lokasi ini'),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (e) {
      print('DEBUG: Error in _selectPolygonAtPoint: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Terjadi kesalahan saat memilih SLS'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showTambahDirektoriDialog(BuildContext context, LatLng point) {
    // TODO: Implement tambah direktori functionality
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Fitur Tambah Direktori akan segera hadir')),
    );
  }

  void _showNavigasiDialog(BuildContext context, LatLng point) {
    // TODO: Implement navigasi functionality
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Fitur Navigasi akan segera hadir')),
    );
  }
}
