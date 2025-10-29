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
                    onPlaceDragEnd: (place, newPoint) {
                      _confirmMovePlaceAndUpdateRegional(
                        context,
                        place,
                        newPoint,
                      );
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
                                          child: LayoutBuilder(
                                            builder: (context, constraints) {
                                              final isMobile =
                                                  MediaQuery.of(
                                                    context,
                                                  ).size.width <
                                                  600;

                                              if (isMobile) {
                                                return ElevatedButton(
                                                  onPressed: () {
                                                    // Zoom to the selected place location
                                                    mapController?.move(
                                                      state
                                                          .selectedPlace!
                                                          .position,
                                                      18.0, // High zoom level for detailed view
                                                    );
                                                  },
                                                  style:
                                                      ElevatedButton.styleFrom(
                                                        backgroundColor:
                                                            Colors.blue,
                                                        foregroundColor:
                                                            Colors.white,
                                                        padding:
                                                            const EdgeInsets.all(
                                                              12,
                                                            ),
                                                        minimumSize: const Size(
                                                          48,
                                                          48,
                                                        ),
                                                      ),
                                                  child: const Icon(
                                                    Icons.zoom_in,
                                                    size: 20,
                                                  ),
                                                );
                                              } else {
                                                return ElevatedButton.icon(
                                                  onPressed: () {
                                                    // Zoom to the selected place location
                                                    mapController?.move(
                                                      state
                                                          .selectedPlace!
                                                          .position,
                                                      18.0, // High zoom level for detailed view
                                                    );
                                                  },
                                                  icon: const Icon(
                                                    Icons.zoom_in,
                                                    size: 18,
                                                  ),
                                                  label: const Text('Zoom To'),
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor:
                                                        Colors.blue,
                                                    foregroundColor:
                                                        Colors.white,
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 16,
                                                          vertical: 12,
                                                        ),
                                                  ),
                                                );
                                              }
                                            },
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        // Navigate to location button
                                        Expanded(
                                          child: LayoutBuilder(
                                            builder: (context, constraints) {
                                              final isMobile =
                                                  MediaQuery.of(
                                                    context,
                                                  ).size.width <
                                                  600;

                                              if (isMobile) {
                                                return ElevatedButton(
                                                  onPressed: () async {
                                                    final place =
                                                        state.selectedPlace!;
                                                    final lat =
                                                        place.position.latitude;
                                                    final lng = place
                                                        .position
                                                        .longitude;

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
                                                        final fallbackUrl =
                                                            Uri.parse(
                                                              'https://maps.google.com/?q=$lat,$lng',
                                                            );
                                                        await launchUrl(
                                                          fallbackUrl,
                                                        );
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
                                                  style:
                                                      ElevatedButton.styleFrom(
                                                        backgroundColor:
                                                            Colors.green,
                                                        foregroundColor:
                                                            Colors.white,
                                                        padding:
                                                            const EdgeInsets.all(
                                                              12,
                                                            ),
                                                        minimumSize: const Size(
                                                          48,
                                                          48,
                                                        ),
                                                      ),
                                                  child: const Icon(
                                                    Icons.navigation,
                                                    size: 20,
                                                  ),
                                                );
                                              } else {
                                                return ElevatedButton.icon(
                                                  onPressed: () async {
                                                    final place =
                                                        state.selectedPlace!;
                                                    final lat =
                                                        place.position.latitude;
                                                    final lng = place
                                                        .position
                                                        .longitude;

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
                                                        final fallbackUrl =
                                                            Uri.parse(
                                                              'https://maps.google.com/?q=$lat,$lng',
                                                            );
                                                        await launchUrl(
                                                          fallbackUrl,
                                                        );
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
                                                    backgroundColor:
                                                        Colors.green,
                                                    foregroundColor:
                                                        Colors.white,
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 16,
                                                          vertical: 12,
                                                        ),
                                                  ),
                                                );
                                              }
                                            },
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        // Update Regional Data button
                                        Expanded(
                                          child: LayoutBuilder(
                                            builder: (context, constraints) {
                                              final isMobile =
                                                  MediaQuery.of(
                                                    context,
                                                  ).size.width <
                                                  600;

                                              if (isMobile) {
                                                return ElevatedButton(
                                                  onPressed: () async {
                                                    final place =
                                                        state.selectedPlace!;
                                                    _updateRegionalData(
                                                      context,
                                                      place,
                                                    );
                                                  },
                                                  style:
                                                      ElevatedButton.styleFrom(
                                                        backgroundColor:
                                                            Colors.orange,
                                                        foregroundColor:
                                                            Colors.white,
                                                        padding:
                                                            const EdgeInsets.all(
                                                              12,
                                                            ),
                                                        minimumSize: const Size(
                                                          48,
                                                          48,
                                                        ),
                                                      ),
                                                  child: const Icon(
                                                    Icons.location_city,
                                                    size: 20,
                                                  ),
                                                );
                                              } else {
                                                return ElevatedButton.icon(
                                                  onPressed: () async {
                                                    final place =
                                                        state.selectedPlace!;
                                                    _updateRegionalData(
                                                      context,
                                                      place,
                                                    );
                                                  },
                                                  icon: const Icon(
                                                    Icons.location_city,
                                                    size: 18,
                                                  ),
                                                  label: const Text(
                                                    'Update Regional',
                                                  ),
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor:
                                                        Colors.orange,
                                                    foregroundColor:
                                                        Colors.white,
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 16,
                                                          vertical: 12,
                                                        ),
                                                  ),
                                                );
                                              }
                                            },
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        // Edit directory button
                                        Expanded(
                                          child: LayoutBuilder(
                                            builder: (context, constraints) {
                                              final isMobile =
                                                  MediaQuery.of(
                                                    context,
                                                  ).size.width <
                                                  600;

                                              if (isMobile) {
                                                return ElevatedButton(
                                                  onPressed: () async {
                                                    final place =
                                                        state.selectedPlace!;

                                                    // Fetch full directory data from repository
                                                    final repository =
                                                        MapRepositoryImpl();
                                                    final directory =
                                                        await repository
                                                            .getDirectoryById(
                                                              place.id,
                                                            );

                                                    if (directory != null) {
                                                      // Extract region data from place or directory
                                                      String idSls = '';
                                                      String kdProv = '';
                                                      String kdKab = '';
                                                      String kdKec = '';
                                                      String kdDesa = '';
                                                      String kdSls = '';
                                                      String? namaSls;
                                                      String? kodePos;

                                                      // Try to get region data from directory first
                                                      if (directory.idSls !=
                                                              null &&
                                                          directory
                                                              .idSls!
                                                              .isNotEmpty) {
                                                        idSls =
                                                            directory.idSls!;
                                                        if (idSls.length >=
                                                            14) {
                                                          kdProv = idSls
                                                              .substring(0, 2);
                                                          kdKab = idSls
                                                              .substring(2, 4);
                                                          kdKec = idSls
                                                              .substring(4, 7);
                                                          kdDesa = idSls
                                                              .substring(7, 10);
                                                          kdSls = idSls
                                                              .substring(
                                                                10,
                                                                14,
                                                              );
                                                        }
                                                        namaSls =
                                                            directory.nmSls;
                                                        kodePos =
                                                            directory.kodePos;
                                                      }

                                                      _showAddDirektoriForm(
                                                        context,
                                                        place.position,
                                                        idSls,
                                                        kdProv,
                                                        kdKab,
                                                        kdKec,
                                                        kdDesa,
                                                        kdSls,
                                                        namaSls,
                                                        kodePos,
                                                        null, // alamatFromGeocode
                                                        existingDirectory:
                                                            directory,
                                                      );
                                                    } else {
                                                      ScaffoldMessenger.of(
                                                        context,
                                                      ).showSnackBar(
                                                        const SnackBar(
                                                          content: Text(
                                                            'Gagal memuat data direktori untuk diedit',
                                                          ),
                                                        ),
                                                      );
                                                    }
                                                  },
                                                  style:
                                                      ElevatedButton.styleFrom(
                                                        backgroundColor:
                                                            Colors.blue,
                                                        foregroundColor:
                                                            Colors.white,
                                                        padding:
                                                            const EdgeInsets.all(
                                                              12,
                                                            ),
                                                        minimumSize: const Size(
                                                          48,
                                                          48,
                                                        ),
                                                      ),
                                                  child: const Icon(
                                                    Icons.edit,
                                                    size: 20,
                                                  ),
                                                );
                                              } else {
                                                return ElevatedButton.icon(
                                                  onPressed: () async {
                                                    final place =
                                                        state.selectedPlace!;

                                                    // Fetch full directory data from repository
                                                    final repository =
                                                        MapRepositoryImpl();
                                                    final directory =
                                                        await repository
                                                            .getDirectoryById(
                                                              place.id,
                                                            );

                                                    if (directory != null) {
                                                      // Extract region data from place or directory
                                                      String idSls = '';
                                                      String kdProv = '';
                                                      String kdKab = '';
                                                      String kdKec = '';
                                                      String kdDesa = '';
                                                      String kdSls = '';
                                                      String? namaSls;
                                                      String? kodePos;

                                                      // Try to get region data from directory first
                                                      if (directory.idSls !=
                                                              null &&
                                                          directory
                                                              .idSls!
                                                              .isNotEmpty) {
                                                        idSls =
                                                            directory.idSls!;
                                                        if (idSls.length >=
                                                            14) {
                                                          kdProv = idSls
                                                              .substring(0, 2);
                                                          kdKab = idSls
                                                              .substring(2, 4);
                                                          kdKec = idSls
                                                              .substring(4, 7);
                                                          kdDesa = idSls
                                                              .substring(7, 10);
                                                          kdSls = idSls
                                                              .substring(
                                                                10,
                                                                14,
                                                              );
                                                        }
                                                        namaSls =
                                                            directory.nmSls;
                                                        kodePos =
                                                            directory.kodePos;
                                                      }

                                                      _showAddDirektoriForm(
                                                        context,
                                                        place.position,
                                                        idSls,
                                                        kdProv,
                                                        kdKab,
                                                        kdKec,
                                                        kdDesa,
                                                        kdSls,
                                                        namaSls,
                                                        kodePos,
                                                        null, // alamatFromGeocode
                                                        existingDirectory:
                                                            directory,
                                                      );
                                                    } else {
                                                      ScaffoldMessenger.of(
                                                        context,
                                                      ).showSnackBar(
                                                        const SnackBar(
                                                          content: Text(
                                                            'Gagal memuat data direktori untuk diedit',
                                                          ),
                                                        ),
                                                      );
                                                    }
                                                  },
                                                  icon: const Icon(
                                                    Icons.edit,
                                                    size: 18,
                                                  ),
                                                  label: const Text('Edit'),
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor:
                                                        Colors.blue,
                                                    foregroundColor:
                                                        Colors.white,
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 16,
                                                          vertical: 12,
                                                        ),
                                                  ),
                                                );
                                              }
                                            },
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        // Delete or mark closed button
                                        Expanded(
                                          child: LayoutBuilder(
                                            builder: (context, constraints) {
                                              final isMobile =
                                                  MediaQuery.of(
                                                    context,
                                                  ).size.width <
                                                  600;

                                              if (isMobile) {
                                                return ElevatedButton(
                                                  onPressed: () async {
                                                    final place =
                                                        state.selectedPlace!;
                                                    final confirmed = await showDialog<bool>(
                                                      context: context,
                                                      builder: (ctx) => AlertDialog(
                                                        title: const Text(
                                                          'Konfirmasi Hapus/Tutup',
                                                        ),
                                                        content: const Text(
                                                          'Jika id_sbr = 0 (belum approve) akan dihapus. Jika sudah memiliki id_sbr, status keberadaan akan diubah menjadi kode 4 (Tutup). Lanjutkan?',
                                                        ),
                                                        actions: [
                                                          TextButton(
                                                            onPressed: () =>
                                                                Navigator.of(
                                                                  ctx,
                                                                ).pop(false),
                                                            child: const Text(
                                                              'Batal',
                                                            ),
                                                          ),
                                                          ElevatedButton(
                                                            onPressed: () =>
                                                                Navigator.of(
                                                                  ctx,
                                                                ).pop(true),
                                                            child: const Text(
                                                              'Lanjut',
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    );
                                                    if (confirmed != true)
                                                      return;
                                                    try {
                                                      final repository =
                                                          MapRepositoryImpl();
                                                      final success =
                                                          await repository
                                                              .deleteOrCloseDirectoryById(
                                                                place.id,
                                                              );
                                                      if (success) {
                                                        ScaffoldMessenger.of(
                                                          context,
                                                        ).showSnackBar(
                                                          const SnackBar(
                                                            content: Text(
                                                              'Berhasil menghapus/menutup sesuai status',
                                                            ),
                                                            backgroundColor:
                                                                Colors.green,
                                                          ),
                                                        );
                                                        // Refresh data dan tutup card
                                                        context.read<MapBloc>().add(
                                                          const PlacesRequested(),
                                                        );
                                                        context
                                                            .read<MapBloc>()
                                                            .add(
                                                              const PlaceCleared(),
                                                            );
                                                      } else {
                                                        ScaffoldMessenger.of(
                                                          context,
                                                        ).showSnackBar(
                                                          const SnackBar(
                                                            content: Text(
                                                              'Operasi gagal',
                                                            ),
                                                            backgroundColor:
                                                                Colors.red,
                                                          ),
                                                        );
                                                      }
                                                    } catch (e) {
                                                      ScaffoldMessenger.of(
                                                        context,
                                                      ).showSnackBar(
                                                        SnackBar(
                                                          content: Text(
                                                            'Error: $e',
                                                          ),
                                                          backgroundColor:
                                                              Colors.red,
                                                        ),
                                                      );
                                                    }
                                                  },
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor: Colors.red,
                                                    foregroundColor:
                                                        Colors.white,
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 16,
                                                          vertical: 12,
                                                        ),
                                                  ),
                                                  child: const Icon(
                                                    Icons.delete_forever,
                                                    size: 18,
                                                  ),
                                                );
                                              } else {
                                                return ElevatedButton.icon(
                                                  onPressed: () async {
                                                    final place =
                                                        state.selectedPlace!;
                                                    final confirmed = await showDialog<bool>(
                                                      context: context,
                                                      builder: (ctx) => AlertDialog(
                                                        title: const Text(
                                                          'Konfirmasi Hapus/Tutup',
                                                        ),
                                                        content: const Text(
                                                          'Jika id_sbr = 0 (belum approve) akan dihapus. Jika sudah memiliki id_sbr, status keberadaan akan diubah menjadi kode 4 (Tutup). Lanjutkan?',
                                                        ),
                                                        actions: [
                                                          TextButton(
                                                            onPressed: () =>
                                                                Navigator.of(
                                                                  ctx,
                                                                ).pop(false),
                                                            child: const Text(
                                                              'Batal',
                                                            ),
                                                          ),
                                                          ElevatedButton(
                                                            onPressed: () =>
                                                                Navigator.of(
                                                                  ctx,
                                                                ).pop(true),
                                                            child: const Text(
                                                              'Lanjut',
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    );
                                                    if (confirmed != true)
                                                      return;
                                                    try {
                                                      final repository =
                                                          MapRepositoryImpl();
                                                      final success =
                                                          await repository
                                                              .deleteOrCloseDirectoryById(
                                                                place.id,
                                                              );
                                                      if (success) {
                                                        ScaffoldMessenger.of(
                                                          context,
                                                        ).showSnackBar(
                                                          const SnackBar(
                                                            content: Text(
                                                              'Berhasil menghapus/menutup sesuai status',
                                                            ),
                                                            backgroundColor:
                                                                Colors.green,
                                                          ),
                                                        );
                                                        // Refresh data dan tutup card
                                                        context.read<MapBloc>().add(
                                                          const PlacesRequested(),
                                                        );
                                                        context
                                                            .read<MapBloc>()
                                                            .add(
                                                              const PlaceCleared(),
                                                            );
                                                      } else {
                                                        ScaffoldMessenger.of(
                                                          context,
                                                        ).showSnackBar(
                                                          const SnackBar(
                                                            content: Text(
                                                              'Operasi gagal',
                                                            ),
                                                            backgroundColor:
                                                                Colors.red,
                                                          ),
                                                        );
                                                      }
                                                    } catch (e) {
                                                      ScaffoldMessenger.of(
                                                        context,
                                                      ).showSnackBar(
                                                        SnackBar(
                                                          content: Text(
                                                            'Error: $e',
                                                          ),
                                                          backgroundColor:
                                                              Colors.red,
                                                        ),
                                                      );
                                                    }
                                                  },
                                                  icon: const Icon(
                                                    Icons.delete_forever,
                                                    size: 18,
                                                  ),
                                                  label: const Text(
                                                    'Hapus/Tutup',
                                                  ),
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor: Colors.red,
                                                    foregroundColor:
                                                        Colors.white,
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 16,
                                                          vertical: 12,
                                                        ),
                                                  ),
                                                );
                                              }
                                            },
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

                // Calculate region data before calling the method
                String idSls = '';
                String? namaSls;
                String? kodePos;
                String kdProv = '';
                String kdKab = '';
                String kdKec = '';
                String kdDesa = '';
                String kdSls = '';
                String? alamatFromGeocode;

                final polygons = parentContext
                    .read<MapBloc>()
                    .state
                    .polygonsMeta;
                for (final polygon in polygons) {
                  if (_isPointInPolygon(point, polygon.points)) {
                    idSls = polygon.idsls ?? '';
                    namaSls = polygon.name;
                    kodePos = polygon.kodePos;
                    break;
                  }
                }
                if (idSls.isNotEmpty && idSls.length >= 14) {
                  kdProv = idSls.substring(0, 2);
                  kdKab = idSls.substring(2, 4);
                  kdKec = idSls.substring(4, 7);
                  kdDesa = idSls.substring(7, 10);
                  kdSls = idSls.substring(10, 14);
                }

                _showAddDirektoriForm(
                  context,
                  point,
                  idSls,
                  kdProv,
                  kdKab,
                  kdKec,
                  kdDesa,
                  kdSls,
                  namaSls,
                  kodePos,
                  alamatFromGeocode,
                );
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
                // Calculate region data before calling the method
                String idSls = '';
                String? namaSls;
                String? kodePos;
                String kdProv = '';
                String kdKab = '';
                String kdKec = '';
                String kdDesa = '';
                String kdSls = '';
                String? alamatFromGeocode;

                final polygons = context.read<MapBloc>().state.polygonsMeta;
                for (final polygon in polygons) {
                  if (_isPointInPolygon(point, polygon.points)) {
                    idSls = polygon.idsls ?? '';
                    namaSls = polygon.name;
                    kodePos = polygon.kodePos;
                    break;
                  }
                }
                if (idSls.isNotEmpty && idSls.length >= 14) {
                  kdProv = idSls.substring(0, 2);
                  kdKab = idSls.substring(2, 4);
                  kdKec = idSls.substring(4, 7);
                  kdDesa = idSls.substring(7, 10);
                  kdSls = idSls.substring(10, 14);
                }

                _showAddDirektoriForm(
                  context,
                  point,
                  idSls,
                  kdProv,
                  kdKab,
                  kdKec,
                  kdDesa,
                  kdSls,
                  namaSls,
                  kodePos,
                  alamatFromGeocode,
                );
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

  void _showAddDirektoriForm(
    BuildContext context,
    LatLng point,
    String idSls,
    String kdProv,
    String kdKab,
    String kdKec,
    String kdDesa,
    String kdSls,
    String? namaSls,
    String? kodePos,
    String? alamatFromGeocode, {
    DirektoriModel? existingDirectory,
  }) {
    final namaUsahaController = TextEditingController();
    final alamatController = TextEditingController();
    final pemilikController = TextEditingController();
    final nomorTeleponController = TextEditingController();

    // Enhanced form controllers
    final namaKomersialController = TextEditingController();
    final nibController = TextEditingController();
    final emailController = TextEditingController();
    final websiteController = TextEditingController();
    final nomorWhatsappController = TextEditingController();
    final nikPemilikController = TextEditingController();
    final keteranganController = TextEditingController();
    final deskripsiBadanUsahaController = TextEditingController();

    // Dropdown variables
    // Declare dropdown variables first
    String? selectedSkalaUsaha;
    String? selectedJenisPerusahaan;
    String? selectedKeberadaanUsaha = '1'; // Default to Aktif
    String? selectedJenisKepemilikan;
    String? selectedBentukBadanHukum;
    String? selectedJaringanUsaha;
    String? selectedSektorInstitusi;
    String? selectedTahunBerdiri;
    String? selectedTenagaKerja;

    // Controller for kegiatan_usaha (jsonb array)
    final kegiatanUsahaController = TextEditingController();

    // Initialize controllers with existing data if editing
    if (existingDirectory != null) {
      namaUsahaController.text = existingDirectory.namaUsaha;
      alamatController.text = existingDirectory.alamat ?? '';
      pemilikController.text = existingDirectory.pemilik ?? '';
      nomorTeleponController.text = existingDirectory.nomorTelepon ?? '';
      namaKomersialController.text = existingDirectory.namaKomersialUsaha ?? '';
      nibController.text = existingDirectory.nib ?? '';
      emailController.text = existingDirectory.email ?? '';
      websiteController.text = existingDirectory.website ?? '';
      nomorWhatsappController.text = existingDirectory.nomorWhatsapp ?? '';
      nikPemilikController.text = existingDirectory.nikPemilik ?? '';
      keteranganController.text = existingDirectory.keterangan ?? '';
      deskripsiBadanUsahaController.text =
          existingDirectory.deskripsiBadanUsahaLainnya ?? '';

      // Set dropdown values
      selectedSkalaUsaha = existingDirectory.skalaUsaha;
      selectedJenisPerusahaan = existingDirectory.jenisPerusahaan;
      selectedKeberadaanUsaha =
          existingDirectory.keberadaanUsaha?.toString() ?? '1';
      selectedJenisKepemilikan = existingDirectory.jenisKepemilikanUsaha
          ?.toString();
      selectedBentukBadanHukum = existingDirectory.bentukBadanHukumUsaha
          ?.toString();
      selectedJaringanUsaha = existingDirectory.jaringanUsaha?.toString();
      selectedSektorInstitusi = existingDirectory.sektorInstitusi?.toString();
      selectedTahunBerdiri = existingDirectory.tahunBerdiri?.toString();
      selectedTenagaKerja = existingDirectory.tenagaKerja?.toString();
    }

    // Variables for autocomplete functionality
    List<DirektoriModel> searchResults = [];
    bool isSearching = false;
    bool showSuggestions = false;

    // Phase tracking for structured form flow
    int currentPhase = 1; // 1: Business name selection, 2: Detailed form
    bool businessNameSelected = false;
    String selectedBusinessType = ''; // 'new' or 'existing'
    DirektoriModel? selectedExistingBusiness;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (bottomSheetContext) => StatefulBuilder(
        builder: (context, setState) => DraggableScrollableSheet(
          initialChildSize: 0.9,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) => Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Column(
              children: [
                // Drag handle
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Header with close button and phase indicator
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                existingDirectory != null
                                    ? 'Edit Direktori'
                                    : currentPhase == 1
                                    ? 'Pilih Nama Usaha'
                                    : 'Detail Direktori',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (currentPhase == 2 && businessNameSelected)
                                Text(
                                  selectedBusinessType == 'new'
                                      ? 'Usaha Baru: ${namaUsahaController.text}'
                                      : 'Usaha Existing: ${selectedExistingBusiness?.namaUsaha ?? namaUsahaController.text}',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[600],
                                  ),
                                ),
                            ],
                          ),
                          IconButton(
                            onPressed: () =>
                                Navigator.of(bottomSheetContext).pop(),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      // Phase indicator
                      if (existingDirectory == null)
                        Container(
                          margin: const EdgeInsets.only(top: 12),
                          child: Row(
                            children: [
                              // Phase 1 indicator
                              Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: currentPhase >= 1
                                      ? Colors.blue
                                      : Colors.grey[300],
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    '1',
                                    style: TextStyle(
                                      color: currentPhase >= 1
                                          ? Colors.white
                                          : Colors.grey[600],
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Container(
                                  height: 2,
                                  color: currentPhase >= 2
                                      ? Colors.blue
                                      : Colors.grey[300],
                                ),
                              ),
                              // Phase 2 indicator
                              Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: currentPhase >= 2
                                      ? Colors.blue
                                      : Colors.grey[300],
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    '2',
                                    style: TextStyle(
                                      color: currentPhase >= 2
                                          ? Colors.white
                                          : Colors.grey[600],
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
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

                // Content in scrollable area
                Expanded(
                  child: SingleChildScrollView(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Always show coordinates and region info
                        const Text(
                          'Koordinat:',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text('Latitude: ${point.latitude.toStringAsFixed(6)}'),
                        Text(
                          'Longitude: ${point.longitude.toStringAsFixed(6)}',
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Informasi Wilayah:',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text('idsls: ${idSls.isNotEmpty ? idSls : "-"}'),
                        Text('kode_pos: ${kodePos ?? "-"}'),
                        const SizedBox(height: 16),

                        // Phase 1: Business name selection (only for new directories)
                        if (existingDirectory == null && currentPhase == 1) ...[
                          // Business name field with autocomplete
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Search field with improved suggestions
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  TextField(
                                    controller: namaUsahaController,
                                    decoration: InputDecoration(
                                      labelText: 'Nama Usaha *',
                                      border: const OutlineInputBorder(),
                                      suffixIcon: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (namaUsahaController
                                              .text
                                              .isNotEmpty)
                                            IconButton(
                                              icon: const Icon(
                                                Icons.clear,
                                                size: 20,
                                              ),
                                              onPressed: () {
                                                namaUsahaController.clear();
                                                setState(() {
                                                  searchResults = [];
                                                  isSearching = false;
                                                  showSuggestions = false;
                                                });
                                              },
                                            ),
                                          const Icon(Icons.search),
                                        ],
                                      ),
                                    ),
                                    onChanged: (query) {
                                      if (query.length >= 2) {
                                        setState(() {
                                          isSearching = true;
                                          showSuggestions = true;
                                        });
                                        _searchDirectories(query, setState, (
                                          results,
                                          loading,
                                        ) {
                                          searchResults = results;
                                          isSearching = loading;
                                        }, context);
                                      } else {
                                        setState(() {
                                          searchResults = [];
                                          isSearching = false;
                                          showSuggestions = false;
                                        });
                                      }
                                    },
                                  ),

                                  // Enhanced suggestions dropdown
                                  if (showSuggestions &&
                                      (isSearching || searchResults.isNotEmpty))
                                    Container(
                                      margin: const EdgeInsets.only(top: 8),
                                      child: Material(
                                        elevation: 4,
                                        borderRadius: BorderRadius.circular(8),
                                        child: Container(
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            color: Colors.white,
                                          ),
                                          constraints: const BoxConstraints(
                                            maxHeight: 400,
                                          ),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              // Header
                                              Container(
                                                padding: const EdgeInsets.all(
                                                  12,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Colors.blue.shade50,
                                                  borderRadius:
                                                      const BorderRadius.only(
                                                        topLeft:
                                                            Radius.circular(8),
                                                        topRight:
                                                            Radius.circular(8),
                                                      ),
                                                ),
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                      Icons.business,
                                                      size: 16,
                                                      color:
                                                          Colors.blue.shade700,
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Text(
                                                      'Pilih Usaha Existing atau Buat Baru',
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color: Colors
                                                            .blue
                                                            .shade700,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),

                                              // Content
                                              Flexible(
                                                child: isSearching
                                                    ? const Padding(
                                                        padding: EdgeInsets.all(
                                                          20,
                                                        ),
                                                        child: Center(
                                                          child: Row(
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .min,
                                                            children: [
                                                              SizedBox(
                                                                width: 16,
                                                                height: 16,
                                                                child:
                                                                    CircularProgressIndicator(
                                                                      strokeWidth:
                                                                          2,
                                                                    ),
                                                              ),
                                                              SizedBox(
                                                                width: 12,
                                                              ),
                                                              Text(
                                                                'Mencari usaha...',
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      )
                                                    : searchResults.isEmpty
                                                    ? Padding(
                                                        padding:
                                                            const EdgeInsets.all(
                                                              16,
                                                            ),
                                                        child: Column(
                                                          mainAxisSize:
                                                              MainAxisSize.min,
                                                          children: [
                                                            Icon(
                                                              Icons.search_off,
                                                              size: 32,
                                                              color: Colors
                                                                  .grey
                                                                  .shade400,
                                                            ),
                                                            const SizedBox(
                                                              height: 8,
                                                            ),
                                                            Text(
                                                              'Tidak ada usaha ditemukan',
                                                              style: TextStyle(
                                                                color: Colors
                                                                    .grey
                                                                    .shade600,
                                                                fontSize: 14,
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                              height: 12,
                                                            ),
                                                            ElevatedButton.icon(
                                                              onPressed: () {
                                                                setState(() {
                                                                  showSuggestions =
                                                                      false;
                                                                });
                                                              },
                                                              icon: const Icon(
                                                                Icons.add,
                                                                size: 16,
                                                              ),
                                                              label: const Text(
                                                                'Buat Usaha Baru',
                                                              ),
                                                              style: ElevatedButton.styleFrom(
                                                                backgroundColor:
                                                                    Colors
                                                                        .green,
                                                                foregroundColor:
                                                                    Colors
                                                                        .white,
                                                                padding:
                                                                    const EdgeInsets.symmetric(
                                                                      horizontal:
                                                                          16,
                                                                      vertical:
                                                                          8,
                                                                    ),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      )
                                                    : ListView.separated(
                                                        shrinkWrap: true,
                                                        itemCount:
                                                            searchResults
                                                                .length +
                                                            1,
                                                        separatorBuilder:
                                                            (context, index) =>
                                                                const Divider(
                                                                  height: 1,
                                                                ),
                                                        itemBuilder: (context, index) {
                                                          // Add "Create New" option at the top
                                                          if (index == 0) {
                                                            return Card(
                                                              margin:
                                                                  const EdgeInsets.all(
                                                                    8,
                                                                  ),
                                                              color: Colors
                                                                  .green
                                                                  .shade50,
                                                              child: ListTile(
                                                                dense: true,
                                                                leading: Container(
                                                                  padding:
                                                                      const EdgeInsets.all(
                                                                        8,
                                                                      ),
                                                                  decoration: BoxDecoration(
                                                                    color: Colors
                                                                        .green,
                                                                    borderRadius:
                                                                        BorderRadius.circular(
                                                                          20,
                                                                        ),
                                                                  ),
                                                                  child: const Icon(
                                                                    Icons.add,
                                                                    color: Colors
                                                                        .white,
                                                                    size: 16,
                                                                  ),
                                                                ),
                                                                title: Text(
                                                                  'Buat "${namaUsahaController.text}" sebagai usaha baru',
                                                                  style: const TextStyle(
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w600,
                                                                    color: Colors
                                                                        .green,
                                                                  ),
                                                                ),
                                                                subtitle: const Text(
                                                                  'Tambahkan usaha baru dengan nama ini',
                                                                  style:
                                                                      TextStyle(
                                                                        fontSize:
                                                                            12,
                                                                      ),
                                                                ),
                                                                onTap: () {
                                                                  setState(() {
                                                                    showSuggestions = false;
                                                                    businessNameSelected = true;
                                                                    selectedBusinessType = 'new';
                                                                    currentPhase = 2;
                                                                    // Clear existing business reference for new business
                                                                    selectedExistingBusiness = null;
                                                                  });
                                                                },
                                                              ),
                                                            );
                                                          }

                                                          // Existing businesses
                                                          final directory =
                                                              searchResults[index -
                                                                  1];
                                                          return Card(
                                                            margin:
                                                                const EdgeInsets.symmetric(
                                                                  horizontal: 8,
                                                                  vertical: 4,
                                                                ),
                                                            child: ListTile(
                                                              dense: true,
                                                              leading: Container(
                                                                padding:
                                                                    const EdgeInsets.all(
                                                                      8,
                                                                    ),
                                                                decoration: BoxDecoration(
                                                                  color: Colors
                                                                      .blue
                                                                      .shade100,
                                                                  borderRadius:
                                                                      BorderRadius.circular(
                                                                        20,
                                                                      ),
                                                                ),
                                                                child: Icon(
                                                                  Icons
                                                                      .business,
                                                                  color: Colors
                                                                      .blue
                                                                      .shade700,
                                                                  size: 16,
                                                                ),
                                                              ),
                                                              title: Text(
                                                                directory
                                                                    .namaUsaha,
                                                                style: const TextStyle(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                ),
                                                              ),
                                                              subtitle: Column(
                                                                crossAxisAlignment:
                                                                    CrossAxisAlignment
                                                                        .start,
                                                                children: [
                                                                  if (directory
                                                                          .alamat !=
                                                                      null)
                                                                    Text(
                                                                      directory
                                                                          .alamat!,
                                                                      style: const TextStyle(
                                                                        fontSize:
                                                                            12,
                                                                      ),
                                                                    ),
                                                                  Text(
                                                                    'ID SLS: ${directory.idSls}',
                                                                    style: TextStyle(
                                                                      fontSize:
                                                                          11,
                                                                      color: Colors
                                                                          .grey
                                                                          .shade600,
                                                                    ),
                                                                  ),
                                                                  Row(
                                                                    children: [
                                                                      Icon(
                                                                        directory.latitude !=
                                                                                    null &&
                                                                                directory.longitude !=
                                                                                    null
                                                                            ? Icons.location_on
                                                                            : Icons.location_off,
                                                                        size:
                                                                            12,
                                                                        color:
                                                                            directory.latitude !=
                                                                                    null &&
                                                                                directory.longitude !=
                                                                                    null
                                                                            ? Colors.green
                                                                            : Colors.red,
                                                                      ),
                                                                      const SizedBox(
                                                                        width:
                                                                            4,
                                                                      ),
                                                                      Text(
                                                                        directory.latitude !=
                                                                                    null &&
                                                                                directory.longitude !=
                                                                                    null
                                                                            ? 'Koordinat tersedia'
                                                                            : 'Belum ada koordinat',
                                                                        style: TextStyle(
                                                                          fontSize:
                                                                              10,
                                                                          color:
                                                                              directory.latitude !=
                                                                                      null &&
                                                                                  directory.longitude !=
                                                                                      null
                                                                              ? Colors.green
                                                                              : Colors.red,
                                                                          fontWeight:
                                                                              FontWeight.w500,
                                                                        ),
                                                                      ),
                                                                    ],
                                                                  ),
                                                                ],
                                                              ),
                                                              trailing: PopupMenuButton<String>(
                                                                icon: const Icon(
                                                                  Icons
                                                                      .more_vert,
                                                                  size: 20,
                                                                ),
                                                                onSelected: (value) {
                                                                  if (value ==
                                                                      'update') {
                                                                    Navigator.of(
                                                                      bottomSheetContext,
                                                                    ).pop();
                                                                    _updateDirectoryCoordinates(
                                                                      context,
                                                                      directory,
                                                                      point,
                                                                    );
                                                                  } else if (value ==
                                                                      'use_name') {
                                                                    // Pre-fill form with existing business data
                                                                    namaUsahaController.text = directory.namaUsaha;
                                                                    alamatController.text = directory.alamat ?? '';
                                                                    pemilikController.text = directory.pemilik ?? '';
                                                                    nomorTeleponController.text = directory.nomorTelepon ?? '';
                                                                    namaKomersialController.text = directory.namaKomersialUsaha ?? '';
                                                                    nibController.text = directory.nib ?? '';
                                                                    emailController.text = directory.email ?? '';
                                                                    websiteController.text = directory.website ?? '';
                                                                    nomorWhatsappController.text = directory.nomorWhatsapp ?? '';
                                                                    nikPemilikController.text = directory.nikPemilik ?? '';
                                                                    kegiatanUsahaController.text = directory.kegiatanUsaha.isNotEmpty 
                                                                        ? directory.kegiatanUsaha.map((k) => k['kegiatan_usaha'] ?? '').join(', ')
                                                                        : '';
                                                                    
                                                                    // Set dropdown values
                                                                    selectedSkalaUsaha = directory.skalaUsaha;
                                                                    selectedJenisPerusahaan = directory.jenisPerusahaan;
                                                                    selectedKeberadaanUsaha = directory.keberadaanUsaha?.toString();
                                                                    selectedJenisKepemilikan = directory.jenisKepemilikanUsaha?.toString();
                                                                    selectedBentukBadanHukum = directory.bentukBadanHukumUsaha?.toString();
                                                                    selectedJaringanUsaha = directory.jaringanUsaha?.toString();
                                                                    selectedSektorInstitusi = directory.sektorInstitusi?.toString();
                                                                    selectedTahunBerdiri = directory.tahunBerdiri?.toString();
                                                                    selectedTenagaKerja = directory.tenagaKerja?.toString();
                                                                    
                                                                    // Store the selected existing business for reference
                                                                    selectedExistingBusiness = directory;
                                                                    
                                                                    setState(() {
                                                                      showSuggestions = false;
                                                                      businessNameSelected = true;
                                                                      selectedBusinessType = 'existing';
                                                                      currentPhase = 2;
                                                                    });
                                                                  }
                                                                },
                                                                itemBuilder: (context) => [
                                                                  const PopupMenuItem(
                                                                    value:
                                                                        'update',
                                                                    child: Row(
                                                                      children: [
                                                                        Icon(
                                                                          Icons
                                                                              .edit_location,
                                                                          size:
                                                                              16,
                                                                        ),
                                                                        SizedBox(
                                                                          width:
                                                                              8,
                                                                        ),
                                                                        Text(
                                                                          'Update Koordinat',
                                                                        ),
                                                                      ],
                                                                    ),
                                                                  ),
                                                                  const PopupMenuItem(
                                                                    value:
                                                                        'use_name',
                                                                    child: Row(
                                                                      children: [
                                                                        Icon(
                                                                          Icons
                                                                              .content_copy,
                                                                          size:
                                                                              16,
                                                                        ),
                                                                        SizedBox(
                                                                          width:
                                                                              8,
                                                                        ),
                                                                        Text(
                                                                          'Gunakan Nama',
                                                                        ),
                                                                      ],
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                              onTap: () {
                                                                // Pre-fill form with existing business data
                                                                namaUsahaController.text = directory.namaUsaha;
                                                                alamatController.text = directory.alamat ?? '';
                                                                pemilikController.text = directory.pemilik ?? '';
                                                                nomorTeleponController.text = directory.nomorTelepon ?? '';
                                                                namaKomersialController.text = directory.namaKomersialUsaha ?? '';
                                                                nibController.text = directory.nib ?? '';
                                                                emailController.text = directory.email ?? '';
                                                                websiteController.text = directory.website ?? '';
                                                                nomorWhatsappController.text = directory.nomorWhatsapp ?? '';
                                                                nikPemilikController.text = directory.nikPemilik ?? '';
                                                                kegiatanUsahaController.text = directory.kegiatanUsaha.isNotEmpty 
                                                                    ? directory.kegiatanUsaha.map((k) => k['kegiatan_usaha'] ?? '').join(', ')
                                                                    : '';
                                                                
                                                                // Set dropdown values
                                                                selectedSkalaUsaha = directory.skalaUsaha;
                                                                selectedJenisPerusahaan = directory.jenisPerusahaan;
                                                                selectedKeberadaanUsaha = directory.keberadaanUsaha?.toString();
                                                                selectedJenisKepemilikan = directory.jenisKepemilikanUsaha?.toString();
                                                                selectedBentukBadanHukum = directory.bentukBadanHukumUsaha?.toString();
                                                                selectedJaringanUsaha = directory.jaringanUsaha?.toString();
                                                                selectedSektorInstitusi = directory.sektorInstitusi?.toString();
                                                                selectedTahunBerdiri = directory.tahunBerdiri?.toString();
                                                                selectedTenagaKerja = directory.tenagaKerja?.toString();
                                                                
                                                                // Store the selected existing business for reference
                                                                selectedExistingBusiness = directory;
                                                                
                                                                setState(() {
                                                                  showSuggestions = false;
                                                                  businessNameSelected = true;
                                                                  selectedBusinessType = 'existing';
                                                                  currentPhase = 2;
                                                                });
                                                              },
                                                            ),
                                                          );
                                                        },
                                                      ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),


                        ],

                        // Phase 2: Detailed form (for new directories or when business name is selected)
                        if ((existingDirectory == null &&
                                currentPhase == 2 &&
                                businessNameSelected) ||
                            existingDirectory != null) ...[
                          // Business name display for Phase 2
                          if (existingDirectory == null && businessNameSelected)
                            Container(
                              padding: const EdgeInsets.all(12),
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.blue.shade200),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    selectedBusinessType == 'new'
                                        ? Icons.add_business
                                        : Icons.business,
                                    color: Colors.blue,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          selectedBusinessType == 'new'
                                              ? 'Usaha Baru'
                                              : 'Usaha Existing',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.blue.shade700,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        Text(
                                          namaUsahaController.text,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      setState(() {
                                        currentPhase = 1;
                                        businessNameSelected = false;
                                        selectedBusinessType = '';
                                        selectedExistingBusiness = null;
                                      });
                                    },
                                    child: const Text('Ubah'),
                                  ),
                                ],
                              ),
                            ),

                          // Business name field for existing directory editing
                          if (existingDirectory != null)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                TextField(
                                  controller: namaUsahaController,
                                  decoration: const InputDecoration(
                                    labelText: 'Nama Usaha *',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                                const SizedBox(height: 12),
                              ],
                            ),

                          // Additional form fields
                          TextField(
                            controller: alamatController,
                            decoration: const InputDecoration(
                              labelText: 'Alamat',
                              border: OutlineInputBorder(),
                            ),
                            maxLines: 2,
                          ),
                          const SizedBox(height: 12),

                          TextField(
                            controller: pemilikController,
                            decoration: const InputDecoration(
                              labelText: 'Nama Pemilik',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),

                          TextField(
                            controller: nomorTeleponController,
                            decoration: const InputDecoration(
                              labelText: 'Nomor Telepon',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.phone,
                          ),
                          const SizedBox(height: 12),

                          TextField(
                            controller: namaKomersialController,
                            decoration: const InputDecoration(
                              labelText: 'Nama Komersial',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),

                          TextField(
                            controller: nibController,
                            decoration: const InputDecoration(
                              labelText: 'NIB (Nomor Induk Berusaha)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),

                          TextField(
                            controller: emailController,
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.emailAddress,
                          ),
                          const SizedBox(height: 12),

                          TextField(
                            controller: websiteController,
                            decoration: const InputDecoration(
                              labelText: 'Website',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.url,
                          ),
                          const SizedBox(height: 12),

                          TextField(
                            controller: nomorWhatsappController,
                            decoration: const InputDecoration(
                              labelText: 'Nomor WhatsApp',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.phone,
                          ),
                          const SizedBox(height: 12),

                          TextField(
                            controller: nikPemilikController,
                            decoration: const InputDecoration(
                              labelText: 'NIK Pemilik',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Dropdown fields
                          DropdownButtonFormField<String>(
                            value: selectedSkalaUsaha,
                            decoration: const InputDecoration(
                              labelText: 'Skala Usaha',
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: '1',
                                child: Text('Mikro'),
                              ),
                              DropdownMenuItem(
                                value: '2',
                                child: Text('Kecil'),
                              ),
                              DropdownMenuItem(
                                value: '3',
                                child: Text('Menengah'),
                              ),
                              DropdownMenuItem(
                                value: '4',
                                child: Text('Besar'),
                              ),
                            ],
                            onChanged: (value) {
                              setState(() {
                                selectedSkalaUsaha = value;
                              });
                            },
                          ),
                          const SizedBox(height: 12),

                          DropdownButtonFormField<String>(
                            value: selectedJenisPerusahaan,
                            decoration: const InputDecoration(
                              labelText: 'Jenis Perusahaan',
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: '1',
                                child: Text('Perorangan'),
                              ),
                              DropdownMenuItem(
                                value: '2',
                                child: Text('Persekutuan'),
                              ),
                              DropdownMenuItem(
                                value: '3',
                                child: Text('Perseroan Terbatas'),
                              ),
                              DropdownMenuItem(
                                value: '4',
                                child: Text('Koperasi'),
                              ),
                              DropdownMenuItem(
                                value: '5',
                                child: Text('BUMN/BUMD'),
                              ),
                              DropdownMenuItem(
                                value: '6',
                                child: Text('Lainnya'),
                              ),
                            ],
                            onChanged: (value) {
                              setState(() {
                                selectedJenisPerusahaan = value;
                              });
                            },
                          ),
                          const SizedBox(height: 12),

                          DropdownButtonFormField<String>(
                            value: selectedKeberadaanUsaha,
                            decoration: const InputDecoration(
                              labelText: 'Keberadaan Usaha',
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: '1',
                                child: Text('Ada/Aktif'),
                              ),
                              DropdownMenuItem(
                                value: '2',
                                child: Text('Sementara Tidak Ada'),
                              ),
                              DropdownMenuItem(
                                value: '3',
                                child: Text('Tidak Ditemukan'),
                              ),
                              DropdownMenuItem(
                                value: '4',
                                child: Text('Tutup Sementara'),
                              ),
                              DropdownMenuItem(
                                value: '5',
                                child: Text('Tutup'),
                              ),
                              DropdownMenuItem(
                                value: '6',
                                child: Text('Pindah Lokasi'),
                              ),
                              DropdownMenuItem(
                                value: '7',
                                child: Text('Berganti Nama'),
                              ),
                              DropdownMenuItem(
                                value: '8',
                                child: Text('Berganti Pemilik'),
                              ),
                              DropdownMenuItem(
                                value: '9',
                                child: Text('Duplikat'),
                              ),
                              DropdownMenuItem(
                                value: '10',
                                child: Text('Lainnya'),
                              ),
                            ],
                            onChanged: (value) {
                              setState(() {
                                selectedKeberadaanUsaha = value;
                              });
                            },
                          ),
                          const SizedBox(height: 12),

                          TextField(
                            controller: kegiatanUsahaController,
                            decoration: const InputDecoration(
                              labelText:
                                  'Kegiatan Usaha (pisahkan dengan koma)',
                              border: OutlineInputBorder(),
                              hintText: 'Contoh: Perdagangan, Jasa, Manufaktur',
                            ),
                            maxLines: 2,
                          ),
                          const SizedBox(height: 12),

                          DropdownButtonFormField<String>(
                            value: selectedJenisKepemilikan,
                            decoration: const InputDecoration(
                              labelText: 'Jenis Kepemilikan Usaha',
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: '1',
                                child: Text('Milik Sendiri'),
                              ),
                              DropdownMenuItem(
                                value: '2',
                                child: Text('Sewa/Kontrak'),
                              ),
                              DropdownMenuItem(
                                value: '3',
                                child: Text('Bebas Sewa'),
                              ),
                              DropdownMenuItem(
                                value: '4',
                                child: Text('Lainnya'),
                              ),
                            ],
                            onChanged: (value) {
                              setState(() {
                                selectedJenisKepemilikan = value;
                              });
                            },
                          ),
                          const SizedBox(height: 12),

                          DropdownButtonFormField<String>(
                            value: selectedBentukBadanHukum,
                            decoration: const InputDecoration(
                              labelText: 'Bentuk Badan Hukum Usaha',
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: '1',
                                child: Text('Tidak Berbadan Hukum'),
                              ),
                              DropdownMenuItem(
                                value: '2',
                                child: Text('PT (Perseroan Terbatas)'),
                              ),
                              DropdownMenuItem(
                                value: '3',
                                child: Text('CV (Commanditaire Vennootschap)'),
                              ),
                              DropdownMenuItem(
                                value: '4',
                                child: Text('Firma'),
                              ),
                              DropdownMenuItem(
                                value: '5',
                                child: Text('Koperasi'),
                              ),
                              DropdownMenuItem(
                                value: '6',
                                child: Text('Yayasan'),
                              ),
                              DropdownMenuItem(
                                value: '7',
                                child: Text('Perkumpulan'),
                              ),
                              DropdownMenuItem(value: '8', child: Text('BUMN')),
                              DropdownMenuItem(value: '9', child: Text('BUMD')),
                              DropdownMenuItem(
                                value: '10',
                                child: Text('Perusahaan Umum'),
                              ),
                              DropdownMenuItem(
                                value: '11',
                                child: Text('Perusahaan Jawatan'),
                              ),
                              DropdownMenuItem(
                                value: '12',
                                child: Text('Perusahaan Perseroan'),
                              ),
                              DropdownMenuItem(
                                value: '99',
                                child: Text('Lainnya'),
                              ),
                            ],
                            onChanged: (value) {
                              setState(() {
                                selectedBentukBadanHukum = value;
                              });
                            },
                          ),
                          const SizedBox(height: 12),

                          DropdownButtonFormField<String>(
                            value: selectedJaringanUsaha,
                            decoration: const InputDecoration(
                              labelText: 'Jaringan Usaha',
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: '1',
                                child: Text('Tidak Ada Jaringan'),
                              ),
                              DropdownMenuItem(
                                value: '2',
                                child: Text('Cabang'),
                              ),
                              DropdownMenuItem(
                                value: '3',
                                child: Text('Kantor Pusat'),
                              ),
                              DropdownMenuItem(
                                value: '4',
                                child: Text('Franchise'),
                              ),
                              DropdownMenuItem(
                                value: '5',
                                child: Text('Agen/Distributor'),
                              ),
                              DropdownMenuItem(
                                value: '6',
                                child: Text('Lainnya'),
                              ),
                            ],
                            onChanged: (value) {
                              setState(() {
                                selectedJaringanUsaha = value;
                              });
                            },
                          ),
                          const SizedBox(height: 12),

                          DropdownButtonFormField<String>(
                            value: selectedSektorInstitusi,
                            decoration: const InputDecoration(
                              labelText: 'Sektor Institusi',
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: '1',
                                child: Text('Swasta'),
                              ),
                              DropdownMenuItem(
                                value: '2',
                                child: Text('Pemerintah'),
                              ),
                              DropdownMenuItem(
                                value: '3',
                                child: Text('BUMN/BUMD'),
                              ),
                              DropdownMenuItem(
                                value: '4',
                                child: Text('Koperasi'),
                              ),
                              DropdownMenuItem(
                                value: '5',
                                child: Text('Lainnya'),
                              ),
                            ],
                            onChanged: (value) {
                              setState(() {
                                selectedSektorInstitusi = value;
                              });
                            },
                          ),
                          const SizedBox(height: 12),

                          TextField(
                            controller: keteranganController,
                            decoration: const InputDecoration(
                              labelText: 'Keterangan',
                              border: OutlineInputBorder(),
                            ),
                            maxLines: 3,
                          ),
                          const SizedBox(height: 12),

                          TextField(
                            controller: deskripsiBadanUsahaController,
                            decoration: const InputDecoration(
                              labelText: 'Deskripsi Badan Usaha',
                              border: OutlineInputBorder(),
                            ),
                            maxLines: 3,
                          ),
                          const SizedBox(height: 12),

                          const Text(
                            'Hanya nama usaha yang wajib diisi. Field lainnya opsional.',
                          ),

                          // Navigation buttons for Phase 2
                          if (existingDirectory == null && currentPhase == 2)
                            Container(
                              margin: const EdgeInsets.only(top: 16),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () {
                                        setState(() {
                                          currentPhase = 1;
                                          businessNameSelected = false;
                                          selectedBusinessType = '';
                                          selectedExistingBusiness = null;
                                        });
                                      },
                                      child: const Text('Kembali'),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    flex: 2,
                                    child: ElevatedButton(
                                      onPressed: () async {
                                        final namaUsaha = businessNameSelected
                                            ? namaUsahaController.text.trim()
                                            : namaUsahaController.text.trim();
                                        if (namaUsaha.isEmpty) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Nama usaha harus diisi',
                                              ),
                                              backgroundColor: Colors.red,
                                            ),
                                          );
                                          return;
                                        }

                                        // Show confirmation dialog
                                        final confirmed = await showDialog<bool>(
                                          context: context,
                                          builder: (dialogContext) => AlertDialog(
                                            title: const Text('Konfirmasi'),
                                            content: Text(
                                              'Apakah Anda yakin ingin menyimpan direktori "$namaUsaha"?',
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.of(
                                                  dialogContext,
                                                ).pop(false),
                                                child: const Text('Batal'),
                                              ),
                                              ElevatedButton(
                                                onPressed: () => Navigator.of(
                                                  dialogContext,
                                                ).pop(true),
                                                child: const Text('Simpan'),
                                              ),
                                            ],
                                          ),
                                        );

                                        if (confirmed == true) {
                                          Navigator.of(context).pop();
                                          final scaffoldMessenger =
                                              ScaffoldMessenger.of(context);
                                          final mapBloc = context
                                              .read<MapBloc>();

                                          await _saveDirektori(
                                            context,
                                            point,
                                            namaUsaha,
                                            alamatController.text.trim(),
                                            pemilikController.text.trim(),
                                            nomorTeleponController.text.trim(),
                                            scaffoldMessenger,
                                            mapBloc,
                                            namaKomersial:
                                                namaKomersialController.text
                                                    .trim()
                                                    .isEmpty
                                                ? null
                                                : namaKomersialController.text
                                                      .trim(),
                                            nib:
                                                nibController.text
                                                    .trim()
                                                    .isEmpty
                                                ? null
                                                : nibController.text.trim(),
                                            email:
                                                emailController.text
                                                    .trim()
                                                    .isEmpty
                                                ? null
                                                : emailController.text.trim(),
                                            website:
                                                websiteController.text
                                                    .trim()
                                                    .isEmpty
                                                ? null
                                                : websiteController.text.trim(),
                                            nomorWhatsapp:
                                                nomorWhatsappController.text
                                                    .trim()
                                                    .isEmpty
                                                ? null
                                                : nomorWhatsappController.text
                                                      .trim(),
                                            nikPemilik:
                                                nikPemilikController.text
                                                    .trim()
                                                    .isEmpty
                                                ? null
                                                : nikPemilikController.text
                                                      .trim(),
                                            keterangan:
                                                keteranganController.text
                                                    .trim()
                                                    .isEmpty
                                                ? null
                                                : keteranganController.text
                                                      .trim(),
                                            kegiatanUsaha:
                                                kegiatanUsahaController.text
                                                    .trim()
                                                    .isEmpty
                                                ? null
                                                : kegiatanUsahaController.text
                                                      .trim(),
                                            deskripsiBadanUsaha:
                                                deskripsiBadanUsahaController
                                                    .text
                                                    .trim()
                                                    .isEmpty
                                                ? null
                                                : deskripsiBadanUsahaController
                                                      .text
                                                      .trim(),
                                            skalaUsaha: selectedSkalaUsaha,
                                            jenisPerusahaan:
                                                selectedJenisPerusahaan,
                                            keberadaanUsaha:
                                                selectedKeberadaanUsaha,
                                            jenisKepemilikan:
                                                selectedJenisKepemilikan,
                                            bentukBadanHukum:
                                                selectedBentukBadanHukum,
                                            jaringanUsaha:
                                                selectedJaringanUsaha,
                                            sektorInstitusi:
                                                selectedSektorInstitusi,
                                            tahunBerdiri: selectedTahunBerdiri,
                                            tenagaKerja: selectedTenagaKerja,
                                            existingDirectory:
                                                existingDirectory,
                                          );
                                        }
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.blue,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 12,
                                        ),
                                      ),
                                      child: const Text('Simpan Direktori'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Konfirmasi pemindahan lokasi place dan update data regional jika berubah
  void _confirmMovePlaceAndUpdateRegional(
    BuildContext context,
    Place place,
    LatLng newPoint,
  ) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final mapBloc = context.read<MapBloc>();

    // Hitung data regional dari koordinat baru
    String idSls = '';
    String? kodePos;
    String? namaSls;
    String kdProv = '';
    String kdKab = '';
    String kdKec = '';
    String kdDesa = '';
    String kdSls = '';

    final polygons = mapBloc.state.polygonsMeta;
    for (final polygon in polygons) {
      if (_isPointInPolygon(newPoint, polygon.points)) {
        idSls = polygon.idsls ?? '';
        namaSls = polygon.name;
        kodePos = polygon.kodePos;

        if (idSls.isNotEmpty && idSls.length >= 14) {
          kdProv = idSls.substring(0, 2);
          kdKab = idSls.substring(2, 4);
          kdKec = idSls.substring(4, 7);
          kdDesa = idSls.substring(7, 10);
          kdSls = idSls.substring(10, 14);
        }
        break;
      }
    }

    // Tampilkan dialog konfirmasi
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Konfirmasi Pemindahan Lokasi'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Pindahkan "${place.name}" ke lokasi baru?'),
            const SizedBox(height: 8),
            Text('Latitude: ${newPoint.latitude.toStringAsFixed(6)}'),
            Text('Longitude: ${newPoint.longitude.toStringAsFixed(6)}'),
            if (idSls.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text(
                'Data Regional Baru:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text('ID SLS: $idSls'),
              if (namaSls != null) Text('Nama SLS: $namaSls'),
              if (kodePos != null) Text('Kode Pos: $kodePos'),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Pindahkan'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final repository = MapRepositoryImpl();
        final success = await repository.updateDirectoryCoordinatesWithRegionalData(
          place.id,
          newPoint.latitude,
          newPoint.longitude,
          idSls,
          kdProv,
          kdKab,
          kdKec,
          kdDesa,
          kdSls,
          kodePos,
          namaSls,
        );

        if (success) {
          scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Text(
                'Lokasi dan data regional "${place.name}" berhasil diperbarui',
              ),
              backgroundColor: Colors.green,
            ),
          );
          // Refresh data pada peta
          mapBloc.add(const PlacesRequested());
        } else {
          scaffoldMessenger.showSnackBar(
            const SnackBar(
              content: Text('Gagal memperbarui lokasi'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } catch (e) {
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
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
    // Save references before async operations
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final mapBloc = context.read<MapBloc>();

    // Calculate regional data from coordinates
    String idSls = '';
    String? kodePos;
    String? namaSls;
    String kdProv = '';
    String kdKab = '';
    String kdKec = '';
    String kdDesa = '';
    String kdSls = '';

    // Find polygon at point to get regional data
    final polygons = mapBloc.state.polygonsMeta;
    for (final polygon in polygons) {
      if (_isPointInPolygon(point, polygon.points)) {
        idSls = polygon.idsls ?? '';
        namaSls = polygon.name;
        kodePos = polygon.kodePos;

        // Extract regional codes from idSls
        if (idSls.isNotEmpty && idSls.length >= 14) {
          kdProv = idSls.substring(0, 2);
          kdKab = idSls.substring(2, 4);
          kdKec = idSls.substring(4, 7);
          kdDesa = idSls.substring(7, 10);
          kdSls = idSls.substring(10, 14);
        }
        break;
      }
    }

    // Show confirmation dialog with regional info
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
            if (idSls.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text(
                'Data Regional:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text('ID SLS: $idSls'),
              if (namaSls != null) Text('Nama SLS: $namaSls'),
              if (kodePos != null) Text('Kode Pos: $kodePos'),
            ],
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
        final success = await repository
            .updateDirectoryCoordinatesWithRegionalData(
              directory.id,
              point.latitude,
              point.longitude,
              idSls,
              kdProv,
              kdKab,
              kdKec,
              kdDesa,
              kdSls,
              kodePos,
              namaSls,
            );

        if (success) {
          scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Text(
                'Koordinat dan data regional "${directory.namaUsaha}" berhasil diupdate',
              ),
              backgroundColor: Colors.green,
            ),
          );

          // Refresh the map data
          mapBloc.add(const PlacesRequested());
        } else {
          scaffoldMessenger.showSnackBar(
            const SnackBar(
              content: Text('Gagal mengupdate koordinat'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } catch (e) {
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // Kode pos diambil langsung dari GeoJSON; fungsi API dihapus.

  void _showSelectExistingDirektori(BuildContext context, LatLng point) {
    final TextEditingController searchController = TextEditingController();
    List<DirektoriModel> searchResults = [];
    bool isSearching = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => Dialog(
          child: Container(
            width: MediaQuery.of(context).size.width * 0.8,
            height: MediaQuery.of(context).size.height * 0.7,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Pilih Direktori untuk Update Koordinat',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: searchController,
                  decoration: const InputDecoration(
                    labelText: 'Cari nama usaha',
                    hintText: 'Ketik minimal 3 karakter untuk mencari...',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (query) {
                    if (query.length >= 3) {
                      setState(() {
                        isSearching = true;
                      });
                      _searchDirectories(query, setState, (results, loading) {
                        searchResults = results;
                        isSearching = loading;
                      }, context);
                    } else {
                      setState(() {
                        searchResults = [];
                        isSearching = false;
                      });
                    }
                  },
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: isSearching
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 16),
                              Text('Mencari...'),
                            ],
                          ),
                        )
                      : searchResults.isEmpty
                      ? const Center(
                          child: Text(
                            'Tidak ada usaha yang ditemukan',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView.separated(
                          itemCount: searchResults.length,
                          separatorBuilder: (context, index) =>
                              const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final directory = searchResults[index];
                            return ListTile(
                              title: Text(
                                directory.namaUsaha,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (directory.alamat != null)
                                    Text(
                                      directory.alamat!,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  Text(
                                    'ID SLS: ${directory.idSls}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                              trailing: ElevatedButton(
                                onPressed: () {
                                  Navigator.of(dialogContext).pop();
                                  _updateDirectoryCoordinates(
                                    context,
                                    directory,
                                    point,
                                  );
                                },
                                child: const Text('Update Koordinat'),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _saveDirektori(
    BuildContext context,
    LatLng point,
    String namaUsaha,
    String alamat,
    String pemilik,
    String nomorTelepon,
    ScaffoldMessengerState scaffoldMessenger,
    MapBloc mapBloc, {
    bool minimalMode = false,
    String? namaKomersial,
    String? nib,
    String? email,
    String? website,
    String? nomorWhatsapp,
    String? nikPemilik,
    String? keterangan,
    String? kegiatanUsaha,
    String? deskripsiBadanUsaha,
    String? skalaUsaha,
    String? jenisPerusahaan,
    String? keberadaanUsaha,
    String? jenisKepemilikan,
    String? bentukBadanHukum,
    String? jaringanUsaha,
    String? sektorInstitusi,
    String? tahunBerdiri,
    String? tenagaKerja,
    DirektoriModel? existingDirectory,
  }) async {
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
          kodePos = polygon.kodePos; // Ambil kode pos dari GeoJSON
          print(
            '✅ [DEBUG] Polygon ditemukan! idSls: $idSls, nama_sls: $namaSls, kode_pos: $kodePos',
          );
          break;
        }
      }

      // Reverse geocoding untuk mendapatkan alamat dan kode pos (skip saat minimalMode)
      if (!minimalMode) {
        try {
          print('🌍 [DEBUG] Melakukan reverse geocoding...');
          List<Placemark> placemarks = await placemarkFromCoordinates(
            point.latitude,
            point.longitude,
          );

          if (placemarks.isNotEmpty) {
            final placemark = placemarks.first;
            alamatFromGeocode =
                '${placemark.street ?? ''}, ${placemark.subLocality ?? ''}, ${placemark.locality ?? ''}'
                    .replaceAll(RegExp(r'^,\s*|,\s*$'), '')
                    .replaceAll(RegExp(r',\s*,'), ',');
            print(
              '📍 [DEBUG] Reverse geocoding berhasil - Alamat: $alamatFromGeocode',
            );
          }
        } catch (e) {
          print('⚠️ [DEBUG] Reverse geocoding gagal: $e');
        }
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
        print(
          '🗺️ [DEBUG] Kode wilayah - Prov: $kdProv, Kab: $kdKab, Kec: $kdKec, Desa: $kdDesa, SLS: $kdSls',
        );
      }

      final directory = DirektoriModel(
        id:
            existingDirectory?.id ??
            '', // Use existing ID for updates, empty for new
        idSbr:
            existingDirectory?.idSbr ?? '0', // Default value untuk data non-BPS
        namaUsaha: namaUsaha,
        namaKomersialUsaha: namaKomersial,
        alamat: alamatFromGeocode ?? alamat, // Prioritas alamat dari geocoding
        idSls: idSls,
        kdProv: kdProv,
        kdKab: kdKab,
        kdKec: kdKec,
        kdDesa: kdDesa,
        kdSls: kdSls,
        nmSls: namaSls, // Menambahkan nama SLS
        kegiatanUsaha: kegiatanUsaha != null && kegiatanUsaha.isNotEmpty
            ? [
                {'nama': kegiatanUsaha},
              ]
            : existingDirectory?.kegiatanUsaha ?? const [],
        skalaUsaha: skalaUsaha,
        keterangan: keterangan,
        nib: nib,
        lat: point.latitude,
        long: point.longitude,
        latitude: point.latitude,
        longitude: point.longitude,
        urlGambar: existingDirectory?.urlGambar,
        kodePos: kodePos, // Kode pos dari GeoJSON
        jenisPerusahaan: jenisPerusahaan,
        pemilik: pemilik,
        nikPemilik: nikPemilik,
        nohpPemilik: nomorTelepon,
        nomorTelepon: nomorTelepon,
        nomorWhatsapp: nomorWhatsapp,
        email: email,
        website: website,
        sumberData: existingDirectory?.sumberData,
        keberadaanUsaha: keberadaanUsaha != null
            ? int.tryParse(keberadaanUsaha) ?? 1
            : 1,
        jenisKepemilikanUsaha: jenisKepemilikan != null
            ? int.tryParse(jenisKepemilikan)
            : null,
        bentukBadanHukumUsaha: bentukBadanHukum != null
            ? int.tryParse(bentukBadanHukum)
            : null,
        deskripsiBadanUsahaLainnya: deskripsiBadanUsaha,
        tahunBerdiri: tahunBerdiri != null ? int.tryParse(tahunBerdiri) : null,
        jaringanUsaha: jaringanUsaha != null
            ? int.tryParse(jaringanUsaha)
            : null,
        sektorInstitusi: sektorInstitusi != null
            ? int.tryParse(sektorInstitusi)
            : null,
        tenagaKerja: tenagaKerja != null ? int.tryParse(tenagaKerja) : null,
        createdAt: existingDirectory?.createdAt,
        updatedAt: DateTime.now(),
      );

      print('💾 [DEBUG] Menyimpan ke database...');
      final repository = MapRepositoryImpl();
      final success = await repository.insertDirectory(directory);

      print('📊 [DEBUG] Hasil penyimpanan: ${success ? "BERHASIL" : "GAGAL"}');

      if (success) {
        print(
          '✅ [DEBUG] Direktori berhasil disimpan, menampilkan SnackBar sukses',
        );
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

  void _updateRegionalData(BuildContext context, Place selectedPlace) async {
    // Save references before async operations
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final mapBloc = context.read<MapBloc>();

    // Get coordinates from selected place
    final point = selectedPlace.position;

    // Calculate regional data from coordinates
    String idSls = '';
    String? kodePos;
    String? namaSls;
    String kdProv = '';
    String kdKab = '';
    String kdKec = '';
    String kdDesa = '';
    String kdSls = '';

    // Find polygon at point to get regional data
    final polygons = mapBloc.state.polygonsMeta;
    for (final polygon in polygons) {
      if (_isPointInPolygon(point, polygon.points)) {
        idSls = polygon.idsls ?? '';
        namaSls = polygon.name;
        kodePos = polygon.kodePos;

        // Extract regional codes from idSls
        if (idSls.isNotEmpty && idSls.length >= 14) {
          kdProv = idSls.substring(0, 2);
          kdKab = idSls.substring(2, 4);
          kdKec = idSls.substring(4, 7);
          kdDesa = idSls.substring(7, 10);
          kdSls = idSls.substring(10, 14);
        }
        break;
      }
    }

    // Show confirmation dialog with regional info
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Konfirmasi Update Regional'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Direktori: ${selectedPlace.name}'),
            const SizedBox(height: 8),
            Text(
              'Koordinat: ${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}',
            ),
            const SizedBox(height: 8),
            Text('ID SLS: ${idSls.isNotEmpty ? idSls : "Tidak ditemukan"}'),
            const SizedBox(height: 4),
            Text('Nama SLS: ${namaSls ?? "Tidak ditemukan"}'),
            const SizedBox(height: 4),
            Text('Kode Pos: ${kodePos ?? "Tidak ditemukan"}'),
            const SizedBox(height: 8),
            if (idSls.isNotEmpty) ...[
              Text('Kode Provinsi: $kdProv'),
              Text('Kode Kabupaten: $kdKab'),
              Text('Kode Kecamatan: $kdKec'),
              Text('Kode Desa: $kdDesa'),
              Text('Kode SLS: $kdSls'),
            ],
            const SizedBox(height: 16),
            const Text(
              'Apakah Anda yakin ingin mengupdate data regional untuk direktori ini?',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Update Regional'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final repository = MapRepositoryImpl();
        final success = await repository
            .updateDirectoryCoordinatesWithRegionalData(
              selectedPlace.id,
              point.latitude,
              point.longitude,
              idSls,
              kdProv,
              kdKab,
              kdKec,
              kdDesa,
              kdSls,
              kodePos,
              namaSls,
            );

        if (success) {
          scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Text(
                'Data regional "${selectedPlace.name}" berhasil diupdate',
              ),
              backgroundColor: Colors.green,
            ),
          );

          // Refresh the map data
          mapBloc.add(const PlacesRequested());
        } else {
          scaffoldMessenger.showSnackBar(
            const SnackBar(
              content: Text('Gagal mengupdate data regional'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } catch (e) {
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}
