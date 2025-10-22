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

class SavedPage extends StatefulWidget {
  const SavedPage({super.key});

  @override
  State<SavedPage> createState() => _SavedPageState();
}

class _SavedPageState extends State<SavedPage> {
  final DraggableScrollableController _scrollController = 
      DraggableScrollableController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _showContextMenu(BuildContext context, LatLng point) {
    final parentContext = context;
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 20),
          ListTile(
            leading: const Icon(Icons.info, color: Colors.blue),
            title: const Text('Info Lokasi'),
            subtitle: const Text('Lihat informasi lokasi'),
            onTap: () {
              Navigator.pop(context);
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
    );
  }

  void _showInfoDialog(BuildContext context, LatLng point, MapBloc mapBloc) {
    final dialogContext = context;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Info Lokasi'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Latitude: ${point.latitude.toStringAsFixed(6)}'),
            Text('Longitude: ${point.longitude.toStringAsFixed(6)}'),
            const SizedBox(height: 16),
            BlocBuilder<MapBloc, MapState>(
              bloc: mapBloc,
              builder: (context, state) {
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
              // Cari polygon di state yang sudah ada menggunakan mapBloc.state
              final currentState = mapBloc.state;
              for (int i = 0; i < currentState.polygonsMeta.length; i++) {
                final polygon = currentState.polygonsMeta[i];
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

  void _showTambahDirektoriDialog(BuildContext context, LatLng point) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tambah Direktori'),
        content: Text(
          'Fitur tambah direktori akan segera hadir!\n\n'
          'Lokasi: ${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showNavigasiDialog(BuildContext context, LatLng point) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Navigasi'),
        content: Text(
          'Fitur navigasi akan segera hadir!\n\n'
          'Tujuan: ${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  bool _isPointInPolygon(LatLng point, List<LatLng> polygon) {
    int intersectCount = 0;
    for (int j = 0, i = polygon.length - 1; j < polygon.length; i = j++) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                    // Background map - peta penuh
                    MapView(
                      config: config,
                      places: state.places,
                      polygon: state.polygon,
                      polygonLabel: state.polygonLabel,
                      temporaryMarker: state.temporaryMarker,
                      polygonsMeta: state.polygonsMeta,
                      onPlaceTap: (place) {
                        context.read<MapBloc>().add(PlaceSelected(place));
                      },
                      onLongPress: (point) {
                        context.read<MapBloc>().add(
                          TemporaryMarkerAdded(point),
                        );
                        _showContextMenu(context, point);
                      },
                      onPolygonSelected: (index) {
                        context.read<MapBloc>().add(
                          PolygonSelectedByIndex(index),
                        );
                      },
                    ),
                    
                    // Info card untuk selected place
                    if (state.selectedPlace != null)
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 200.0, left: 12.0, right: 12.0),
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
                    
                    // Draggable bottom sheet
                    DraggableScrollableSheet(
                      controller: _scrollController,
                      initialChildSize: 0.3,
                      minChildSize: 0.1,
                      maxChildSize: 0.9,
                      builder: (context, scrollController) {
                        return Container(
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(20),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black26,
                                blurRadius: 10,
                                offset: Offset(0, -2),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              // Handle bar
                              Container(
                                width: 40,
                                height: 4,
                                margin: const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  color: Colors.grey[300],
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              
                              // Header
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                                child: Row(
                                  children: [
                                    Icon(Icons.bookmark, color: Colors.blue),
                                    SizedBox(width: 12),
                                    Text(
                                      'Direktori Disimpan',
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              
                              const Divider(height: 1),
                              
                              // Content
                              Expanded(
                                child: ListView(
                                  controller: scrollController,
                                  padding: const EdgeInsets.all(20),
                                  children: [
                                    // Placeholder untuk direktori yang disimpan
                                    Container(
                                      padding: const EdgeInsets.all(20),
                                      decoration: BoxDecoration(
                                        color: Colors.grey[50],
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: Colors.grey[200]!),
                                      ),
                                      child: Column(
                                        children: [
                                          Icon(
                                            Icons.bookmark_border,
                                            size: 48,
                                            color: Colors.grey[400],
                                          ),
                                          const SizedBox(height: 12),
                                          Text(
                                            'Belum ada direktori yang disimpan',
                                            style: TextStyle(
                                              fontSize: 16,
                                              color: Colors.grey[600],
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            'Direktori yang Anda simpan akan muncul di sini',
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: Colors.grey[500],
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                );
              case MapStatus.initial:
                return const SizedBox.shrink();
            }
          },
        ),
      ),
    );
  }
}