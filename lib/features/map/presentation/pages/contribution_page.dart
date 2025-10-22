import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../bloc/map_bloc.dart';
import '../bloc/map_state.dart';
import '../bloc/map_event.dart';
import '../widgets/map_view.dart';
import '../../domain/entities/polygon_data.dart';
import '../../data/repositories/map_repository_impl.dart';
import '../../domain/usecases/get_initial_map_config.dart';
import '../../domain/usecases/get_places.dart';
import '../../domain/usecases/get_first_polygon_meta_from_geojson.dart';
import '../../domain/usecases/get_all_polygons_meta_from_geojson.dart';

class ContributionPage extends StatefulWidget {
  const ContributionPage({super.key});

  @override
  State<ContributionPage> createState() => _ContributionPageState();
}

class _ContributionPageState extends State<ContributionPage> {
  final MapController _mapController = MapController();
  final DraggableScrollableController _scrollController = DraggableScrollableController();

  void _showContextMenu(LatLng position) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.info),
              title: const Text('Info Lokasi'),
              onTap: () {
                Navigator.pop(context);
                _showInfoDialog(position);
              },
            ),
            ListTile(
              leading: const Icon(Icons.add_location),
              title: const Text('Tambah Direktori'),
              onTap: () {
                Navigator.pop(context);
                _showTambahDirektoriDialog(position);
              },
            ),
            ListTile(
              leading: const Icon(Icons.navigation),
              title: const Text('Navigasi'),
              onTap: () {
                Navigator.pop(context);
                _showNavigasiDialog(position);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showInfoDialog(LatLng position) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Info Lokasi'),
        content: Text('Koordinat: ${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  void _showTambahDirektoriDialog(LatLng position) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tambah Direktori'),
        content: Text('Tambah direktori di koordinat: ${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tambah'),
          ),
        ],
      ),
    );
  }

  void _showNavigasiDialog(LatLng position) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Navigasi'),
        content: Text('Navigasi ke koordinat: ${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Mulai'),
          ),
        ],
      ),
    );
  }

  bool _isPointInPolygon(LatLng point, List<LatLng> polygon) {
    int intersectCount = 0;
    for (int j = 0, i = polygon.length - 1; j < polygon.length; i = j++) {
      if (((polygon[i].latitude > point.latitude) != (polygon[j].latitude > point.latitude)) &&
          (point.longitude < (polygon[j].longitude - polygon[i].longitude) * (point.latitude - polygon[i].latitude) / (polygon[j].latitude - polygon[i].latitude) + polygon[i].longitude)) {
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
                    // Full screen map
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
                        _showContextMenu(point);
                      },
                      onPolygonSelected: (index) {
                        context.read<MapBloc>().add(
                          PolygonSelectedByIndex(index),
                        );
                      },
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
                                    Icon(Icons.add_circle_outline, color: Colors.green),
                                    SizedBox(width: 12),
                                    Text(
                                      'Kontribusi',
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
                                    // Placeholder untuk fitur kontribusi
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
                                            Icons.add_circle_outline,
                                            size: 48,
                                            color: Colors.grey[400],
                                          ),
                                          const SizedBox(height: 12),
                                          Text(
                                            'Fitur kontribusi akan segera hadir',
                                            style: TextStyle(
                                              fontSize: 16,
                                              color: Colors.grey[600],
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            'Anda akan dapat menambahkan direktori baru dan berkontribusi pada peta',
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
              default:
                return const SizedBox.shrink();
            }
          },
        ),
      ),
    );
  }
}