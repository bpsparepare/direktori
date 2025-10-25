import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../../data/repositories/map_repository_impl.dart';
import '../../data/models/direktori_model.dart';
import '../../domain/usecases/get_initial_map_config.dart';
import '../../domain/usecases/get_places.dart';
import '../../domain/usecases/get_first_polygon_meta_from_geojson.dart';
import '../../domain/usecases/get_all_polygons_meta_from_geojson.dart';
import '../widgets/map_view.dart';
import '../widgets/map_controls.dart';
import '../../domain/entities/place.dart';
import '../bloc/map_bloc.dart';
import '../bloc/map_event.dart';
import '../bloc/map_state.dart';

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
              // appBar: AppBar(title: const Text('Direktori Map')),
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
                        child: GestureDetector(
                          onTap: () {
                            // Tap anywhere on card to close (optional)
                          },
                          child: Card(
                            elevation: 6,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Place information section
                                Padding(
                                  padding: const EdgeInsets.all(12.0),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Icon(
                                        Icons.place,
                                        color: Colors.red,
                                      ),
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
                                            Text(
                                              state.selectedPlace!.description,
                                            ),
                                          ],
                                        ),
                                      ),
                                      // Improved close button with larger touch target
                                      Container(
                                        width: 48,
                                        height: 48,
                                        decoration: BoxDecoration(
                                          color: Colors.grey.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(
                                            24,
                                          ),
                                        ),
                                        child: IconButton(
                                          icon: const Icon(Icons.close),
                                          iconSize: 20,
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(
                                            minWidth: 48,
                                            minHeight: 48,
                                          ),
                                          onPressed: () {
                                            print(
                                              'DEBUG: Close button pressed',
                                            ); // Debug log
                                            context.read<MapBloc>().add(
                                              const PlaceCleared(),
                                            );
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Action buttons section
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade50,
                                    borderRadius: const BorderRadius.only(
                                      bottomLeft: Radius.circular(12),
                                      bottomRight: Radius.circular(12),
                                    ),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12.0),
                                    child: Row(
                                      children: [
                                        // Zoom to location button
                                        Expanded(
                                          child: ElevatedButton.icon(
                                            onPressed: () {
                                              // Zoom to the selected place location
                                              mapController?.move(
                                                state.selectedPlace!.position,
                                                18.0, // High zoom level for detailed view
                                              );
                                            },
                                            icon: const Icon(
                                              Icons.zoom_in,
                                              size: 18,
                                            ),
                                            label: const Text('Zoom To'),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.blue,
                                              foregroundColor: Colors.white,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 16,
                                                    vertical: 12,
                                                  ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        // Navigate to location button
                                        Expanded(
                                          child: ElevatedButton.icon(
                                            onPressed: () async {
                                              final place =
                                                  state.selectedPlace!;
                                              final lat =
                                                  place.position.latitude;
                                              final lng =
                                                  place.position.longitude;

                                              // Create Google Maps URL
                                              final googleMapsUrl = Uri.parse(
                                                'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng',
                                              );

                                              try {
                                                if (await canLaunchUrl(
                                                  googleMapsUrl,
                                                )) {
                                                  await launchUrl(
                                                    googleMapsUrl,
                                                    mode: LaunchMode
                                                        .externalApplication,
                                                  );
                                                } else {
                                                  // Fallback to generic maps URL
                                                  final fallbackUrl = Uri.parse(
                                                    'https://maps.google.com/?q=$lat,$lng',
                                                  );
                                                  await launchUrl(fallbackUrl);
                                                }
                                              } catch (e) {
                                                // Show error message
                                                if (context.mounted) {
                                                  ScaffoldMessenger.of(
                                                    context,
                                                  ).showSnackBar(
                                                    const SnackBar(
                                                      content: Text(
                                                        'Tidak dapat membuka aplikasi navigasi',
                                                      ),
                                                      backgroundColor:
                                                          Colors.red,
                                                    ),
                                                  );
                                                }
                                              }
                                            },
                                            icon: const Icon(
                                              Icons.navigation,
                                              size: 18,
                                            ),
                                            label: const Text('Navigate'),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.green,
                                              foregroundColor: Colors.white,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 16,
                                                    vertical: 12,
                                                  ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
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
              'Tambah/Edit Direktori',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),

            // Menu options
            ListTile(
              leading: const Icon(Icons.add_business, color: Colors.green),
              title: const Text('Tambah Direktori Baru'),
              subtitle: const Text('Buat entri direktori baru di lokasi ini'),
              onTap: () {
                Navigator.pop(context);
                _showAddDirektoriForm(context, point);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_location, color: Colors.blue),
              title: const Text('Update Koordinat Direktori'),
              subtitle: const Text(
                'Pilih direktori yang sudah ada untuk diupdate koordinatnya',
              ),
              onTap: () {
                Navigator.pop(context);
                _showSelectExistingDirektori(context, point);
              },
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _showNavigasiDialog(BuildContext context, LatLng point) {
    // TODO: Implement navigasi functionality
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Fitur Navigasi akan segera hadir')),
    );
  }

  void _showAddDirektoriForm(BuildContext context, LatLng point) {
    final TextEditingController namaUsahaController = TextEditingController();
    final TextEditingController alamatController = TextEditingController();
    final TextEditingController pemilikController = TextEditingController();
    final TextEditingController nomorTeleponController =
        TextEditingController();

    // Store the ScaffoldMessenger and MapBloc references before showing dialog
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final mapBloc = context.read<MapBloc>();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Tambah Direktori Baru'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Koordinat (read-only)
              const Text(
                'Koordinat:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text('Latitude: ${point.latitude.toStringAsFixed(6)}'),
              Text('Longitude: ${point.longitude.toStringAsFixed(6)}'),
              const SizedBox(height: 16),

              // Nama Usaha (required)
              TextField(
                controller: namaUsahaController,
                decoration: const InputDecoration(
                  labelText: 'Nama Usaha *',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),

              // Alamat
              TextField(
                controller: alamatController,
                decoration: const InputDecoration(
                  labelText: 'Alamat',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 12),

              // Pemilik
              TextField(
                controller: pemilikController,
                decoration: const InputDecoration(
                  labelText: 'Pemilik',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),

              // Nomor Telepon
              TextField(
                controller: nomorTeleponController,
                decoration: const InputDecoration(
                  labelText: 'Nomor Telepon',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.phone,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () {
              if (namaUsahaController.text.trim().isEmpty) {
                scaffoldMessenger.showSnackBar(
                  const SnackBar(
                    content: Text('Nama usaha harus diisi'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              // Store MapBloc reference before closing dialog
              // final mapBloc = context.read<MapBloc>(); // Moved to top of method
              
              Navigator.of(dialogContext).pop();
              _saveDirektori(
                context,
                point,
                namaUsahaController.text.trim(),
                alamatController.text.trim(),
                pemilikController.text.trim(),
                nomorTeleponController.text.trim(),
                scaffoldMessenger,
                mapBloc,
              );
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  void _showSelectExistingDirektori(BuildContext context, LatLng point) {
    final TextEditingController searchController = TextEditingController();
    List<DirektoriModel> searchResults = [];
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Pilih Direktori untuk Update Koordinat'),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: Column(
              children: [
                // Koordinat yang akan diset
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Koordinat yang akan diset:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text('Latitude: ${point.latitude.toStringAsFixed(6)}'),
                      Text('Longitude: ${point.longitude.toStringAsFixed(6)}'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Search field
                TextField(
                  controller: searchController,
                  decoration: const InputDecoration(
                    labelText: 'Cari nama usaha',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (query) {
                    if (query.length >= 3) {
                      _searchDirectories(query, setState, (results, loading) {
                        searchResults = results;
                        isLoading = loading;
                      }, context);
                    } else {
                      setState(() {
                        searchResults = [];
                        isLoading = false;
                      });
                    }
                  },
                ),
                const SizedBox(height: 16),

                // Results
                Expanded(
                  child: isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : searchResults.isEmpty
                      ? const Center(
                          child: Text(
                            'Ketik minimal 3 karakter untuk mencari direktori',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          itemCount: searchResults.length,
                          itemBuilder: (context, index) {
                            final directory = searchResults[index];
                            return ListTile(
                              title: Text(directory.namaUsaha),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (directory.alamat != null)
                                    Text(directory.alamat!),
                                  Text(
                                    'ID SLS: ${directory.idSls}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                              trailing: const Icon(Icons.arrow_forward_ios),
                              onTap: () {
                                Navigator.of(dialogContext).pop();
                                _updateDirectoryCoordinates(
                                  context,
                                  directory,
                                  point,
                                );
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Batal'),
            ),
          ],
        ),
      ),
    );
  }

  void _searchDirectories(
    String query,
    StateSetter setState,
    Function(List<DirektoriModel>, bool) onResult,
    BuildContext context,
  ) async {
    setState(() {
      onResult([], true); // Set loading
    });

    try {
      final repository = MapRepositoryImpl();
      final results = await repository.searchDirectoriesWithoutCoordinates(
        query,
      );
      setState(() {
        onResult(results, false); // Set results, stop loading
      });
    } catch (e) {
      setState(() {
        onResult([], false); // Clear results, stop loading
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error mencari direktori: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _updateDirectoryCoordinates(
    BuildContext context,
    DirektoriModel directory,
    LatLng point,
  ) async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Konfirmasi Update'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Update koordinat untuk "${directory.namaUsaha}"?'),
            const SizedBox(height: 8),
            Text('Latitude: ${point.latitude.toStringAsFixed(6)}'),
            Text('Longitude: ${point.longitude.toStringAsFixed(6)}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Update'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final repository = MapRepositoryImpl();
        final success = await repository.updateDirectoryCoordinates(
          directory.id,
          point.latitude,
          point.longitude,
        );

        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Koordinat "${directory.namaUsaha}" berhasil diupdate',
              ),
              backgroundColor: Colors.green,
            ),
          );

          // Refresh the map data
          context.read<MapBloc>().add(const PlacesRequested());
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Gagal mengupdate koordinat'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _saveDirektori(
    BuildContext context,
    LatLng point,
    String namaUsaha,
    String alamat,
    String pemilik,
    String nomorTelepon,
    ScaffoldMessengerState scaffoldMessenger,
    MapBloc mapBloc,
  ) async {
    print('🔄 [DEBUG] Memulai proses penyimpanan direktori...');
    print('📍 [DEBUG] Koordinat: ${point.latitude}, ${point.longitude}');
    print('🏢 [DEBUG] Nama Usaha: $namaUsaha');
    print('📍 [DEBUG] Alamat: $alamat');
    print('👤 [DEBUG] Pemilik: $pemilik');
    print('📞 [DEBUG] Nomor Telepon: $nomorTelepon');
    
    try {
      // Find polygon at point to get idSls and nama_sls
      String idSls = '';
      String? kodePos;
      String? namaSls;
      String? alamatFromGeocode;

      print('🗺️ [DEBUG] Mencari polygon yang mengandung titik...');
      final polygons = mapBloc.state.polygonsMeta;
      print('📊 [DEBUG] Jumlah polygon tersedia: ${polygons.length}');

      for (final polygon in polygons) {
        if (_isPointInPolygon(point, polygon.points)) {
          idSls = polygon.idsls ?? '';
          namaSls = polygon.name; // Mengambil nama SLS dari polygon
          print('✅ [DEBUG] Polygon ditemukan! idSls: $idSls, nama_sls: $namaSls');
          break;
        }
      }
      
      // Reverse geocoding untuk mendapatkan alamat dan kode pos
      try {
        print('🌍 [DEBUG] Melakukan reverse geocoding...');
        List<Placemark> placemarks = await placemarkFromCoordinates(
          point.latitude, 
          point.longitude
        );
        
        if (placemarks.isNotEmpty) {
          final placemark = placemarks.first;
          alamatFromGeocode = '${placemark.street ?? ''}, ${placemark.subLocality ?? ''}, ${placemark.locality ?? ''}'.replaceAll(RegExp(r'^,\s*|,\s*$'), '').replaceAll(RegExp(r',\s*,'), ',');
          kodePos = placemark.postalCode;
          print('📍 [DEBUG] Reverse geocoding berhasil - Alamat: $alamatFromGeocode, Kode Pos: $kodePos');
        }
      } catch (e) {
        print('⚠️ [DEBUG] Reverse geocoding gagal: $e');
      }
      
      if (idSls.isEmpty) {
        print('⚠️ [DEBUG] Tidak ada polygon yang mengandung titik ini');
      }

      print('🏗️ [DEBUG] Membuat objek DirektoriModel...');
      
      // Ekstraksi kode wilayah dari idSls
      String kdProv = '';
      String kdKab = '';
      String kdKec = '';
      String kdDesa = '';
      String kdSls = '';
      
      if (idSls.isNotEmpty && idSls.length >= 14) {
        kdProv = idSls.substring(0, 2);
        kdKab = idSls.substring(2, 4);
        kdKec = idSls.substring(4, 7);
        kdDesa = idSls.substring(7, 10);
        kdSls = idSls.substring(10, 14);
        print('🗺️ [DEBUG] Kode wilayah - Prov: $kdProv, Kab: $kdKab, Kec: $kdKec, Desa: $kdDesa, SLS: $kdSls');
      }
      
      final directory = DirektoriModel(
        id: '', // Will be generated by database
        idSbr: '0', // Default value untuk data non-BPS, akan diupdate saat import BPS
        namaUsaha: namaUsaha,
        alamat: alamatFromGeocode ?? alamat, // Prioritas alamat dari geocoding, fallback ke input user
        idSls: idSls,
        kdProv: kdProv,
        kdKab: kdKab,
        kdKec: kdKec,
        kdDesa: kdDesa,
        kdSls: kdSls,
        nmSls: namaSls, // Menambahkan nama SLS
        kegiatanUsaha: const [],
        lat: point.latitude,
        long: point.longitude,
        kodePos: kodePos, // Kode pos dari reverse geocoding
        pemilik: pemilik,
        nomorTelepon: nomorTelepon,
      );

      print('💾 [DEBUG] Menyimpan ke database...');
      final repository = MapRepositoryImpl();
      final success = await repository.insertDirectory(directory);

      print('📊 [DEBUG] Hasil penyimpanan: ${success ? "BERHASIL" : "GAGAL"}');

      if (success) {
        print('✅ [DEBUG] Direktori berhasil disimpan, menampilkan SnackBar sukses');
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text('Direktori "$namaUsaha" berhasil disimpan'),
            backgroundColor: Colors.green,
          ),
        );

        print('🔄 [DEBUG] Memuat ulang data peta...');
        // Refresh the map data dengan delay kecil untuk memastikan database sudah commit
        await Future.delayed(const Duration(milliseconds: 500));
        mapBloc.add(const PlacesRequested());
        
        // Juga clear temporary marker jika ada
        mapBloc.add(const TemporaryMarkerRemoved());
      } else {
        print('❌ [DEBUG] Penyimpanan gagal, menampilkan SnackBar error');
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text('Gagal menyimpan direktori'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e, stackTrace) {
      print('💥 [DEBUG] Exception terjadi: $e');
      print('📋 [DEBUG] Stack trace: $stackTrace');
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
    
    print('🏁 [DEBUG] Proses penyimpanan direktori selesai');
  }
}
