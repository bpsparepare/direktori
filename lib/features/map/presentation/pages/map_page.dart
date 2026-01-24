import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../../../../core/config/supabase_config.dart';
import 'package:uuid/uuid.dart';
import '../../data/repositories/map_repository_impl.dart';
import '../../data/repositories/scraping_repository_impl.dart';
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
import '../../../../core/widgets/image_upload_widget.dart';
import '../../../contribution/presentation/bloc/contribution_bloc.dart';
import '../../../contribution/presentation/bloc/contribution_event.dart';
import '../../data/services/groundcheck_supabase_service.dart';
import '../../data/services/bps_gc_service.dart';
import '../../data/services/gc_credentials_service.dart';
import '../../../../core/utils/map_utils.dart';
import 'groundcheck_page.dart';

class MapPage extends StatelessWidget {
  final MapController? mapController;
  final DirektoriModel?
  coordinateTarget; // Directory selected to add coordinate
  final VoidCallback? onExitCoordinateMode; // Callback to exit coordinate mode

  const MapPage({
    super.key,
    this.mapController,
    this.coordinateTarget,
    this.onExitCoordinateMode,
  });

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
                    selectedPlace:
                        state.selectedPlace, // Pass selectedPlace to MapView
                    polygon: state.polygon,
                    selectedPolygons:
                        state.selectedPolygons, // Pass selectedPolygons
                    polygonLabel: state.polygonLabel,
                    temporaryMarker: state.temporaryMarker,
                    polygonsMeta: state.polygonsMeta,
                    mapController: mapController, // Pass shared MapController
                    onPlaceTap: (place) {
                      context.read<MapBloc>().add(PlaceSelected(place));
                    },
                    onPlaceDragEnd: (place, newPoint) {
                      if (place.id.startsWith('gc:')) {
                        _confirmMoveGroundcheckCoordinates(
                          context,
                          place,
                          newPoint,
                        );
                      } else {
                        _confirmMovePlaceAndUpdateRegional(
                          context,
                          place,
                          newPoint,
                        );
                      }
                    },
                    onNearbyPlacesTap: (places) {
                      _showNearbyGroundcheckPopup(context, places);
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
                    onMultiplePolygonsSelected: (polygons) {
                      context.read<MapBloc>().add(
                        MultiplePolygonsSelected(polygons),
                      );
                    },
                    onBoundsChanged: (bounds) {
                      final south = bounds.south;
                      final north = bounds.north;
                      final west = bounds.west;
                      final east = bounds.east;
                      context.read<MapBloc>().add(
                        PlacesInBoundsRequested(south, north, west, east),
                      );
                    },
                    isPolygonSelected:
                        state.selectedPolygonMeta != null ||
                        state.selectedPolygons.isNotEmpty,
                  ),
                  // Coordinate mode overlay: center crosshair + actions
                  if (coordinateTarget != null) ...[
                    // Center crosshair icon (non-interactive)
                    IgnorePointer(
                      child: Center(
                        child: Icon(
                          Icons.add_location_alt_outlined,
                          color: Colors.blue,
                          size: 40,
                        ),
                      ),
                    ),
                    // Bottom action bar
                    Positioned(
                      bottom: 24,
                      left: 16,
                      right: 16,
                      child: Card(
                        elevation: 6,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: 16,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text(
                                      'Mode Tambah Koordinat',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      coordinateTarget?.namaUsaha ?? '-',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                              TextButton(
                                onPressed: () {
                                  onExitCoordinateMode?.call();
                                },
                                child: const Text('Batal'),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                onPressed: () {
                                  // Use map center as the chosen point
                                  final LatLng center =
                                      mapController?.camera.center ??
                                      config.center;
                                  _updateDirectoryCoordinates(
                                    context,
                                    coordinateTarget!,
                                    center,
                                    onSuccess: () {
                                      onExitCoordinateMode?.call();
                                    },
                                  );
                                },
                                icon: const Icon(Icons.save),
                                label: const Text('Simpan Koordinat'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],

                  // Refresh places button (top-right)
                  // Positioned(
                  //   top: 12,
                  //   right: 12,
                  //   child: Material(
                  //     color: Colors.white,
                  //     shape: const CircleBorder(),
                  //     elevation: 2,
                  //     child: IconButton(
                  //       tooltip: 'Refresh marker',
                  //       icon: const Icon(Icons.refresh),
                  //       onPressed: () {
                  //         MapRepositoryImpl().invalidatePlacesCache();
                  //         context.read<MapBloc>().add(const PlacesRequested());
                  //         ScaffoldMessenger.of(context).showSnackBar(
                  //           const SnackBar(
                  //             content: Text('Marker diperbarui'),
                  //             duration: Duration(milliseconds: 800),
                  //           ),
                  //         );
                  //       },
                  //     ),
                  //   ),
                  // ),
                  if (state.selectedPlace != null)
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide =
                            constraints.maxWidth >= 900; // desktop/layar besar
                        final Widget panel = Focus(
                          autofocus: true,
                          onKeyEvent: (node, event) {
                            if (event is KeyDownEvent &&
                                event.logicalKey == LogicalKeyboardKey.escape) {
                              context.read<MapBloc>().add(const PlaceCleared());
                              return KeyEventResult.handled;
                            }
                            return KeyEventResult.ignored;
                          },
                          child: GestureDetector(
                            onTap: () {
                              // Tap anywhere on card to close (optional)
                            },
                            child: Focus(
                              autofocus: true,
                              onKeyEvent: (node, event) {
                                if (event is KeyDownEvent &&
                                    event.logicalKey ==
                                        LogicalKeyboardKey.escape) {
                                  context.read<MapBloc>().add(
                                    const PlaceCleared(),
                                  );
                                  return KeyEventResult.handled;
                                }
                                return KeyEventResult.ignored;
                              },
                              child: Card(
                                elevation: 6,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Display image at the top if urlGambar is available
                                    if (state.selectedPlace!.urlGambar !=
                                            null &&
                                        state
                                            .selectedPlace!
                                            .urlGambar!
                                            .isNotEmpty) ...[
                                      ClipRRect(
                                        borderRadius: const BorderRadius.only(
                                          topLeft: Radius.circular(12),
                                          topRight: Radius.circular(12),
                                        ),
                                        child: AspectRatio(
                                          aspectRatio:
                                              16 / 9, // Maintain aspect ratio
                                          child: Image.network(
                                            state.selectedPlace!.urlGambar!,
                                            width: double.infinity,
                                            fit: BoxFit.cover,
                                            errorBuilder:
                                                (context, error, stackTrace) {
                                                  return Container(
                                                    width: double.infinity,
                                                    decoration: BoxDecoration(
                                                      color: Colors.grey[300],
                                                      borderRadius:
                                                          const BorderRadius.only(
                                                            topLeft:
                                                                Radius.circular(
                                                                  12,
                                                                ),
                                                            topRight:
                                                                Radius.circular(
                                                                  12,
                                                                ),
                                                          ),
                                                    ),
                                                    child: const Column(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .center,
                                                      children: [
                                                        Icon(
                                                          Icons.broken_image,
                                                          color: Colors.grey,
                                                          size: 40,
                                                        ),
                                                        SizedBox(height: 4),
                                                        Text(
                                                          'Gambar tidak dapat dimuat',
                                                          style: TextStyle(
                                                            color: Colors.grey,
                                                            fontSize: 12,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  );
                                                },
                                            loadingBuilder:
                                                (
                                                  context,
                                                  child,
                                                  loadingProgress,
                                                ) {
                                                  if (loadingProgress == null)
                                                    return child;
                                                  return Container(
                                                    width: double.infinity,
                                                    decoration: BoxDecoration(
                                                      color: Colors.grey[200],
                                                      borderRadius:
                                                          const BorderRadius.only(
                                                            topLeft:
                                                                Radius.circular(
                                                                  12,
                                                                ),
                                                            topRight:
                                                                Radius.circular(
                                                                  12,
                                                                ),
                                                          ),
                                                    ),
                                                    child: const Center(
                                                      child:
                                                          CircularProgressIndicator(),
                                                    ),
                                                  );
                                                },
                                          ),
                                        ),
                                      ),
                                    ],
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
                                                  state
                                                      .selectedPlace!
                                                      .description,
                                                ),
                                              ],
                                            ),
                                          ),
                                          // Improved close button with larger touch target
                                          Container(
                                            width: 48,
                                            height: 48,
                                            decoration: BoxDecoration(
                                              color: Colors.grey.withValues(
                                                alpha: 0.1,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(24),
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
                                            // Zoom to location button (only for non-scraped directories)
                                            if (state.selectedPlace != null &&
                                                !state.selectedPlace!.id
                                                    .startsWith('scrape:'))
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
                                                        style: ElevatedButton.styleFrom(
                                                          backgroundColor:
                                                              Colors.blue,
                                                          foregroundColor:
                                                              Colors.white,
                                                          padding:
                                                              const EdgeInsets.all(
                                                                12,
                                                              ),
                                                          minimumSize:
                                                              const Size(
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
                                                        label: const Flexible(
                                                          child: Text(
                                                            'Zoom To',
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            softWrap: false,
                                                          ),
                                                        ),
                                                        style: ElevatedButton.styleFrom(
                                                          backgroundColor:
                                                              Colors.blue,
                                                          foregroundColor:
                                                              Colors.white,
                                                          textStyle:
                                                              const TextStyle(
                                                                fontSize: 14,
                                                              ),
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
                                            if (state.selectedPlace != null &&
                                                !state.selectedPlace!.id
                                                    .startsWith('scrape:'))
                                              const SizedBox(width: 12),
                                            // Navigate to location button (only for non-scraped directories)
                                            if (state.selectedPlace != null &&
                                                !state.selectedPlace!.id
                                                    .startsWith('scrape:'))
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
                                                          final place = state
                                                              .selectedPlace!;
                                                          final lat = place
                                                              .position
                                                              .latitude;
                                                          final lng = place
                                                              .position
                                                              .longitude;

                                                          // Create Google Maps URL
                                                          final googleMapsUrl =
                                                              Uri.parse(
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
                                                            if (context
                                                                .mounted) {
                                                              ScaffoldMessenger.of(
                                                                context,
                                                              ).showSnackBar(
                                                                const SnackBar(
                                                                  content: Text(
                                                                    'Tidak dapat membuka aplikasi navigasi',
                                                                  ),
                                                                  backgroundColor:
                                                                      Colors
                                                                          .red,
                                                                ),
                                                              );
                                                            }
                                                          }
                                                        },
                                                        style: ElevatedButton.styleFrom(
                                                          backgroundColor:
                                                              Colors.green,
                                                          foregroundColor:
                                                              Colors.white,
                                                          padding:
                                                              const EdgeInsets.all(
                                                                12,
                                                              ),
                                                          minimumSize:
                                                              const Size(
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
                                                          final place = state
                                                              .selectedPlace!;
                                                          final lat = place
                                                              .position
                                                              .latitude;
                                                          final lng = place
                                                              .position
                                                              .longitude;

                                                          // Create Google Maps URL
                                                          final googleMapsUrl =
                                                              Uri.parse(
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
                                                            if (context
                                                                .mounted) {
                                                              ScaffoldMessenger.of(
                                                                context,
                                                              ).showSnackBar(
                                                                const SnackBar(
                                                                  content: Text(
                                                                    'Tidak dapat membuka aplikasi navigasi',
                                                                  ),
                                                                  backgroundColor:
                                                                      Colors
                                                                          .red,
                                                                ),
                                                              );
                                                            }
                                                          }
                                                        },
                                                        icon: const Icon(
                                                          Icons.navigation,
                                                          size: 18,
                                                        ),
                                                        label: const Flexible(
                                                          child: Text(
                                                            'Navigate',
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            softWrap: false,
                                                          ),
                                                        ),
                                                        style: ElevatedButton.styleFrom(
                                                          backgroundColor:
                                                              Colors.green,
                                                          foregroundColor:
                                                              Colors.white,
                                                          textStyle:
                                                              const TextStyle(
                                                                fontSize: 14,
                                                              ),
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
                                            if (state.selectedPlace != null &&
                                                !state.selectedPlace!.id
                                                    .startsWith('scrape:'))
                                              const SizedBox(width: 12),
                                            // Update Regional Data button (only for non-scraped directories)
                                            if (state.selectedPlace != null &&
                                                !state.selectedPlace!.id
                                                    .startsWith('scrape:'))
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
                                                          final place = state
                                                              .selectedPlace!;
                                                          _updateRegionalData(
                                                            context,
                                                            place,
                                                          );
                                                        },
                                                        style: ElevatedButton.styleFrom(
                                                          backgroundColor:
                                                              Colors.orange,
                                                          foregroundColor:
                                                              Colors.white,
                                                          padding:
                                                              const EdgeInsets.all(
                                                                12,
                                                              ),
                                                          minimumSize:
                                                              const Size(
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
                                                          final place = state
                                                              .selectedPlace!;
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
                                            // Add to Directory button for scraped places
                                            if (state.selectedPlace != null &&
                                                state.selectedPlace!.id
                                                    .startsWith('scrape:'))
                                              Expanded(
                                                child: LayoutBuilder(
                                                  builder: (context, constraints) {
                                                    final isMobile =
                                                        MediaQuery.of(
                                                          context,
                                                        ).size.width <
                                                        600;

                                                    void
                                                    handleAddFromScrape() async {
                                                      final place =
                                                          state.selectedPlace!;
                                                      String? kategori;
                                                      String? alamat;
                                                      String? website;
                                                      String? telp;
                                                      final desc =
                                                          place.description ??
                                                          '';
                                                      if (desc.isNotEmpty) {
                                                        for (final part
                                                            in desc.split(
                                                              ' | ',
                                                            )) {
                                                          final idx = part
                                                              .indexOf(':');
                                                          if (idx > 0) {
                                                            final key = part
                                                                .substring(
                                                                  0,
                                                                  idx,
                                                                )
                                                                .trim()
                                                                .toLowerCase();
                                                            final val = part
                                                                .substring(
                                                                  idx + 1,
                                                                )
                                                                .trim();
                                                            switch (key) {
                                                              case 'kategori':
                                                                kategori = val;
                                                                break;
                                                              case 'alamat':
                                                                alamat = val;
                                                                break;
                                                              case 'web':
                                                                website = val;
                                                                break;
                                                              case 'telp':
                                                                telp = val;
                                                                break;
                                                            }
                                                          }
                                                        }
                                                      }

                                                      // Regional codes are unknown for scraped, pass empty
                                                      _showAddDirektoriForm(
                                                        context,
                                                        place.position,
                                                        '', // idSls
                                                        '', // kdProv
                                                        '', // kdKab
                                                        '', // kdKec
                                                        '', // kdDesa
                                                        '', // kdSls
                                                        null, // namaSls
                                                        null, // kodePos
                                                        alamat, // alamatFromGeocode
                                                        existingDirectory: null,
                                                        initialNamaUsaha:
                                                            place.name,
                                                        initialAlamat: alamat,
                                                        initialWebsite: website,
                                                        initialNomorTelepon:
                                                            telp,
                                                        initialUrlGambar:
                                                            place.urlGambar,
                                                        initialKategori:
                                                            kategori,
                                                        startAtPhase2: true,
                                                        scrapedPlaceId:
                                                            place.id,
                                                      );
                                                    }

                                                    if (isMobile) {
                                                      return ElevatedButton(
                                                        onPressed:
                                                            handleAddFromScrape,
                                                        style: ElevatedButton.styleFrom(
                                                          backgroundColor:
                                                              Colors.purple,
                                                          foregroundColor:
                                                              Colors.white,
                                                          padding:
                                                              const EdgeInsets.all(
                                                                12,
                                                              ),
                                                          minimumSize:
                                                              const Size(
                                                                48,
                                                                48,
                                                              ),
                                                        ),
                                                        child: const Icon(
                                                          Icons.playlist_add,
                                                          size: 20,
                                                        ),
                                                      );
                                                    } else {
                                                      return ElevatedButton.icon(
                                                        onPressed:
                                                            handleAddFromScrape,
                                                        icon: const Icon(
                                                          Icons.playlist_add,
                                                          size: 18,
                                                        ),
                                                        label: const Flexible(
                                                          child: Text(
                                                            'Tambah ke Direktori',
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            softWrap: false,
                                                          ),
                                                        ),
                                                        style: ElevatedButton.styleFrom(
                                                          backgroundColor:
                                                              Colors.purple,
                                                          foregroundColor:
                                                              Colors.white,
                                                          textStyle:
                                                              const TextStyle(
                                                                fontSize: 14,
                                                              ),
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
                                            // Scraped-only actions: Hapus/Tutup status in Google Sheets
                                            if (state.selectedPlace != null &&
                                                state.selectedPlace!.id
                                                    .startsWith('scrape:'))
                                              const SizedBox(width: 12),
                                            if (state.selectedPlace != null &&
                                                state.selectedPlace!.id
                                                    .startsWith('scrape:'))
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
                                                        onPressed: () =>
                                                            _updateScrapeStatus(
                                                              context,
                                                              state
                                                                  .selectedPlace!,
                                                              'hapus',
                                                            ),
                                                        style: ElevatedButton.styleFrom(
                                                          backgroundColor:
                                                              Colors
                                                                  .red
                                                                  .shade700,
                                                          foregroundColor:
                                                              Colors.white,
                                                          padding:
                                                              const EdgeInsets.all(
                                                                12,
                                                              ),
                                                          minimumSize:
                                                              const Size(
                                                                48,
                                                                48,
                                                              ),
                                                        ),
                                                        child: const Icon(
                                                          Icons
                                                              .remove_circle_outline,
                                                          size: 20,
                                                        ),
                                                      );
                                                    } else {
                                                      return ElevatedButton.icon(
                                                        onPressed: () =>
                                                            _updateScrapeStatus(
                                                              context,
                                                              state
                                                                  .selectedPlace!,
                                                              'hapus',
                                                            ),
                                                        icon: const Icon(
                                                          Icons
                                                              .remove_circle_outline,
                                                          size: 18,
                                                        ),
                                                        label: const Flexible(
                                                          child: Text(
                                                            'Hapus (Scraping)',
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            softWrap: false,
                                                          ),
                                                        ),
                                                        style: ElevatedButton.styleFrom(
                                                          backgroundColor:
                                                              Colors
                                                                  .red
                                                                  .shade700,
                                                          foregroundColor:
                                                              Colors.white,
                                                          textStyle:
                                                              const TextStyle(
                                                                fontSize: 14,
                                                              ),
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
                                            if (state.selectedPlace != null &&
                                                state.selectedPlace!.id
                                                    .startsWith('scrape:'))
                                              const SizedBox(width: 12),
                                            if (state.selectedPlace != null &&
                                                state.selectedPlace!.id
                                                    .startsWith('scrape:'))
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
                                                        onPressed: () =>
                                                            _updateScrapeStatus(
                                                              context,
                                                              state
                                                                  .selectedPlace!,
                                                              'tutup',
                                                            ),
                                                        style: ElevatedButton.styleFrom(
                                                          backgroundColor:
                                                              Colors.orange,
                                                          foregroundColor:
                                                              Colors.white,
                                                          padding:
                                                              const EdgeInsets.all(
                                                                12,
                                                              ),
                                                          minimumSize:
                                                              const Size(
                                                                48,
                                                                48,
                                                              ),
                                                        ),
                                                        child: const Icon(
                                                          Icons.cancel_outlined,
                                                          size: 20,
                                                        ),
                                                      );
                                                    } else {
                                                      return ElevatedButton.icon(
                                                        onPressed: () =>
                                                            _updateScrapeStatus(
                                                              context,
                                                              state
                                                                  .selectedPlace!,
                                                              'tutup',
                                                            ),
                                                        icon: const Icon(
                                                          Icons.cancel_outlined,
                                                          size: 18,
                                                        ),
                                                        label: const Flexible(
                                                          child: Text(
                                                            'Tutup (Scraping)',
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            softWrap: false,
                                                          ),
                                                        ),
                                                        style: ElevatedButton.styleFrom(
                                                          backgroundColor:
                                                              Colors.orange,
                                                          foregroundColor:
                                                              Colors.white,
                                                          textStyle:
                                                              const TextStyle(
                                                                fontSize: 14,
                                                              ),
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
                                            if (state.selectedPlace != null &&
                                                state.selectedPlace!.id
                                                    .startsWith('scrape:'))
                                              const SizedBox(width: 12),
                                            // Open Google Maps link (only for scraped markers)
                                            if (state.selectedPlace != null &&
                                                state.selectedPlace!.id
                                                    .startsWith('scrape:'))
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
                                                        onPressed: () =>
                                                            _openScrapeGoogleMapsLink(
                                                              context,
                                                              state
                                                                  .selectedPlace!,
                                                            ),
                                                        style: ElevatedButton.styleFrom(
                                                          backgroundColor:
                                                              Colors.green,
                                                          foregroundColor:
                                                              Colors.white,
                                                          padding:
                                                              const EdgeInsets.all(
                                                                12,
                                                              ),
                                                          minimumSize:
                                                              const Size(
                                                                48,
                                                                48,
                                                              ),
                                                        ),
                                                        child: const Icon(
                                                          Icons.map,
                                                          size: 20,
                                                        ),
                                                      );
                                                    } else {
                                                      return ElevatedButton.icon(
                                                        onPressed: () =>
                                                            _openScrapeGoogleMapsLink(
                                                              context,
                                                              state
                                                                  .selectedPlace!,
                                                            ),
                                                        icon: const Icon(
                                                          Icons.map,
                                                          size: 18,
                                                        ),
                                                        label: const Flexible(
                                                          child: Text(
                                                            'Buka Google Maps',
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            softWrap: false,
                                                          ),
                                                        ),
                                                        style: ElevatedButton.styleFrom(
                                                          backgroundColor:
                                                              Colors.green,
                                                          foregroundColor:
                                                              Colors.white,
                                                          textStyle:
                                                              const TextStyle(
                                                                fontSize: 14,
                                                              ),
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
                                            if (state.selectedPlace != null &&
                                                state.selectedPlace!.id
                                                    .startsWith('scrape:'))
                                              const SizedBox(width: 12),
                                            // Edit directory button (only for non-scraped directories)
                                            if (state.selectedPlace != null &&
                                                !state.selectedPlace!.id
                                                    .startsWith('scrape:'))
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
                                                          final place = state
                                                              .selectedPlace!;

                                                          // Fetch full directory data from repository
                                                          final repository =
                                                              MapRepositoryImpl();
                                                          final directory =
                                                              await repository
                                                                  .getDirectoryById(
                                                                    place.id,
                                                                  );

                                                          if (directory !=
                                                              null) {
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
                                                            if (directory
                                                                        .idSls !=
                                                                    null &&
                                                                directory
                                                                    .idSls!
                                                                    .isNotEmpty) {
                                                              idSls = directory
                                                                  .idSls!;
                                                              if (idSls
                                                                      .length >=
                                                                  14) {
                                                                kdProv = idSls
                                                                    .substring(
                                                                      0,
                                                                      2,
                                                                    );
                                                                kdKab = idSls
                                                                    .substring(
                                                                      2,
                                                                      4,
                                                                    );
                                                                kdKec = idSls
                                                                    .substring(
                                                                      4,
                                                                      7,
                                                                    );
                                                                kdDesa = idSls
                                                                    .substring(
                                                                      7,
                                                                      10,
                                                                    );
                                                                kdSls = idSls
                                                                    .substring(
                                                                      10,
                                                                      14,
                                                                    );
                                                              }
                                                              namaSls =
                                                                  directory
                                                                      .nmSls;
                                                              kodePos =
                                                                  directory
                                                                      .kodePos;
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
                                                        style: ElevatedButton.styleFrom(
                                                          backgroundColor:
                                                              Colors.blue,
                                                          foregroundColor:
                                                              Colors.white,
                                                          padding:
                                                              const EdgeInsets.all(
                                                                12,
                                                              ),
                                                          minimumSize:
                                                              const Size(
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
                                                          final place = state
                                                              .selectedPlace!;

                                                          // Fetch full directory data from repository
                                                          final repository =
                                                              MapRepositoryImpl();
                                                          final directory =
                                                              await repository
                                                                  .getDirectoryById(
                                                                    place.id,
                                                                  );

                                                          if (directory !=
                                                              null) {
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
                                                            if (directory
                                                                        .idSls !=
                                                                    null &&
                                                                directory
                                                                    .idSls!
                                                                    .isNotEmpty) {
                                                              idSls = directory
                                                                  .idSls!;
                                                              if (idSls
                                                                      .length >=
                                                                  14) {
                                                                kdProv = idSls
                                                                    .substring(
                                                                      0,
                                                                      2,
                                                                    );
                                                                kdKab = idSls
                                                                    .substring(
                                                                      2,
                                                                      4,
                                                                    );
                                                                kdKec = idSls
                                                                    .substring(
                                                                      4,
                                                                      7,
                                                                    );
                                                                kdDesa = idSls
                                                                    .substring(
                                                                      7,
                                                                      10,
                                                                    );
                                                                kdSls = idSls
                                                                    .substring(
                                                                      10,
                                                                      14,
                                                                    );
                                                              }
                                                              namaSls =
                                                                  directory
                                                                      .nmSls;
                                                              kodePos =
                                                                  directory
                                                                      .kodePos;
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
                                                        label: const Text(
                                                          'Edit',
                                                        ),
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
                                            if (state.selectedPlace != null &&
                                                !state.selectedPlace!.id
                                                    .startsWith('scrape:'))
                                              const SizedBox(width: 12),
                                            // Delete or mark closed button (only for non-scraped directories)
                                            if (state.selectedPlace != null &&
                                                !state.selectedPlace!.id
                                                    .startsWith('scrape:'))
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
                                                          final place = state
                                                              .selectedPlace!;
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
                                                                      ).pop(
                                                                        false,
                                                                      ),
                                                                  child:
                                                                      const Text(
                                                                        'Batal',
                                                                      ),
                                                                ),
                                                                ElevatedButton(
                                                                  onPressed: () =>
                                                                      Navigator.of(
                                                                        ctx,
                                                                      ).pop(
                                                                        true,
                                                                      ),
                                                                  child:
                                                                      const Text(
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
                                                                      Colors
                                                                          .green,
                                                                ),
                                                              );
                                                              // Refresh data dan tutup card
                                                              context
                                                                  .read<
                                                                    MapBloc
                                                                  >()
                                                                  .add(
                                                                    const PlacesRequested(),
                                                                  );
                                                              context
                                                                  .read<
                                                                    MapBloc
                                                                  >()
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
                                                                      Colors
                                                                          .red,
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
                                                          backgroundColor:
                                                              Colors.red,
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
                                                          final place = state
                                                              .selectedPlace!;
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
                                                                      ).pop(
                                                                        false,
                                                                      ),
                                                                  child:
                                                                      const Text(
                                                                        'Batal',
                                                                      ),
                                                                ),
                                                                ElevatedButton(
                                                                  onPressed: () =>
                                                                      Navigator.of(
                                                                        ctx,
                                                                      ).pop(
                                                                        true,
                                                                      ),
                                                                  child:
                                                                      const Text(
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
                                                                      Colors
                                                                          .green,
                                                                ),
                                                              );
                                                              // Refresh data dan tutup card
                                                              context
                                                                  .read<
                                                                    MapBloc
                                                                  >()
                                                                  .add(
                                                                    const PlacesRequested(),
                                                                  );
                                                              context
                                                                  .read<
                                                                    MapBloc
                                                                  >()
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
                                                                      Colors
                                                                          .red,
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
                                                          backgroundColor:
                                                              Colors.red,
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
                        );
                        if (isWide) {
                          // Tampilkan sebagai panel samping pada layar besar (seperti Google Maps)
                          return Align(
                            alignment: Alignment.centerRight,
                            child: Container(
                              margin: const EdgeInsets.all(12.0),
                              width: math.min(constraints.maxWidth * 0.5, 600),
                              child: panel,
                            ),
                          );
                        } else {
                          // Tampilkan sebagai bottom card pada mobile
                          return Align(
                            alignment: Alignment.bottomCenter,
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: panel,
                            ),
                          );
                        }
                      },
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

  // Helper function to get keberadaan usaha description
  String _getKeberadaanUsahaDescription(int? keberadaanUsaha) {
    if (keberadaanUsaha == null) {
      return 'Undefined';
    }

    switch (keberadaanUsaha) {
      case 1:
        return 'Aktif';
      case 2:
        return 'Tutup Sementara';
      case 3:
        return 'Belum Beroperasi/Berproduksi';
      case 4:
        return 'Tutup';
      case 5:
        return 'Alih Usaha';
      case 6:
        return 'Tidak Ditemukan';
      case 7:
        return 'Aktif Pindah';
      case 8:
        return 'Aktif Nonrespon';
      case 9:
        return 'Duplikat';
      case 10:
        return 'Salah Kode Wilayah';
      default:
        return 'Tidak Diketahui';
    }
  }

  // Helper function to get keberadaan usaha color
  Color _getKeberadaanUsahaColor(int? keberadaanUsaha) {
    if (keberadaanUsaha == null) {
      return Colors.grey.shade400;
    }

    switch (keberadaanUsaha) {
      case 1: // Aktif
        return Colors.green;
      case 2: // Tutup Sementara
        return Colors.orange;
      case 3: // Belum Beroperasi/Berproduksi
        return Colors.blue;
      case 4: // Tutup
        return Colors.red;
      case 5: // Alih Usaha
        return Colors.purple;
      case 6: // Tidak Ditemukan
        return Colors.grey;
      case 7: // Aktif Pindah
        return Colors.teal;
      case 8: // Aktif Nonrespon
        return Colors.amber;
      case 9: // Duplikat
        return Colors.brown;
      case 10: // Salah Kode Wilayah
        return Colors.pink;
      default:
        return Colors.grey;
    }
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
              leading: const Icon(
                Icons.playlist_add_check,
                color: Colors.purple,
              ),
              title: const Text('Tambah Groundcheck'),
              subtitle: const Text('Cari & Tambah/Edit data groundcheck'),
              onTap: () {
                Navigator.pop(context);
                parentContext.read<MapBloc>().add(
                  const TemporaryMarkerRemoved(),
                );

                // Calculate region data
                String idSls = '';
                String? namaSls;
                final polygons = parentContext
                    .read<MapBloc>()
                    .state
                    .polygonsMeta;
                for (final polygon in polygons) {
                  if (MapUtils.isPointInPolygon(point, polygon.points)) {
                    idSls = polygon.idsls ?? '';
                    namaSls = polygon.name;
                    break;
                  }
                }

                _showAddGroundcheckForm(context, point, idSls, namaSls);
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
            Visibility(
              visible:
                  DateTime.now().year == 2025 &&
                  DateTime.now().month == 11 &&
                  DateTime.now().day == 11,
              child: ListTile(
                leading: const Icon(Icons.flag, color: Colors.green),
                title: const Text('Kirim Quiz'),
                subtitle: const Text('Kirim titik ini sebagai jawaban'),
                onTap: () async {
                  Navigator.pop(context);
                  final confirm = await showDialog<bool>(
                    context: parentContext,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Kirim jawaban?'),
                      content: const Text(
                        'Apakah Anda yakin ingin mengirim titik ini sebagai jawaban?',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(false),
                          child: const Text('Batal'),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.of(ctx).pop(true),
                          child: const Text('Kirim'),
                        ),
                      ],
                    ),
                  );

                  if (confirm == true) {
                    try {
                      // Tampilkan indikator proses
                      showDialog(
                        context: parentContext,
                        barrierDismissible: false,
                        builder: (ctx) => const AlertDialog(
                          content: Row(
                            children: [
                              SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(),
                              ),
                              SizedBox(width: 16),
                              Expanded(child: Text('Mengirim jawaban...')),
                            ],
                          ),
                        ),
                      );

                      final result = await SupabaseConfig.client.rpc(
                        'fn_submit_guess_current',
                        params: {
                          'p_lat': point.latitude,
                          'p_lon': point.longitude,
                        },
                      );

                      // Tutup indikator proses
                      if (Navigator.of(parentContext).canPop()) {
                        Navigator.of(parentContext).pop();
                      }

                      // Ekstrak metrik dari hasil RPC, jika tidak ada, query dari tabel submissions
                      String submissionId = '';
                      num? score;
                      bool? isCorrect;
                      num? distanceM;
                      int? durationMs;

                      if (result is Map<String, dynamic>) {
                        submissionId = (result['id']?.toString() ?? '');
                        score =
                            (result['score'] ?? result['total_score']) as num?;
                        isCorrect = result['is_correct'] as bool?;
                        distanceM =
                            (result['distance_m'] ?? result['distance'])
                                as num?;
                        durationMs =
                            (result['duration_ms'] ?? result['total_time_ms'])
                                as int?;
                      } else if (result is List &&
                          result.isNotEmpty &&
                          result.first is Map<String, dynamic>) {
                        final m = result.first as Map<String, dynamic>;
                        submissionId = (m['id']?.toString() ?? '');
                        score = (m['score'] ?? m['total_score']) as num?;
                        isCorrect = m['is_correct'] as bool?;
                        distanceM = (m['distance_m'] ?? m['distance']) as num?;
                        durationMs =
                            (m['duration_ms'] ?? m['total_time_ms']) as int?;
                      } else if (result is String) {
                        submissionId = result;
                      }

                      // SnackBar konfirmasi minimalis (tampilkan skor/benar jika tersedia)
                      final scoreText = (score != null)
                          ? (score is int
                                ? score.toString()
                                : (score as num).toString())
                          : null;
                      final isCorrectText = (isCorrect == null)
                          ? null
                          : (isCorrect! ? 'Benar' : 'Salah');
                      final msg = (scoreText != null && isCorrectText != null)
                          ? 'Berhasil kirim. Skor: $scoreText • $isCorrectText'
                          : 'Berhasil kirim jawaban.';
                      ScaffoldMessenger.of(
                        parentContext,
                      ).showSnackBar(SnackBar(content: Text(msg)));
                    } catch (e) {
                      // Tutup indikator proses jika masih terbuka
                      if (Navigator.of(parentContext).canPop()) {
                        Navigator.of(parentContext).pop();
                      }

                      final message = e.toString();

                      // Feedback minimalis untuk error
                      ScaffoldMessenger.of(parentContext).showSnackBar(
                        SnackBar(content: Text('Gagal kirim: $message')),
                      );
                    }
                  }
                },
              ),
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

    // Check if polygons data is stale (has metadata but no points)
    // This happens if the app was hot-reloaded after we disabled the metadata-only optimization
    final isStale =
        mapBloc.state.polygonsMeta.isNotEmpty &&
        mapBloc.state.polygonsMeta.first.points.isEmpty;

    if (isStale) {
      print(
        '⚠️ [DEBUG] Stale polygon data detected (no points). Triggering reload...',
      );
      mapBloc.add(const PolygonsListRequested());
    }

    showDialog(
      context: context,
      builder: (dialogContext) => BlocBuilder<MapBloc, MapState>(
        bloc: mapBloc,
        builder: (context, state) {
          return AlertDialog(
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
                    // Show loading if we are reloading data
                    if (state.polygonsMeta.isNotEmpty &&
                        state.polygonsMeta.first.points.isEmpty) {
                      return const Center(
                        child: Column(
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 8),
                            Text('Memuat data geometri SLS...'),
                          ],
                        ),
                      );
                    }

                    String? polygonInfo;
                    String? kodePosInfo;

                    for (final polygon in state.polygonsMeta) {
                      if (MapUtils.isPointInPolygon(point, polygon.points)) {
                        polygonInfo = '${polygon.name} (${polygon.idsls})';
                        kodePosInfo = polygon.kodePos;
                        break;
                      }
                    }

                    if (polygonInfo != null) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(polygonInfo),
                          if (kodePosInfo != null &&
                              kodePosInfo.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            const Text(
                              'Kode Pos:',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(kodePosInfo),
                          ],
                        ],
                      );
                    }
                    return const Text('Tidak ada SLS di lokasi ini');
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  mapBloc.add(const TemporaryMarkerRemoved());
                },
                child: const Text('Tutup'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  mapBloc.add(const TemporaryMarkerRemoved());

                  bool found = false;
                  for (int i = 0; i < state.polygonsMeta.length; i++) {
                    final polygon = state.polygonsMeta[i];
                    if (MapUtils.isPointInPolygon(point, polygon.points)) {
                      mapBloc.add(PolygonSelectedByIndex(i));

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('SLS ${polygon.name} telah dipilih'),
                          backgroundColor: Colors.green,
                        ),
                      );
                      found = true;
                      return;
                    }
                  }

                  // Jika tidak ditemukan
                  if (!found) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Tidak ada SLS di lokasi ini'),
                        backgroundColor: Colors.orange,
                      ),
                    );
                  }
                },
                child: const Text('Pilih SLS'),
              ),
            ],
          );
        },
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
        if (MapUtils.isPointInPolygon(point, polygon.points)) {
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
        if (MapUtils.isPointInPolygon(point, polygon.points)) {
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
                  if (MapUtils.isPointInPolygon(point, polygon.points)) {
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

  void _showAddGroundcheckForm(
    BuildContext context,
    LatLng point,
    String idSls,
    String? namaSls,
  ) {
    // Controllers
    final idsbrController = TextEditingController();
    final namaUsahaController = TextEditingController();
    final alamatController = TextEditingController();

    // Dropdown values
    String? selectedStatus;
    String? selectedSkala;
    String? selectedGcsResult;

    // Search state
    List<GroundcheckRecord> searchResults = [];
    bool isSearching = false;
    bool showSuggestions = false;
    Timer? _debounce;

    // Phase tracking: 1 = Search, 2 = Form
    int currentPhase = 1;
    GroundcheckRecord? editingRecord;
    bool useCurrentLocation =
        true; // For editing: update location to clicked point?

    // Helper to normalize status for dropdown
    String? _normalizeStatus(String status) {
      if (status.isEmpty) return null;
      final lower = status.toLowerCase();
      if (lower.contains('aktif')) return 'Aktif';
      if (lower.contains('tutup sementara')) return 'Tutup Sementara';
      if (lower.contains('belum beroperasi')) return 'Belum Beroperasi';
      if (lower.contains('tutup')) return 'Tutup';
      if (lower.contains('alih usaha')) return 'Alih Usaha';
      if (lower.contains('tidak ditemukan')) return 'Tidak Ditemukan';
      return status; // Fallback
    }

    // Helper to normalize GCS for dropdown
    String? _normalizeGcs(String gcs) {
      if (gcs.isEmpty) return null;
      final lower = gcs.toLowerCase();
      if (lower.contains('ditemukan') && !lower.contains('tidak'))
        return '1. Ditemukan';
      if (lower.contains('tutup')) return '3. Tutup';
      if (lower.contains('ganda')) return '4. Ganda';
      if (lower.contains('tidak ditemukan')) return '0. Tidak Ditemukan';
      return gcs;
    }

    // Pre-fill function
    void _prefillForm(GroundcheckRecord record) {
      idsbrController.text = record.idsbr;
      namaUsahaController.text = record.namaUsaha;
      alamatController.text = record.alamatUsaha;
      selectedStatus = _normalizeStatus(record.statusPerusahaan);
      selectedSkala = record.skalaUsaha.isEmpty ? null : record.skalaUsaha;
      selectedGcsResult = _normalizeGcs(record.gcsResult);
    }

    Color _getGcsColor(String gcsResult) {
      final lower = gcsResult.toLowerCase();
      if (lower.isEmpty || lower == '-- pilih --') {
        return Colors.grey;
      } else if (lower == '99' || lower.contains('tidak ditemukan')) {
        return Colors.red;
      } else if (lower == '1' || lower.contains('ditemukan')) {
        return Colors.green;
      } else if (lower == '3' || lower.contains('tutup')) {
        return Colors.blueGrey;
      } else if (lower == '4' || lower.contains('ganda')) {
        return Colors.orange;
      } else if (lower == '5' ||
          lower.contains('usaha') ||
          lower.contains('tambahan')) {
        return Colors.blue;
      } else {
        return Colors.blueGrey;
      }
    }

    String _getGcsLabel(String gcsResult) {
      final lower = gcsResult.toLowerCase();
      if (lower.isEmpty || lower == '-- pilih --') {
        return 'Belum GC';
      } else if (lower == '0' || lower.contains('tidak ditemukan')) {
        return '0. Tidak Ditemukan';
      } else if (lower == '1' || lower.contains('ditemukan')) {
        return '1. Ditemukan';
      } else if (lower == '3' || lower.contains('tutup')) {
        return '3. Tutup';
      } else if (lower == '4' || lower.contains('ganda')) {
        return '4. Ganda';
      } else if (lower == '5' ||
          lower.contains('usaha') ||
          lower.contains('tambahan')) {
        return '5. Usaha Baru';
      } else {
        return gcsResult;
      }
    }

    Color _getStatusColor(String status) {
      final lower = status.toLowerCase();
      if (lower.contains('aktif')) {
        return Colors.green;
      } else if (lower.contains('tutup sementara')) {
        return Colors.orange;
      } else if (lower.contains('belum beroperasi')) {
        return Colors.blue;
      } else if (lower.contains('tutup')) {
        return Colors.red;
      } else if (lower.contains('alih usaha')) {
        return Colors.purple;
      } else if (lower.contains('tidak ditemukan')) {
        return Colors.grey;
      } else {
        return Colors.grey;
      }
    }

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
                // Header
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        currentPhase == 1
                            ? 'Cari / Tambah Groundcheck'
                            : (editingRecord != null
                                  ? 'Edit Groundcheck'
                                  : 'Tambah Baru'),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(bottomSheetContext).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (currentPhase == 1) ...[
                          TextField(
                            decoration: InputDecoration(
                              labelText: 'Cari Nama Usaha / IDSBR',
                              prefixIcon: const Icon(Icons.search),
                              border: const OutlineInputBorder(),
                              suffixIcon: isSearching
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : null,
                            ),
                            onChanged: (query) {
                              if (_debounce?.isActive ?? false)
                                _debounce!.cancel();
                              _debounce = Timer(
                                const Duration(milliseconds: 500),
                                () {
                                  if (!context.mounted) return;
                                  if (query.length >= 2) {
                                    setState(() {
                                      isSearching = true;
                                      showSuggestions = true;
                                    });
                                    GroundcheckSupabaseService()
                                        .searchRecords(query)
                                        .then((results) {
                                          if (!context.mounted) return;
                                          setState(() {
                                            searchResults = results;
                                            isSearching = false;
                                          });
                                        });
                                  } else {
                                    setState(() {
                                      searchResults = [];
                                      isSearching = false;
                                      showSuggestions = false;
                                    });
                                  }
                                },
                              );
                            },
                          ),
                          const SizedBox(height: 16),
                          if (searchResults.isNotEmpty)
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: searchResults.length,
                              separatorBuilder: (context, index) =>
                                  const Divider(),
                              itemBuilder: (context, index) {
                                final record = searchResults[index];
                                final gcsLabel = _getGcsLabel(record.gcsResult);
                                final statusLabel =
                                    record.statusPerusahaan.isEmpty
                                    ? 'Belum Ada Status'
                                    : record.statusPerusahaan;
                                final lat = double.tryParse(record.latitude);
                                final lon = double.tryParse(record.longitude);
                                final hasCoord =
                                    lat != null &&
                                    lon != null &&
                                    lat != 0.0 &&
                                    lon != 0.0;

                                return ListTile(
                                  leading: Icon(
                                    Icons.location_on,
                                    color: _getGcsColor(record.gcsResult),
                                    size: 32,
                                  ),
                                  title: Text(record.namaUsaha),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('${record.alamatUsaha}'),
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 4,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color:
                                                  (hasCoord
                                                          ? Colors.blue
                                                          : Colors.red)
                                                      .withValues(alpha: 0.1),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              border: Border.all(
                                                color:
                                                    (hasCoord
                                                            ? Colors.blue
                                                            : Colors.red)
                                                        .withValues(alpha: 0.5),
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  hasCoord
                                                      ? Icons.location_on
                                                      : Icons.location_off,
                                                  size: 12,
                                                  color: hasCoord
                                                      ? Colors.blue
                                                      : Colors.red,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  hasCoord
                                                      ? 'Ada Koordinat'
                                                      : 'Tanpa Koordinat',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: hasCoord
                                                        ? Colors.blue
                                                        : Colors.red,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (record.gcsResult.isNotEmpty)
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: _getGcsColor(
                                                  record.gcsResult,
                                                ).withValues(alpha: 0.1),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                                border: Border.all(
                                                  color: _getGcsColor(
                                                    record.gcsResult,
                                                  ).withValues(alpha: 0.5),
                                                ),
                                              ),
                                              child: Text(
                                                gcsLabel,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: _getGcsColor(
                                                    record.gcsResult,
                                                  ),
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          if (record
                                              .statusPerusahaan
                                              .isNotEmpty)
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: _getStatusColor(
                                                  record.statusPerusahaan,
                                                ).withValues(alpha: 0.1),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                                border: Border.all(
                                                  color: _getStatusColor(
                                                    record.statusPerusahaan,
                                                  ).withValues(alpha: 0.5),
                                                ),
                                              ),
                                              child: Text(
                                                statusLabel,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: _getStatusColor(
                                                    record.statusPerusahaan,
                                                  ),
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  isThreeLine: true,
                                  onTap: () {
                                    setState(() {
                                      editingRecord = record;
                                      _prefillForm(record);
                                      currentPhase = 2;
                                      useCurrentLocation =
                                          false; // Default to keeping existing location
                                    });
                                  },
                                );
                              },
                            ),
                          if (searchResults.isEmpty &&
                              showSuggestions &&
                              !isSearching)
                            const Padding(
                              padding: EdgeInsets.all(8.0),
                              child: Text(
                                'Tidak ditemukan. Silakan buat baru.',
                              ),
                            ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                setState(() {
                                  currentPhase = 2;
                                  editingRecord = null;
                                  // Clear form
                                  idsbrController.clear();
                                  namaUsahaController.clear();
                                  alamatController.clear();
                                  selectedStatus = null;
                                  selectedSkala = null;
                                  selectedGcsResult = null;
                                  useCurrentLocation = true;
                                });
                              },
                              icon: const Icon(Icons.add),
                              label: const Text('Buat Data Baru'),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                              ),
                            ),
                          ),
                        ] else ...[
                          // Phase 2: Form
                          if (editingRecord != null)
                            CheckboxListTile(
                              title: const Text(
                                'Update Lokasi ke Titik Pilihan',
                              ),
                              subtitle: Text(
                                'Lat: ${point.latitude.toStringAsFixed(6)}, Lng: ${point.longitude.toStringAsFixed(6)}',
                              ),
                              value: useCurrentLocation,
                              onChanged: (val) {
                                setState(() {
                                  useCurrentLocation = val ?? false;
                                });
                              },
                            ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: namaUsahaController,
                            decoration: const InputDecoration(
                              labelText: 'Nama Usaha *',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: alamatController,
                            decoration: const InputDecoration(
                              labelText: 'Alamat Usaha',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () {
                                    setState(() {
                                      currentPhase = 1;
                                    });
                                  },
                                  child: const Text('Kembali'),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () async {
                                    if (namaUsahaController.text.isEmpty) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Nama Usaha wajib diisi',
                                          ),
                                        ),
                                      );
                                      return;
                                    }

                                    // Auto-generate IDSBR if empty or if creating new
                                    String finalIdsbr;
                                    if (editingRecord != null) {
                                      finalIdsbr = editingRecord!.idsbr;
                                    } else {
                                      // If creating new, generate temp ID
                                      finalIdsbr =
                                          'TEMP-${DateTime.now().millisecondsSinceEpoch}';
                                    }

                                    final service =
                                        GroundcheckSupabaseService();
                                    final userId =
                                        editingRecord?.userId ??
                                        await service.fetchCurrentUserId();
                                    final record = GroundcheckRecord(
                                      idsbr: finalIdsbr,
                                      namaUsaha: namaUsahaController.text,
                                      alamatUsaha: alamatController.text,
                                      kodeWilayah:
                                          idSls, // Use the region where the point is
                                      statusPerusahaan: 'Aktif',
                                      skalaUsaha: '', // Null/empty as requested
                                      gcsResult: editingRecord != null
                                          ? '1' // Ditemukan
                                          : '5', // Tambahan
                                      latitude: useCurrentLocation
                                          ? point.latitude.toString()
                                          : (editingRecord?.latitude ??
                                                point.latitude.toString()),
                                      longitude: useCurrentLocation
                                          ? point.longitude.toString()
                                          : (editingRecord?.longitude ??
                                                point.longitude.toString()),
                                      perusahaanId:
                                          editingRecord?.perusahaanId ??
                                          finalIdsbr,
                                      userId: userId,
                                    );

                                    await service.updateRecord(record);

                                    // Refresh map to show new/updated marker
                                    try {
                                      MapRepositoryImpl()
                                          .invalidatePlacesCache();
                                    } catch (_) {}
                                    if (context.mounted) {
                                      context.read<MapBloc>().add(
                                        const PlacesRequested(),
                                      );
                                    }

                                    if (context.mounted) {
                                      Navigator.of(context).pop();
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Data berhasil disimpan',
                                          ),
                                        ),
                                      );
                                    }
                                  },
                                  child: const Text('Simpan'),
                                ),
                              ),
                            ],
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
    // Optional initial values for prefill (e.g., from scraped place)
    String? initialNamaUsaha,
    String? initialAlamat,
    String? initialWebsite,
    String? initialNomorTelepon,
    String? initialUrlGambar,
    String? initialKategori,
    bool startAtPhase2 = false,
    // If invoked from scraped marker, pass its placeId to update Sheets status after save
    String? scrapedPlaceId,
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
    final kategoriController =
        TextEditingController(); // For kategori/tag input
    final kbliController = TextEditingController(); // For KBLI 5-digit code
    final tagController = TextEditingController(); // For tag input
    final urlGambarController = TextEditingController(); // For image URL

    // Dropdown variables
    // Declare dropdown variables first
    List<String> selectedTags = []; // For multiple tag selection
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

      // Initialize KBLI and tag fields
      kbliController.text = existingDirectory.kbli ?? '';
      if (existingDirectory.tag != null && existingDirectory.tag!.isNotEmpty) {
        selectedTags = List<String>.from(existingDirectory.tag!);
        tagController.text = selectedTags.join(', ');
      }
    }

    // Apply initial prefill values (e.g., from scraped place)
    if (existingDirectory == null) {
      if (initialNamaUsaha != null && initialNamaUsaha.isNotEmpty) {
        namaUsahaController.text = initialNamaUsaha;
      }
      if (initialAlamat != null && initialAlamat.isNotEmpty) {
        alamatController.text = initialAlamat;
      } else if (alamatFromGeocode != null && alamatFromGeocode.isNotEmpty) {
        alamatController.text = alamatFromGeocode;
      }
      if (initialWebsite != null && initialWebsite.isNotEmpty) {
        websiteController.text = initialWebsite;
      }
      if (initialNomorTelepon != null && initialNomorTelepon.isNotEmpty) {
        nomorTeleponController.text = initialNomorTelepon;
      }
      if (initialUrlGambar != null && initialUrlGambar.isNotEmpty) {
        urlGambarController.text = initialUrlGambar;
      }
      if (initialKategori != null && initialKategori.isNotEmpty) {
        kategoriController.text = initialKategori;
      }
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
    bool showFollowUpQuestions =
        false; // Controls follow-up questions visibility

    // If instructed to start at phase 2 (e.g., scraped place), configure flow
    if (existingDirectory == null &&
        (startAtPhase2 ||
            (initialNamaUsaha != null && initialNamaUsaha.isNotEmpty))) {
      currentPhase = 2;
      businessNameSelected = true;
      selectedBusinessType = 'new';
      selectedExistingBusiness = null;
    }

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
                          Row(
                            children: [
                              IconButton(
                                tooltip: 'Info lokasi',
                                onPressed: () {
                                  showDialog(
                                    context: bottomSheetContext,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text('Informasi Lokasi'),
                                      content: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Koordinat:',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Latitude: ${point.latitude.toStringAsFixed(6)}',
                                          ),
                                          Text(
                                            'Longitude: ${point.longitude.toStringAsFixed(6)}',
                                          ),
                                          const SizedBox(height: 12),
                                          const Text(
                                            'Informasi Wilayah:',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'idsls: ${idSls.isNotEmpty ? idSls : "-"}',
                                          ),
                                          Text('kode_pos: ${kodePos ?? "-"}'),
                                        ],
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.of(ctx).pop(),
                                          child: const Text('Tutup'),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.info_outline),
                              ),
                              IconButton(
                                onPressed: () =>
                                    Navigator.of(bottomSheetContext).pop(),
                                icon: const Icon(Icons.close),
                              ),
                            ],
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
                        // Info lokasi dipindahkan ke dialog (ikon info di header)
                        const SizedBox(height: 8),

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
                                  if (showSuggestions)
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
                                                                    showSuggestions =
                                                                        false;
                                                                    businessNameSelected =
                                                                        true;
                                                                    selectedBusinessType =
                                                                        'new';
                                                                    currentPhase =
                                                                        2;
                                                                    // Clear existing business reference for new business
                                                                    selectedExistingBusiness =
                                                                        null;
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
                                                                  // Keberadaan Usaha info
                                                                  const SizedBox(
                                                                    height: 4,
                                                                  ),
                                                                  Row(
                                                                    children: [
                                                                      Container(
                                                                        width:
                                                                            8,
                                                                        height:
                                                                            8,
                                                                        decoration: BoxDecoration(
                                                                          color: _getKeberadaanUsahaColor(
                                                                            directory.keberadaanUsaha,
                                                                          ),
                                                                          shape:
                                                                              BoxShape.circle,
                                                                        ),
                                                                      ),
                                                                      const SizedBox(
                                                                        width:
                                                                            4,
                                                                      ),
                                                                      Text(
                                                                        _getKeberadaanUsahaDescription(
                                                                          directory
                                                                              .keberadaanUsaha,
                                                                        ),
                                                                        style: TextStyle(
                                                                          fontSize:
                                                                              10,
                                                                          color: _getKeberadaanUsahaColor(
                                                                            directory.keberadaanUsaha,
                                                                          ),
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
                                                                    namaUsahaController
                                                                            .text =
                                                                        directory
                                                                            .namaUsaha;
                                                                    alamatController
                                                                            .text =
                                                                        directory
                                                                            .alamat ??
                                                                        '';
                                                                    pemilikController
                                                                            .text =
                                                                        directory
                                                                            .pemilik ??
                                                                        '';
                                                                    nomorTeleponController
                                                                            .text =
                                                                        directory
                                                                            .nomorTelepon ??
                                                                        '';
                                                                    namaKomersialController
                                                                            .text =
                                                                        directory
                                                                            .namaKomersialUsaha ??
                                                                        '';
                                                                    nibController
                                                                            .text =
                                                                        directory
                                                                            .nib ??
                                                                        '';
                                                                    emailController
                                                                            .text =
                                                                        directory
                                                                            .email ??
                                                                        '';
                                                                    websiteController
                                                                            .text =
                                                                        directory
                                                                            .website ??
                                                                        '';
                                                                    nomorWhatsappController
                                                                            .text =
                                                                        directory
                                                                            .nomorWhatsapp ??
                                                                        '';
                                                                    nikPemilikController
                                                                            .text =
                                                                        directory
                                                                            .nikPemilik ??
                                                                        '';
                                                                    kegiatanUsahaController
                                                                            .text =
                                                                        directory
                                                                            .kegiatanUsaha
                                                                            .isNotEmpty
                                                                        ? directory
                                                                              .kegiatanUsaha
                                                                              .map(
                                                                                (
                                                                                  k,
                                                                                ) =>
                                                                                    k['kegiatan_usaha'] ??
                                                                                    '',
                                                                              )
                                                                              .join(', ')
                                                                        : '';

                                                                    // Set dropdown values
                                                                    selectedSkalaUsaha =
                                                                        directory
                                                                            .skalaUsaha;
                                                                    selectedJenisPerusahaan =
                                                                        directory
                                                                            .jenisPerusahaan;
                                                                    selectedKeberadaanUsaha =
                                                                        directory
                                                                            .keberadaanUsaha
                                                                            ?.toString();
                                                                    selectedJenisKepemilikan =
                                                                        directory
                                                                            .jenisKepemilikanUsaha
                                                                            ?.toString();
                                                                    selectedBentukBadanHukum =
                                                                        directory
                                                                            .bentukBadanHukumUsaha
                                                                            ?.toString();
                                                                    selectedJaringanUsaha =
                                                                        directory
                                                                            .jaringanUsaha
                                                                            ?.toString();
                                                                    selectedSektorInstitusi =
                                                                        directory
                                                                            .sektorInstitusi
                                                                            ?.toString();
                                                                    selectedTahunBerdiri =
                                                                        directory
                                                                            .tahunBerdiri
                                                                            ?.toString();
                                                                    selectedTenagaKerja =
                                                                        directory
                                                                            .tenagaKerja
                                                                            ?.toString();

                                                                    // Store the selected existing business for reference
                                                                    selectedExistingBusiness =
                                                                        directory;

                                                                    setState(() {
                                                                      showSuggestions =
                                                                          false;
                                                                      businessNameSelected =
                                                                          true;
                                                                      selectedBusinessType =
                                                                          'existing';
                                                                      currentPhase =
                                                                          2;
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
                                                                namaUsahaController
                                                                        .text =
                                                                    directory
                                                                        .namaUsaha;
                                                                alamatController
                                                                        .text =
                                                                    directory
                                                                        .alamat ??
                                                                    '';
                                                                pemilikController
                                                                        .text =
                                                                    directory
                                                                        .pemilik ??
                                                                    '';
                                                                nomorTeleponController
                                                                        .text =
                                                                    directory
                                                                        .nomorTelepon ??
                                                                    '';
                                                                namaKomersialController
                                                                        .text =
                                                                    directory
                                                                        .namaKomersialUsaha ??
                                                                    '';
                                                                nibController
                                                                        .text =
                                                                    directory
                                                                        .nib ??
                                                                    '';
                                                                emailController
                                                                        .text =
                                                                    directory
                                                                        .email ??
                                                                    '';
                                                                websiteController
                                                                        .text =
                                                                    directory
                                                                        .website ??
                                                                    '';
                                                                nomorWhatsappController
                                                                        .text =
                                                                    directory
                                                                        .nomorWhatsapp ??
                                                                    '';
                                                                nikPemilikController
                                                                        .text =
                                                                    directory
                                                                        .nikPemilik ??
                                                                    '';
                                                                kegiatanUsahaController
                                                                        .text =
                                                                    directory
                                                                        .kegiatanUsaha
                                                                        .isNotEmpty
                                                                    ? directory
                                                                          .kegiatanUsaha
                                                                          .map(
                                                                            (
                                                                              k,
                                                                            ) =>
                                                                                k['kegiatan_usaha'] ??
                                                                                '',
                                                                          )
                                                                          .join(
                                                                            ', ',
                                                                          )
                                                                    : '';

                                                                // Set dropdown values
                                                                selectedSkalaUsaha =
                                                                    directory
                                                                        .skalaUsaha;
                                                                selectedJenisPerusahaan =
                                                                    directory
                                                                        .jenisPerusahaan;
                                                                selectedKeberadaanUsaha =
                                                                    directory
                                                                        .keberadaanUsaha
                                                                        ?.toString();
                                                                selectedJenisKepemilikan =
                                                                    directory
                                                                        .jenisKepemilikanUsaha
                                                                        ?.toString();
                                                                selectedBentukBadanHukum =
                                                                    directory
                                                                        .bentukBadanHukumUsaha
                                                                        ?.toString();
                                                                selectedJaringanUsaha =
                                                                    directory
                                                                        .jaringanUsaha
                                                                        ?.toString();
                                                                selectedSektorInstitusi =
                                                                    directory
                                                                        .sektorInstitusi
                                                                        ?.toString();
                                                                selectedTahunBerdiri =
                                                                    directory
                                                                        .tahunBerdiri
                                                                        ?.toString();
                                                                selectedTenagaKerja =
                                                                    directory
                                                                        .tenagaKerja
                                                                        ?.toString();

                                                                // Store the selected existing business for reference
                                                                selectedExistingBusiness =
                                                                    directory;

                                                                setState(() {
                                                                  showSuggestions =
                                                                      false;
                                                                  businessNameSelected =
                                                                      true;
                                                                  selectedBusinessType =
                                                                      'existing';
                                                                  currentPhase =
                                                                      2;
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

                          // MAIN QUESTIONS SECTION
                          Container(
                            padding: const EdgeInsets.all(16),
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.green.shade200),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.assignment,
                                      color: Colors.green.shade700,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Pertanyaan Utama',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),

                                // 1. Alamat
                                TextField(
                                  controller: alamatController,
                                  decoration: const InputDecoration(
                                    labelText: 'Alamat *',
                                    border: OutlineInputBorder(),
                                    helperText: 'Alamat lengkap usaha',
                                  ),
                                  maxLines: 2,
                                ),
                                const SizedBox(height: 16),

                                // 2. KBLI Code (5 digits)
                                TextField(
                                  controller: kbliController,
                                  decoration: const InputDecoration(
                                    labelText: 'Kode KBLI *',
                                    border: OutlineInputBorder(),
                                    hintText: 'Contoh: 47111',
                                    helperText: 'Kode KBLI harus 5 digit angka',
                                  ),
                                  keyboardType: TextInputType.number,
                                  maxLength: 5,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                  onChanged: (value) {
                                    // Validate KBLI format
                                    if (value.length == 5) {
                                      // Valid KBLI
                                    }
                                  },
                                ),
                                const SizedBox(height: 16),

                                // 3. Deskripsi Badan Usaha
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    TextField(
                                      controller: deskripsiBadanUsahaController,
                                      decoration: const InputDecoration(
                                        labelText: 'Deskripsi Detail Usaha',
                                        border: OutlineInputBorder(),
                                        hintText:
                                            'Jelaskan secara detail kegiatan usaha Anda',
                                      ),
                                      maxLines: 3,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),

                                // 4. Tag Multi-Selection
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Tag/Kategori',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                    const SizedBox(height: 8),

                                    // Selected tags display
                                    if (selectedTags.isNotEmpty)
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: Colors.grey.shade300,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: selectedTags.map((tag) {
                                            return Chip(
                                              label: Text(tag),
                                              deleteIcon: const Icon(
                                                Icons.close,
                                                size: 18,
                                              ),
                                              onDeleted: () {
                                                setState(() {
                                                  selectedTags.remove(tag);
                                                  tagController.text =
                                                      selectedTags.join(', ');
                                                });
                                              },
                                              backgroundColor:
                                                  Colors.blue.shade100,
                                              deleteIconColor:
                                                  Colors.blue.shade700,
                                            );
                                          }).toList(),
                                        ),
                                      ),

                                    const SizedBox(height: 8),

                                    // Tag input field
                                    Row(
                                      children: [
                                        Expanded(
                                          child: TextField(
                                            controller: tagController,
                                            decoration: const InputDecoration(
                                              labelText: 'Tambah Tag',
                                              border: OutlineInputBorder(),
                                              hintText:
                                                  'Ketik tag dan tekan Enter',
                                            ),
                                            onSubmitted: (value) {
                                              if (value.trim().isNotEmpty &&
                                                  !selectedTags.contains(
                                                    value.trim(),
                                                  )) {
                                                setState(() {
                                                  selectedTags.add(
                                                    value.trim(),
                                                  );
                                                  tagController.clear();
                                                });
                                              }
                                            },
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        IconButton(
                                          onPressed: () {
                                            final value = tagController.text
                                                .trim();
                                            if (value.isNotEmpty &&
                                                !selectedTags.contains(value)) {
                                              setState(() {
                                                selectedTags.add(value);
                                                tagController.clear();
                                              });
                                            }
                                          },
                                          icon: const Icon(Icons.add),
                                          style: IconButton.styleFrom(
                                            backgroundColor:
                                                Colors.blue.shade100,
                                            foregroundColor:
                                                Colors.blue.shade700,
                                          ),
                                        ),
                                      ],
                                    ),

                                    // Predefined tags
                                    const SizedBox(height: 8),
                                    Text(
                                      'Tag Populer:',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 4,
                                      children:
                                          [
                                            'Sekolah',
                                            'Hotel',
                                            'Cafe',
                                            'Restoran',
                                            'Toko',
                                            'Bengkel',
                                            'Klinik',
                                            'Bank',
                                          ].map((tag) {
                                            final isSelected = selectedTags
                                                .contains(tag);
                                            return FilterChip(
                                              label: Text(tag),
                                              selected: isSelected,
                                              onSelected: (selected) {
                                                setState(() {
                                                  if (selected) {
                                                    selectedTags.add(tag);
                                                  } else {
                                                    selectedTags.remove(tag);
                                                  }
                                                });
                                              },
                                              selectedColor:
                                                  Colors.blue.shade200,
                                              checkmarkColor:
                                                  Colors.blue.shade700,
                                            );
                                          }).toList(),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),

                                // 5. Upload Gambar
                                ImageUploadWidget(
                                  onImageUploaded: (imageUrl) {
                                    setState(() {
                                      urlGambarController.text = imageUrl;
                                    });
                                  },
                                  initialImageUrl:
                                      urlGambarController.text.isNotEmpty
                                      ? urlGambarController.text
                                      : null,
                                  hintText: 'Upload gambar usaha (opsional)',
                                ),
                              ],
                            ),
                          ),

                          // CONTINUE BUTTON
                          if (!showFollowUpQuestions)
                            Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(bottom: 16),
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  setState(() {
                                    showFollowUpQuestions = true;
                                  });
                                },
                                icon: const Icon(Icons.expand_more),
                                label: const Text('Lanjutan (Opsional)'),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  side: BorderSide(color: Colors.blue.shade300),
                                ),
                              ),
                            ),

                          // FOLLOW-UP QUESTIONS SECTION
                          if (showFollowUpQuestions) ...[
                            Container(
                              padding: const EdgeInsets.all(16),
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.orange.shade200,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.assignment_outlined,
                                        color: Colors.orange.shade700,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Pertanyaan Lanjutan (Opsional)',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.orange.shade700,
                                        ),
                                      ),
                                      const Spacer(),
                                      TextButton(
                                        onPressed: () {
                                          setState(() {
                                            showFollowUpQuestions = false;
                                          });
                                        },
                                        child: const Text('Sembunyikan'),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),

                                  // Contact Information
                                  Text(
                                    'Informasi Kontak',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
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
                                    controller: emailController,
                                    decoration: const InputDecoration(
                                      labelText: 'Email',
                                      border: OutlineInputBorder(),
                                    ),
                                    keyboardType: TextInputType.emailAddress,
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
                                  const SizedBox(height: 16),

                                  // Business Details
                                  Text(
                                    'Detail Usaha',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  TextField(
                                    controller: namaKomersialController,
                                    decoration: const InputDecoration(
                                      labelText: 'Nama Komersial',
                                      border: OutlineInputBorder(),
                                    ),
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
                                  const SizedBox(height: 16),

                                  // Legal Information
                                  Text(
                                    'Informasi Legal',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  TextField(
                                    controller: nibController,
                                    decoration: const InputDecoration(
                                      labelText: 'NIB (Nomor Induk Berusaha)',
                                      border: OutlineInputBorder(),
                                    ),
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
                                        child: Text(
                                          'CV (Commanditaire Vennootschap)',
                                        ),
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
                                      DropdownMenuItem(
                                        value: '8',
                                        child: Text('BUMN'),
                                      ),
                                      DropdownMenuItem(
                                        value: '9',
                                        child: Text('BUMD'),
                                      ),
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
                                  const SizedBox(height: 16),

                                  // Additional Information
                                  Text(
                                    'Informasi Tambahan',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
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
                                ],
                              ),
                            ),
                          ],

                          const SizedBox(height: 12),
                          const Text(
                            'Hanya nama usaha dan alamat yang wajib diisi. Field lainnya opsional.',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),

                          // Navigation buttons for Phase 2 (New Directory)
                          if (existingDirectory == null && currentPhase == 2)
                            SafeArea(
                              minimum: const EdgeInsets.only(bottom: 16),
                              child: Container(
                                margin: const EdgeInsets.only(top: 16),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
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
                                              nomorTeleponController.text
                                                  .trim(),
                                              scaffoldMessenger,
                                              mapBloc,
                                              scrapedPlaceId: scrapedPlaceId,
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
                                                  : websiteController.text
                                                        .trim(),
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
                                              tahunBerdiri:
                                                  selectedTahunBerdiri,
                                              tenagaKerja: selectedTenagaKerja,
                                              // New fields
                                              kbli:
                                                  kbliController.text
                                                      .trim()
                                                      .isEmpty
                                                  ? null
                                                  : kbliController.text.trim(),
                                              tag: selectedTags.isEmpty
                                                  ? null
                                                  : selectedTags,
                                              urlGambar:
                                                  urlGambarController.text
                                                      .trim()
                                                      .isEmpty
                                                  ? null
                                                  : urlGambarController.text
                                                        .trim(),
                                              existingDirectory:
                                                  existingDirectory,
                                              selectedExistingBusiness:
                                                  selectedExistingBusiness,
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
                            ),

                          // Save button for Edit Mode
                          if (existingDirectory != null)
                            SafeArea(
                              minimum: const EdgeInsets.only(bottom: 16),
                              child: Container(
                                margin: const EdgeInsets.only(top: 16),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: () async {
                                    final namaUsaha = namaUsahaController.text
                                        .trim();
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
                                          'Apakah Anda yakin ingin menyimpan perubahan direktori "$namaUsaha"?',
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
                                      final mapBloc = context.read<MapBloc>();

                                      await _saveDirektori(
                                        context,
                                        point,
                                        namaUsaha,
                                        alamatController.text.trim(),
                                        pemilikController.text.trim(),
                                        nomorTeleponController.text.trim(),
                                        scaffoldMessenger,
                                        mapBloc,
                                        scrapedPlaceId: scrapedPlaceId,
                                        namaKomersial:
                                            namaKomersialController.text
                                                .trim()
                                                .isEmpty
                                            ? null
                                            : namaKomersialController.text
                                                  .trim(),
                                        nib: nibController.text.trim().isEmpty
                                            ? null
                                            : nibController.text.trim(),
                                        email:
                                            emailController.text.trim().isEmpty
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
                                            : nikPemilikController.text.trim(),
                                        keterangan:
                                            keteranganController.text
                                                .trim()
                                                .isEmpty
                                            ? null
                                            : keteranganController.text.trim(),
                                        kegiatanUsaha:
                                            kegiatanUsahaController.text
                                                .trim()
                                                .isEmpty
                                            ? null
                                            : kegiatanUsahaController.text
                                                  .trim(),
                                        deskripsiBadanUsaha:
                                            deskripsiBadanUsahaController.text
                                                .trim()
                                                .isEmpty
                                            ? null
                                            : deskripsiBadanUsahaController.text
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
                                        jaringanUsaha: selectedJaringanUsaha,
                                        sektorInstitusi:
                                            selectedSektorInstitusi,
                                        tahunBerdiri: selectedTahunBerdiri,
                                        tenagaKerja: selectedTenagaKerja,
                                        // New fields
                                        kbli: kbliController.text.trim().isEmpty
                                            ? null
                                            : kbliController.text.trim(),
                                        tag: selectedTags.isEmpty
                                            ? null
                                            : selectedTags,
                                        urlGambar:
                                            urlGambarController.text
                                                .trim()
                                                .isEmpty
                                            ? null
                                            : urlGambarController.text.trim(),
                                        existingDirectory: existingDirectory,
                                        selectedExistingBusiness: null,
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
                                  child: const Text('Simpan Perubahan'),
                                ),
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
      if (MapUtils.isPointInPolygon(newPoint, polygon.points)) {
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
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text(
              'Konfirmasi Pemindahan Lokasi',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
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
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Batal'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Pindahkan'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      try {
        final repository = MapRepositoryImpl();
        final success = await repository
            .updateDirectoryCoordinatesWithRegionalData(
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
          // Emit contribution for drag-and-drop coordinate update
          try {
            final contributionBloc = context.read<ContributionBloc>();
            // Old coordinates from existing place position
            final oldLat = place.position.latitude;
            final oldLon = place.position.longitude;
            String? actionSubtype;
            double? distance;
            // Calculate Haversine distance
            const double R = 6371000; // meters
            final dLat =
                (newPoint.latitude - oldLat) * (3.141592653589793 / 180);
            final dLon =
                (newPoint.longitude - oldLon) * (3.141592653589793 / 180);
            final a =
                (math.sin(dLat / 2) * math.sin(dLat / 2)) +
                math.cos(oldLat * (3.141592653589793 / 180)) *
                    math.cos(newPoint.latitude * (3.141592653589793 / 180)) *
                    (math.sin(dLon / 2) * math.sin(dLon / 2));
            final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
            distance = R * c;
            if (distance >= 0.01) {
              actionSubtype = distance >= 20
                  ? 'update_coordinates_major'
                  : 'update_coordinates_minor';
            }

            if (actionSubtype != null) {
              final changes = <String, dynamic>{
                'nama_usaha': place.name,
                'latitude': newPoint.latitude,
                'longitude': newPoint.longitude,
                'target_uuid': place.id,
                'timestamp': DateTime.now().toIso8601String(),
                'distance_moved_m': distance,
              };
              contributionBloc.add(
                CreateContributionEvent(
                  actionType: actionSubtype,
                  targetType: 'directory',
                  targetId: place.id,
                  changes: changes,
                  latitude: newPoint.latitude,
                  longitude: newPoint.longitude,
                ),
              );
            }
          } catch (e) {
            // Ignore contribution errors
          }
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

  void _confirmMoveGroundcheckCoordinates(
    BuildContext context,
    Place place,
    LatLng newPoint,
  ) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final mapBloc = context.read<MapBloc>();
    final idsbr = place.id.startsWith('gc:') ? place.id.substring(3) : place.id;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text(
              'Konfirmasi Pemindahan Marker Groundcheck',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Text('Pindahkan "${place.name}" ke lokasi baru?'),
            const SizedBox(height: 8),
            Text('Latitude: ${newPoint.latitude.toStringAsFixed(6)}'),
            Text('Longitude: ${newPoint.longitude.toStringAsFixed(6)}'),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Batal'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Pindahkan'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      try {
        final service = GroundcheckSupabaseService();
        final success = await service.updateCoordinates(
          idsbr: idsbr,
          latitude: newPoint.latitude,
          longitude: newPoint.longitude,
        );
        if (success) {
          scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Text(
                'Lokasi groundcheck "${place.name}" berhasil diperbarui',
              ),
              backgroundColor: Colors.green,
            ),
          );
          try {
            MapRepositoryImpl().invalidatePlacesCache();
          } catch (_) {}
          mapBloc.add(const PlacesRequested());
        } else {
          scaffoldMessenger.showSnackBar(
            const SnackBar(
              content: Text('Gagal memperbarui lokasi groundcheck'),
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

  Widget _getPlaceIcon(Place p) {
    IconData icon;
    Color color;
    switch (p.gcsResult) {
      case '1': // Ditemukan
        color = Colors.green;
        icon = Icons.check_circle;
        break;
      case '99': // Tidak ditemukan
        color = Colors.red;
        icon = Icons.cancel;
        break;
      case '3': // Tutup
        color = Colors.pinkAccent;
        icon = Icons.block;
        break;
      case '4': // Ganda
        color = Colors.purple;
        icon = Icons.content_copy;
        break;
      case '5': // Usaha Baru
        color = Colors.blue;
        icon = Icons.add_location;
        break;
      default: // Belum Groundcheck (null/empty)
        color = Colors.orange;
        icon = Icons.help;
        break;
    }
    return Icon(icon, color: color);
  }

  void _showNearbyGroundcheckPopup(
    BuildContext context,
    List<Place> places,
  ) async {
    final mutablePlaces = List<Place>.from(places);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (dialogContext) {
        return DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.3,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return StatefulBuilder(
              builder: (ctx, setState) {
                return Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                  ),
                  child: Column(
                    children: [
                      Center(
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 12),
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Lokasi Groundcheck berdekatan',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: ListView.separated(
                          controller: scrollController,
                          padding: const EdgeInsets.only(
                            left: 16,
                            right: 16,
                            top: 16,
                            bottom: 80,
                          ),
                          itemCount: mutablePlaces.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 16),
                          itemBuilder: (_, i) {
                            final p = mutablePlaces[i];
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    _getPlaceIcon(p),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            p.name,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          if (p.address != null &&
                                              p.address!.isNotEmpty)
                                            Text(
                                              'Alamat: ${p.address!}',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey[600],
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          if (p.statusPerusahaan != null &&
                                              p.statusPerusahaan!.isNotEmpty)
                                            Text(
                                              'Status: ${p.statusPerusahaan}',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: Colors.blue,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),

                                    IconButton(
                                      icon: const Icon(
                                        Icons.streetview,
                                        color: Colors.blue,
                                      ),
                                      tooltip: 'Lihat Street View',
                                      onPressed: () async {
                                        final url = Uri.parse(
                                          'https://www.google.com/maps/@?api=1&map_action=pano&viewpoint=${p.position.latitude},${p.position.longitude}',
                                        );
                                        if (!await launchUrl(
                                          url,
                                          mode: LaunchMode.externalApplication,
                                        )) {
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  'Tidak dapat membuka Street View',
                                                ),
                                              ),
                                            );
                                          }
                                        }
                                      },
                                    ),
                                    if (p.gcsResult == '5')
                                      IconButton(
                                        icon: const Icon(
                                          Icons.delete,
                                          color: Colors.red,
                                        ),
                                        tooltip: 'Hapus Marker Tambahan',
                                        onPressed: () async {
                                          if (!context.mounted) return;
                                          final confirmed = await showDialog<bool>(
                                            context: context,
                                            builder: (ctx) => AlertDialog(
                                              title: const Text(
                                                'Hapus Marker?',
                                              ),
                                              content: const Text(
                                                'Marker tambahan ini akan dihapus permanen. Lanjutkan?',
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () => Navigator.of(
                                                    ctx,
                                                  ).pop(false),
                                                  child: const Text('Batal'),
                                                ),
                                                TextButton(
                                                  onPressed: () => Navigator.of(
                                                    ctx,
                                                  ).pop(true),
                                                  style: TextButton.styleFrom(
                                                    foregroundColor: Colors.red,
                                                  ),
                                                  child: const Text('Hapus'),
                                                ),
                                              ],
                                            ),
                                          );

                                          if (confirmed == true &&
                                              context.mounted) {
                                            final repo = MapRepositoryImpl();
                                            final idsbr = p.id.replaceFirst(
                                              'gc:',
                                              '',
                                            );
                                            final success = await repo
                                                .deleteOrCloseDirectoryById(
                                                  idsbr,
                                                );

                                            if (success &&
                                                dialogContext.mounted) {
                                              setState(() {
                                                mutablePlaces.removeAt(i);
                                              });
                                              // Force refresh map
                                              context.read<MapBloc>().add(
                                                const PlacesRefreshRequested(
                                                  onlyToday: true,
                                                ),
                                              );
                                              if (mutablePlaces.isEmpty) {
                                                Navigator.of(
                                                  dialogContext,
                                                ).pop();
                                              } else if (mutablePlaces.length ==
                                                  1) {
                                                Navigator.of(
                                                  dialogContext,
                                                ).pop();
                                              }
                                              if (context.mounted) {
                                                ScaffoldMessenger.of(
                                                  context,
                                                ).showSnackBar(
                                                  const SnackBar(
                                                    content: Text(
                                                      'Marker berhasil dihapus',
                                                    ),
                                                    backgroundColor:
                                                        Colors.green,
                                                  ),
                                                );
                                              }
                                            } else if (context.mounted) {
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                const SnackBar(
                                                  content: Text(
                                                    'Gagal menghapus marker',
                                                  ),
                                                  backgroundColor: Colors.red,
                                                ),
                                              );
                                            }
                                          }
                                        },
                                      )
                                    else
                                      IconButton(
                                        icon: const Icon(
                                          Icons.edit,
                                          color: Colors.orange,
                                        ),
                                        tooltip: 'Update status',
                                        onPressed: () async {
                                          if (!context.mounted) return;
                                          final newCode =
                                              await _showUpdateGroundcheckStatusDialog(
                                                context,
                                                p,
                                              );

                                          if (!dialogContext.mounted) return;

                                          if (newCode != null) {
                                            setState(() {
                                              mutablePlaces[i] = Place(
                                                id: p.id,
                                                name: p.name,
                                                description: p.description,
                                                position: p.position,
                                                urlGambar: p.urlGambar,
                                                gcsResult: newCode,
                                                address: p.address,
                                                statusPerusahaan:
                                                    p.statusPerusahaan,
                                              );
                                            });
                                            if (mutablePlaces.length == 1) {
                                              Navigator.of(dialogContext).pop();
                                            }
                                          }
                                        },
                                      ),
                                  ],
                                ),
                              ],
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

  Future<String?> _showUpdateGroundcheckStatusDialog(
    BuildContext context,
    Place place,
  ) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final mapBloc = context.read<MapBloc>();
    final idsbr = place.id.replaceFirst('gc:', '');
    if (idsbr.isEmpty) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('ID groundcheck tidak valid'),
          backgroundColor: Colors.red,
        ),
      );
      return null;
    }

    String normalize(String? value) {
      if (value == null) return '';
      if (value == '0') return '99';
      return value;
    }

    final currentCode = normalize(place.gcsResult);
    String selectedCode = currentCode;
    bool isExpanded = false;
    final nameController = TextEditingController(text: place.name);
    final addressController = TextEditingController(text: place.address ?? '');

    final options = <Map<String, String>>[
      {'code': '', 'label': 'Belum Groundcheck'},
      {'code': '1', 'label': '1. Ditemukan'},
      {'code': '99', 'label': '99. Tidak Ditemukan'},
      {'code': '3', 'label': '3. Tutup'},
      {'code': '4', 'label': '4. Ganda'},
    ];

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateSB) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                padding: const EdgeInsets.only(bottom: 24),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 12),
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Update Status Groundcheck',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () => Navigator.of(ctx).pop(null),
                            ),
                          ],
                        ),
                      ),
                      const Divider(),
                      ...options.map((o) {
                        final code = o['code']!;
                        final label = o['label']!;
                        return RadioListTile<String>(
                          value: code,
                          groupValue: selectedCode,
                          title: Text(label),
                          onChanged: (value) {
                            setStateSB(() {
                              selectedCode = value ?? '';
                            });
                          },
                        );
                      }),
                      const Divider(),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: InkWell(
                          onTap: () {
                            setStateSB(() {
                              isExpanded = !isExpanded;
                            });
                          },
                          child: Row(
                            children: [
                              Icon(
                                isExpanded
                                    ? Icons.keyboard_arrow_up
                                    : Icons.keyboard_arrow_down,
                                color: Colors.blue,
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Edit Nama & Alamat Usaha',
                                style: TextStyle(
                                  color: Colors.blue,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (isExpanded) ...[
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: TextField(
                            controller: nameController,
                            decoration: const InputDecoration(
                              labelText: 'Nama Usaha',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: TextField(
                            controller: addressController,
                            decoration: const InputDecoration(
                              labelText: 'Alamat Usaha',
                              border: OutlineInputBorder(),
                            ),
                            maxLines: 2,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () => Navigator.of(ctx).pop({
                            'confirmed': true,
                            'selectedCode': selectedCode,
                            'name': nameController.text.trim(),
                            'address': addressController.text.trim(),
                          }),
                          child: const Text('Simpan'),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (result == null || result['confirmed'] != true) return null;

    final newCode = result['selectedCode'] as String;
    final newName = result['name'] as String;
    final newAddress = result['address'] as String;

    // Check if anything changed
    final codeChanged = newCode != currentCode;
    final nameChanged = newName != place.name;
    final addressChanged = newAddress != (place.address ?? '');

    if (!codeChanged && !nameChanged && !addressChanged) {
      return null;
    }

    try {
      final service = GroundcheckSupabaseService();
      final userId = await service.fetchCurrentUserId();
      final ok = await service.updateGcsResult(
        idsbr,
        newCode,
        userId: userId,
        namaUsaha: nameChanged ? newName : null,
        alamatUsaha: addressChanged ? newAddress : null,
      );
      if (!ok) {
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text('Gagal mengupdate status groundcheck'),
            backgroundColor: Colors.red,
          ),
        );
        return null;
      }
      try {
        MapRepositoryImpl().invalidatePlacesCache();
      } catch (_) {}
      mapBloc.add(const PlacesRequested());
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('Status groundcheck berhasil diupdate'),
          backgroundColor: Colors.green,
        ),
      );
      return selectedCode;
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
      return null;
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
    LatLng point, {
    VoidCallback? onSuccess,
  }) async {
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
      if (MapUtils.isPointInPolygon(point, polygon.points)) {
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
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text(
              'Konfirmasi Update',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
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
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Batal'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Update'),
                  ),
                ),
              ],
            ),
          ],
        ),
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

          // Emit contribution for coordinate update
          try {
            final contributionBloc = context.read<ContributionBloc>();
            // Determine old vs new coordinates
            final oldLat = directory.latitude ?? directory.lat;
            final oldLon = directory.longitude ?? directory.long;
            String? actionSubtype;
            double? distance;
            if (oldLat == null || oldLon == null) {
              actionSubtype = 'set_first_coordinates';
            } else {
              // Haversine distance
              const double R = 6371000; // meters
              final dLat =
                  (point.latitude - oldLat) * (3.141592653589793 / 180);
              final dLon =
                  (point.longitude - oldLon) * (3.141592653589793 / 180);
              final a =
                  (math.sin(dLat / 2) * math.sin(dLat / 2)) +
                  math.cos(oldLat * (3.141592653589793 / 180)) *
                      math.cos(point.latitude * (3.141592653589793 / 180)) *
                      (math.sin(dLon / 2) * math.sin(dLon / 2));
              final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
              distance = R * c;
              if (distance >= 0.01) {
                actionSubtype = distance >= 20
                    ? 'update_coordinates_major'
                    : 'update_coordinates_minor';
              }
            }

            if (actionSubtype != null) {
              final changes = <String, dynamic>{
                'nama_usaha': directory.namaUsaha,
                'latitude': point.latitude,
                'longitude': point.longitude,
                'target_uuid': directory.id,
                'timestamp': DateTime.now().toIso8601String(),
                if (distance != null) 'distance_moved_m': distance,
              };
              contributionBloc.add(
                CreateContributionEvent(
                  actionType: actionSubtype,
                  targetType: 'directory',
                  targetId: directory.id,
                  changes: changes,
                  latitude: point.latitude,
                  longitude: point.longitude,
                ),
              );
            }
          } catch (e) {
            // Ignore contribution errors
          }

          // Refresh the map data
          mapBloc.add(const PlacesRequested());

          // Notify caller (e.g., to exit coordinate mode)
          onSuccess?.call();
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

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          padding: EdgeInsets.fromLTRB(
            20,
            8,
            20,
            MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text(
                      'Pilih Direktori untuk Update Koordinat',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
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
    String? kbli, // New KBLI parameter
    List<String>? tag, // New tag parameter
    String? urlGambar, // New URL gambar parameter
    String?
    scrapedPlaceId, // Optional scraped place id for Sheets status update
    DirektoriModel? existingDirectory,
    DirektoriModel? selectedExistingBusiness,
  }) async {
    print('🔄 [DEBUG] Memulai proses penyimpanan direktori...');
    print('📍 [DEBUG] Koordinat: ${point.latitude}, ${point.longitude}');
    print('🏢 [DEBUG] Nama Usaha: $namaUsaha');
    print('📍 [DEBUG] Alamat: $alamat');
    print('👤 [DEBUG] Pemilik: $pemilik');
    print('📞 [DEBUG] Nomor Telepon: $nomorTelepon');

    // Get ContributionBloc reference early to avoid widget deactivation issues
    ContributionBloc? contributionBloc;
    try {
      // Check that context is still mounted
      if (context.mounted) {
        contributionBloc = context.read<ContributionBloc>();
        print('✅ [CONTRIBUTION] ContributionBloc berhasil diakses');
      } else {
        print('⚠️ [CONTRIBUTION] Context tidak mounted');
      }
    } catch (e) {
      print('⚠️ [CONTRIBUTION] Tidak dapat mengakses ContributionBloc: $e');
    }

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
        if (MapUtils.isPointInPolygon(point, polygon.points)) {
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
            selectedExistingBusiness?.id ??
            '', // Use existing ID for updates (including selectedExistingBusiness), empty for new
        idSbr:
            selectedExistingBusiness?.idSbr ??
            existingDirectory?.idSbr ??
            '0', // Use selected business id_sbr if available
        namaUsaha: namaUsaha,
        namaKomersialUsaha: namaKomersial,
        alamat: alamat, // Gunakan input pengguna dari alamatController
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
        urlGambar: urlGambar?.trim().isNotEmpty == true
            ? urlGambar!.trim()
            : existingDirectory?.urlGambar,
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
        // New fields
        kbli: kbli,
        tag: tag,
      );

      print('💾 [DEBUG] Menyimpan ke database...');
      final repository = MapRepositoryImpl();
      bool success = false;
      String? newDirectoryId;

      if (existingDirectory != null || selectedExistingBusiness != null) {
        // Update existing directory
        final updateId = existingDirectory?.id ?? selectedExistingBusiness?.id;
        print(
          '🔄 [DEBUG] Mengupdate direktori yang sudah ada dengan ID: $updateId',
        );
        success = await repository.updateDirectory(directory);
      } else {
        // Insert new directory and get the new ID
        print('➕ [DEBUG] Menambah direktori baru');
        newDirectoryId = await repository.insertDirectoryAndGetId(directory);
        success = newDirectoryId != null;
        if (success) {
          print(
            '✅ [DEBUG] Direktori baru berhasil disimpan dengan ID: $newDirectoryId',
          );
        }
      }

      print('📊 [DEBUG] Hasil penyimpanan: ${success ? "BERHASIL" : "GAGAL"}');

      if (success) {
        print(
          '✅ [DEBUG] Direktori berhasil disimpan, menampilkan SnackBar sukses',
        );

        // Save contribution after successful directory save
        try {
          print('💾 [CONTRIBUTION] Menyimpan kontribusi...');

          if (contributionBloc != null) {
            // Determine action type and changes
            final originalDirectory =
                existingDirectory ?? selectedExistingBusiness;
            final actionType = originalDirectory != null
                ? 'edit_location'
                : 'add_location';
            final targetId = originalDirectory?.id ?? newDirectoryId ?? '';

            // Skip contribution if we don't have a valid target_id
            if (targetId.isEmpty) {
              print(
                '⚠️ [CONTRIBUTION] Melewati penyimpanan kontribusi karena target_id kosong',
              );
            } else {
              print('🎯 [CONTRIBUTION] Action: $actionType, Target: $targetId');

              // Create changes map for tracking what was modified
              final changes = <String, dynamic>{
                'nama_usaha': namaUsaha,
                'alamat': alamatFromGeocode ?? alamat,
                'latitude': point.latitude,
                'longitude': point.longitude,
                // Keep UUID reference because contributions table uses BIGINT target_id
                // This allows us to trace back to the new directory even if target_id is null
                'target_uuid': targetId,
                'timestamp': DateTime.now().toIso8601String(),
              };

              if (originalDirectory != null) {
                // For updates, track what changed
                if (originalDirectory.namaUsaha != namaUsaha) {
                  changes['old_nama_usaha'] = originalDirectory.namaUsaha;
                }
                if (originalDirectory.alamat != (alamatFromGeocode ?? alamat)) {
                  changes['old_alamat'] = originalDirectory.alamat;
                }
              }

              print('📝 [CONTRIBUTION] Changes (umum): $changes');

              // Tentukan event utama untuk menghindari duplikasi
              // - Jika direktori baru: gunakan add_directory_manual / add_directory_scrape
              // - Jika update koordinat: gunakan set_first_coordinates / update_coordinates_major|minor
              String? primaryAction;

              // Helper hitung jarak (meter) antara koordinat lama dan baru
              double _distanceMeters(
                double lat1,
                double lon1,
                double lat2,
                double lon2,
              ) {
                const double R = 6371000; // Earth radius in meters
                final dLat = (lat2 - lat1) * (3.141592653589793 / 180);
                final dLon = (lon2 - lon1) * (3.141592653589793 / 180);
                final a =
                    (math.sin(dLat / 2) * math.sin(dLat / 2)) +
                    math.cos(lat1 * (3.141592653589793 / 180)) *
                        math.cos(lat2 * (3.141592653589793 / 180)) *
                        (math.sin(dLon / 2) * math.sin(dLon / 2));
                final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
                return R * c;
              }

              if (originalDirectory == null) {
                // Direktori baru
                if (scrapedPlaceId != null &&
                    scrapedPlaceId.startsWith('scrape:')) {
                  primaryAction = 'add_directory_scrape';
                } else {
                  primaryAction = 'add_directory_manual';
                }
              } else {
                // Update direktori: cek perubahan koordinat
                final oldLat =
                    originalDirectory.latitude ?? originalDirectory.lat;
                final oldLon =
                    originalDirectory.longitude ?? originalDirectory.long;
                if (oldLat == null || oldLon == null) {
                  primaryAction = 'set_first_coordinates';
                } else {
                  final dist = _distanceMeters(
                    oldLat,
                    oldLon,
                    point.latitude,
                    point.longitude,
                  );
                  if (dist >= 0.01) {
                    // anggap 0 jika sama persis, toleransi kecil
                    primaryAction = dist >= 20
                        ? 'update_coordinates_major'
                        : 'update_coordinates_minor';
                    changes['distance_moved_m'] = dist;
                  }
                }
              }

              // Generate satu operation_id untuk semua event dalam satu penyimpanan
              final opId = const Uuid().v4();
              if (primaryAction != null) {
                contributionBloc.add(
                  CreateContributionEvent(
                    actionType: primaryAction,
                    targetType: 'directory',
                    targetId: targetId,
                    changes: changes,
                    latitude: point.latitude,
                    longitude: point.longitude,
                    operationId: opId,
                  ),
                );
                print('✅ [CONTRIBUTION] Event utama dikirim: $primaryAction');
              } else {
                print(
                  'ℹ️ [CONTRIBUTION] Tidak ada perubahan koordinat signifikan, skip event utama',
                );
              }

              // Emit kontribusi tambahan untuk pengayaan data (KBLI, deskripsi, alamat, foto)
              final nowIso = DateTime.now().toIso8601String();

              void emit(String type, Map<String, dynamic> ch) {
                contributionBloc!.add(
                  CreateContributionEvent(
                    actionType: type,
                    targetType: 'directory',
                    targetId: targetId,
                    changes: ch,
                    latitude: point.latitude,
                    longitude: point.longitude,
                    operationId: opId,
                  ),
                );
              }

              // KBLI
              final oldKbli = (existingDirectory?.kbli ?? '').trim();
              final newKbli = (kbli ?? '').trim();
              if (newKbli.isNotEmpty && newKbli != oldKbli) {
                final type = oldKbli.isEmpty ? 'add_kbli' : 'update_kbli';
                emit(type, {
                  'kbli': newKbli,
                  if (oldKbli.isNotEmpty) 'old_kbli': oldKbli,
                  'target_uuid': targetId,
                  'timestamp': nowIso,
                });
                print('✅ [CONTRIBUTION] Event $type (KBLI) dikirim');
              }

              // Deskripsi usaha
              final oldDesc =
                  (existingDirectory?.deskripsiBadanUsahaLainnya ?? '').trim();
              final newDesc = (deskripsiBadanUsaha ?? '').trim();
              if (newDesc.isNotEmpty && newDesc != oldDesc) {
                final type = oldDesc.isEmpty
                    ? 'add_description'
                    : 'update_description';
                emit(type, {
                  'description': newDesc,
                  if (oldDesc.isNotEmpty) 'old_description': oldDesc,
                  'target_uuid': targetId,
                  'timestamp': nowIso,
                });
                print('✅ [CONTRIBUTION] Event $type (deskripsi) dikirim');
              }

              // Alamat presisi
              final oldAddr = (existingDirectory?.alamat ?? '').trim();
              final newAddr = (alamatFromGeocode ?? alamat).trim();
              // Jika event utama adalah add_directory_scrape, jangan emit add/update_address
              if (primaryAction != 'add_directory_scrape' &&
                  newAddr.isNotEmpty &&
                  newAddr != oldAddr) {
                final type = oldAddr.isEmpty ? 'add_address' : 'update_address';
                emit(type, {
                  'address': newAddr,
                  if (oldAddr.isNotEmpty) 'old_address': oldAddr,
                  'target_uuid': targetId,
                  'timestamp': nowIso,
                });
                print('✅ [CONTRIBUTION] Event $type (alamat) dikirim');
              }

              // Foto
              final oldPhoto = (existingDirectory?.urlGambar ?? '').trim();
              final newPhoto = (urlGambar ?? '').trim();
              // Jika event utama adalah add_directory_scrape, jangan emit add/update_photo
              if (primaryAction != 'add_directory_scrape' &&
                  newPhoto.isNotEmpty &&
                  newPhoto != oldPhoto) {
                final type = oldPhoto.isEmpty ? 'add_photo' : 'update_photo';
                emit(type, {
                  'photo_url': newPhoto,
                  if (oldPhoto.isNotEmpty) 'old_photo_url': oldPhoto,
                  'target_uuid': targetId,
                  'timestamp': nowIso,
                });
                print('✅ [CONTRIBUTION] Event $type (foto) dikirim');
              }

              // Tautkan kontribusi lama yang hanya menyimpan UUID di changes
              if (newDirectoryId != null && contributionBloc != null) {
                contributionBloc.add(
                  LinkContributionsToDirectoryEvent(
                    directoryId: newDirectoryId,
                  ),
                );
                print(
                  '🔗 [CONTRIBUTION] Meminta penautan kontribusi ke direktori $newDirectoryId',
                );
              }
            }
          } else {
            print(
              '⚠️ [CONTRIBUTION] ContributionBloc tidak tersedia, melewati penyimpanan kontribusi',
            );
          }
        } catch (contributionError) {
          print(
            '❌ [CONTRIBUTION] Gagal menyimpan kontribusi: $contributionError',
          );
          // Don't fail the whole operation if contribution fails
        }

        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text('Direktori "$namaUsaha" berhasil disimpan'),
            backgroundColor: Colors.green,
          ),
        );

        // If this save originated from a scraped place, mark status in Google Sheets
        if (scrapedPlaceId != null && scrapedPlaceId.startsWith('scrape:')) {
          try {
            debugPrint(
              'Sheets: updating status to "ditambah" for $scrapedPlaceId',
            );
            final ok = await ScrapingRepositoryImpl().updateStatusByPlaceId(
              scrapedPlaceId,
              'ditambah',
            );
            if (!ok) {
              debugPrint('Sheets: failed to update status for $scrapedPlaceId');
            }
          } catch (e) {
            debugPrint('Sheets: error updating status: $e');
          }
        }

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
      if (MapUtils.isPointInPolygon(point, polygon.points)) {
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

  // Update Google Sheets status for a scraped marker by its placeId
  Future<void> _updateScrapeStatus(
    BuildContext context,
    Place place,
    String status,
  ) async {
    try {
      final ok = await ScrapingRepositoryImpl().updateStatusByPlaceId(
        place.id,
        status,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'Status "$status" terkirim ke Google Sheets'
                : 'Gagal mengirim status ke Google Sheets',
          ),
          backgroundColor: ok ? Colors.green : Colors.red,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error update status: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Open Google Maps link for a scraped marker using its cached scraped data.
  Future<void> _openScrapeGoogleMapsLink(
    BuildContext context,
    Place place,
  ) async {
    try {
      final repo = ScrapingRepositoryImpl();
      final sp = await repo.getByPlaceId(place.id);

      String? urlStr = sp?.link;
      Uri? uri;
      if (urlStr != null && urlStr.trim().isNotEmpty) {
        uri = Uri.tryParse(urlStr.trim());
      }

      // Fallback to lat/lng search if link is missing or invalid
      uri ??= Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=${place.position.latitude},${place.position.longitude}',
      );
      // Coba buka melalui aplikasi eksternal terlebih dahulu.
      // Jika gagal, fallback ke browser (platform default).
      bool launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!launched) {
        // Jika tetap gagal, coba buka dengan mode default (browser/webview).
        launched = await launchUrl(uri, mode: LaunchMode.platformDefault);
      }

      if (!launched) {
        // Fallback terakhir: paksa URL pencarian Google Maps berbasis lat/lng.
        final fallbackUrl = Uri.parse(
          'https://maps.google.com/?q=${place.position.latitude},${place.position.longitude}',
        );
        launched = await launchUrl(
          fallbackUrl,
          mode: LaunchMode.platformDefault,
        );
      }

      if (launched) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Membuka Google Maps'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tidak dapat membuka Google Maps'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error membuka link: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
