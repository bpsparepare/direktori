import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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
        create: (_) => MapBloc(
          getInitialMapConfig: GetInitialMapConfig(MapRepositoryImpl()),
          getPlaces: GetPlaces(MapRepositoryImpl()),
          getFirstPolygonMeta: GetFirstPolygonMetaFromGeoJson(MapRepositoryImpl()),
          getAllPolygonsMeta: GetAllPolygonsMetaFromGeoJson(MapRepositoryImpl()),
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
                      config: config,
                      places: state.places,
                      polygon: state.polygon,
                      polygonLabel: state.polygonLabel,
                      onPlaceTap: (p) =>
                          context.read<MapBloc>().add(PlaceSelected(p)),
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
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.label, size: 18, color: Colors.blueAccent),
                                    const SizedBox(width: 6),
                                    Text(state.selectedPolygonMeta!.name ?? '-', style: const TextStyle(fontWeight: FontWeight.w600)),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text('Kecamatan: ${state.selectedPolygonMeta!.kecamatan ?? '-'}'),
                                Text('Desa/Kelurahan: ${state.selectedPolygonMeta!.desa ?? '-'}'),
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
                            builder: (_) {
                              String query = '';
                              return StatefulBuilder(
                                builder: (ctx, setModalState) {
                                  final filtered = list.where((p) {
                                    final q = query.toLowerCase();
                                    final n = (p.name ?? '').toLowerCase();
                                    final kc = (p.kecamatan ?? '').toLowerCase();
                                    final ds = (p.desa ?? '').toLowerCase();
                                    return n.contains(q) || kc.contains(q) || ds.contains(q);
                                  }).toList();
                                  return SafeArea(
                                    child: Column(
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.all(12.0),
                                          child: TextField(
                                            autofocus: true,
                                            decoration: const InputDecoration(
                                              prefixIcon: Icon(Icons.search),
                                              hintText: 'Cari nmsls / nmkec / nmdesa',
                                              border: OutlineInputBorder(),
                                            ),
                                            onChanged: (v) => setModalState(() => query = v),
                                          ),
                                        ),
                                        Expanded(
                                          child: ListView.builder(
                                            itemCount: filtered.length,
                                            itemBuilder: (ctx2, i) {
                                              final item = filtered[i];
                                              final idx = list.indexOf(item);
                                              final name = item.name ?? 'Polygon ${idx + 1}';
                                              final subtitle = '${item.kecamatan ?? '-'} • ${item.desa ?? '-'}';
                                              return ListTile(
                                                leading: const Icon(Icons.polyline),
                                                title: Text(name),
                                                subtitle: Text(subtitle),
                                                onTap: () {
                                                  Navigator.of(ctx2).pop();
                                                  bloc.add(PolygonSelectedByIndex(idx));
                                                },
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
}