import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_dragmarker/flutter_map_dragmarker.dart';
import 'package:latlong2/latlong.dart';
import '../../domain/entities/map_config.dart';
import '../../../../core/utils/map_utils.dart';
import '../../domain/entities/place.dart';
import '../../domain/entities/polygon_data.dart';
import 'map_controls.dart';
import 'map_type.dart';

class MapView extends StatefulWidget {
  final MapConfig config;
  final List<Place> places;
  final Place? selectedPlace; // Add selectedPlace parameter
  final List<LatLng> polygon;
  final List<PolygonData> selectedPolygons; // Add selectedPolygons
  final String? polygonLabel;
  final LatLng? temporaryMarker;
  final List<PolygonData> polygonsMeta;
  final void Function(Place) onPlaceTap;
  final void Function(Place, LatLng)? onPlaceDragEnd;
  final void Function(LatLng)? onLongPress;
  final void Function(int)? onPolygonSelected;
  final void Function(List<PolygonData>)?
  onMultiplePolygonsSelected; // Add callback
  final MapController? mapController; // Add optional MapController parameter
  final void Function(LatLngBounds)? onBoundsChanged;
  final void Function(List<Place>)? onNearbyPlacesTap;
  final bool isPolygonSelected; // Add isPolygonSelected property
  final double baseFontSize; // Base font size for markers

  const MapView({
    super.key,
    required this.config,
    required this.places,
    this.selectedPlace, // Add to constructor
    required this.polygon,
    this.selectedPolygons = const [], // Add to constructor
    this.polygonLabel,
    this.temporaryMarker,
    this.polygonsMeta = const [],
    required this.onPlaceTap,
    this.onPlaceDragEnd,
    this.onLongPress,
    this.onPolygonSelected,
    this.onMultiplePolygonsSelected,
    this.mapController, // Add to constructor
    this.onBoundsChanged,
    this.onNearbyPlacesTap,
    this.isPolygonSelected = false, // Add default value
    this.baseFontSize = 12.0,
  });

  @override
  State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView> with TickerProviderStateMixin {
  late MapController _mapController;
  double _zoom = 13.0;
  double _rotation = 0.0;
  LatLng? _currentLocation; // Add current location state
  MapType _currentMapType = MapType.street; // Add map type state
  late AnimationController _rotationAnimationController;
  late Animation<double> _rotationAnimation;

  double _offsetX = 0.0;
  double _offsetY = 0.0;

  bool _showDirectoryMarkers = true;
  bool _showMarkerLabels = true;
  bool _showGroundcheckMarkers = true;
  bool _showNonVerifiedGroundchecks = true;
  double _baseFontSize = 10.0; // Initial font size
  Timer? _boundsDebounce;
  bool _isDragging = false; // Track dragging state

  @override
  void initState() {
    super.initState();
    _baseFontSize = widget.baseFontSize;
    _zoom = widget.config.zoom;
    // Initialize offset with default values from config
    _offsetX = widget.config.defaultOffsetX;
    _offsetY = widget.config.defaultOffsetY;
    // Use provided MapController or create new one
    _mapController = widget.mapController ?? MapController();
    _rotationAnimationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _rotationAnimation = Tween<double>(begin: 0, end: 0).animate(
      CurvedAnimation(
        parent: _rotationAnimationController,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _boundsDebounce?.cancel();
    _rotationAnimationController.dispose();
    super.dispose();
  }

  void _animateToNorth() {
    _rotationAnimation = Tween<double>(begin: _rotation, end: 0.0).animate(
      CurvedAnimation(
        parent: _rotationAnimationController,
        curve: Curves.easeInOut,
      ),
    );

    _rotationAnimationController.addListener(() {
      final newRotation = _rotationAnimation.value;
      _mapController.rotate(newRotation);
      setState(() {
        _rotation = newRotation;
      });
    });

    _rotationAnimationController.forward(from: 0).then((_) {
      _rotationAnimationController.removeListener(() {});
    });
  }

  LatLng? _centroid(List<LatLng> pts) {
    if (pts.isEmpty) return null;
    if (pts.length == 1) return pts.first;

    // Implementasi geometric centroid untuk polygon
    // Menggunakan algoritma yang memperhitungkan area polygon
    double area = 0.0;
    double centroidX = 0.0;
    double centroidY = 0.0;

    // Pastikan polygon tertutup
    List<LatLng> points = List.from(pts);
    if (points.first.latitude != points.last.latitude ||
        points.first.longitude != points.last.longitude) {
      points.add(points.first);
    }

    // Hitung area dan centroid menggunakan shoelace formula
    for (int i = 0; i < points.length - 1; i++) {
      double x0 = points[i].longitude;
      double y0 = points[i].latitude;
      double x1 = points[i + 1].longitude;
      double y1 = points[i + 1].latitude;

      double a = x0 * y1 - x1 * y0;
      area += a;
      centroidX += (x0 + x1) * a;
      centroidY += (y0 + y1) * a;
    }

    area *= 0.5;

    // Jika area terlalu kecil, fallback ke arithmetic mean
    if (area.abs() < 1e-10) {
      double sumLat = 0, sumLon = 0;
      for (final p in pts) {
        sumLat += p.latitude;
        sumLon += p.longitude;
      }
      return LatLng(sumLat / pts.length, sumLon / pts.length);
    }

    centroidX /= (6.0 * area);
    centroidY /= (6.0 * area);

    return LatLng(centroidY, centroidX);
  }

  LatLng? _multiPolygonCenter(List<PolygonData> polygons) {
    if (polygons.isEmpty) return null;
    double minLat = 90.0;
    double maxLat = -90.0;
    double minLng = 180.0;
    double maxLng = -180.0;

    bool hasPoints = false;
    for (final p in polygons) {
      for (final point in p.points) {
        hasPoints = true;
        if (point.latitude < minLat) minLat = point.latitude;
        if (point.latitude > maxLat) maxLat = point.latitude;
        if (point.longitude < minLng) minLng = point.longitude;
        if (point.longitude > maxLng) maxLng = point.longitude;
      }
    }

    if (!hasPoints) return null;
    return LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
  }

  void _fitPolygonToBounds(List<LatLng> points) {
    if (points.isEmpty) return;

    // Hitung bounding box dari polygon
    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (final point in points) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }

    // Buat LatLngBounds dan fit ke bounds dengan padding
    final bounds = LatLngBounds(LatLng(minLat, minLng), LatLng(maxLat, maxLng));

    // Fit to bounds dengan padding untuk memberikan ruang di sekitar polygon
    _mapController.fitCamera(
      CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(50.0)),
    );
  }

  void _fitMultiPolygonToBounds(List<PolygonData> polygons) {
    if (polygons.isEmpty) return;

    double minLat = 90.0;
    double maxLat = -90.0;
    double minLng = 180.0;
    double maxLng = -180.0;
    bool hasPoints = false;

    for (final p in polygons) {
      for (final point in p.points) {
        hasPoints = true;
        if (point.latitude < minLat) minLat = point.latitude;
        if (point.latitude > maxLat) maxLat = point.latitude;
        if (point.longitude < minLng) minLng = point.longitude;
        if (point.longitude > maxLng) maxLng = point.longitude;
      }
    }

    if (!hasPoints) return;

    final bounds = LatLngBounds(LatLng(minLat, minLng), LatLng(maxLat, maxLng));
    _mapController.fitCamera(
      CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(50.0)),
    );
  }

  @override
  void didUpdateWidget(MapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.polygon != widget.polygon &&
        widget.polygon.isNotEmpty &&
        widget.selectedPolygons.isEmpty) {
      // Zoom to fit the new polygon instead of just moving to centroid
      _fitPolygonToBounds(widget.polygon);
    } else if (widget.selectedPolygons.isNotEmpty &&
        oldWidget.selectedPolygons != widget.selectedPolygons) {
      _fitMultiPolygonToBounds(widget.selectedPolygons);
    }
  }

  double _scaledFontSize() {
    final double z = _zoom;
    if (z <= 11) return 12;
    if (z <= 12) return 14;
    if (z <= 13) return 16;
    if (z <= 14) return 18;
    if (z <= 15) return 20;
    if (z <= 16) return 22;
    if (z <= 17) return 24;
    return 26;
  }

  double _scaledWidth(String text, double fontSize) {
    final double w = fontSize * (text.length * 0.6);
    return w.clamp(60, 400);
  }

  double _scaledHeight(double fontSize) {
    final double h = fontSize * 1.6;
    return h.clamp(24, 64);
  }

  // Calculate dynamic offset based on zoom level for Esri maps
  double _getDynamicOffsetX(double baseOffsetX, double zoomLevel) {
    // Base zoom level where the offset was calibrated (assuming zoom 13)
    const double baseZoomLevel = 13.0;

    // Scale factor: offset decreases as zoom increases
    // This is because at higher zoom levels, the same pixel offset represents a smaller geographic distance
    double scaleFactor = baseZoomLevel / zoomLevel;

    return baseOffsetX * scaleFactor;
  }

  double _getDynamicOffsetY(double baseOffsetY, double zoomLevel) {
    // Base zoom level where the offset was calibrated (assuming zoom 13)
    const double baseZoomLevel = 13.0;

    // Scale factor: offset decreases as zoom increases
    double scaleFactor = baseZoomLevel / zoomLevel;

    return baseOffsetY * scaleFactor;
  }

  @override
  Widget build(BuildContext context) {
    LatLng? centroid;
    if (widget.selectedPolygons.isNotEmpty) {
      centroid = _multiPolygonCenter(widget.selectedPolygons);
    } else {
      centroid = _centroid(widget.polygon);
    }

    final double fontSize = _scaledFontSize();
    final double labelWidth = widget.polygonLabel != null
        ? _scaledWidth(widget.polygonLabel!, fontSize)
        : 120;
    final double labelHeight = _scaledHeight(fontSize);
    final List<Place> renderList = _placesForRender(widget.places);
    final List<Place> groundcheckList = renderList
        .where(
          (p) =>
              p.id.startsWith('gc:') &&
              (_showNonVerifiedGroundchecks ||
                  p.gcsResult == '1' ||
                  (p.gcsResult?.isEmpty ?? true)),
        )
        .toList();
    final List<Place> mainList = renderList
        .where((p) => !p.id.startsWith('gc:'))
        .toList();

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: widget.config.center,
            initialZoom: widget.config.zoom,
            minZoom: _currentMapType.minZoom,
            maxZoom: (_currentMapType.maxZoom + 2).toDouble(),
            initialRotation: _rotation,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all,
            ),
            onLongPress: (tapPosition, point) {
              if (widget.onLongPress != null) {
                widget.onLongPress!(point);
              }
            },
            onMapEvent: (evt) {
              bool shouldSetState = false;
              // Only update state if zoom or rotation changed significantly
              if ((evt.camera.zoom - _zoom).abs() > 0.001) {
                _zoom = evt.camera.zoom;
                shouldSetState = true;
                debugPrint(
                  'MapView: Zoom changed to ${_zoom.toStringAsFixed(2)}',
                );
              }
              if ((evt.camera.rotation - _rotation).abs() > 0.001) {
                _rotation = evt.camera.rotation;
                shouldSetState = true;
              }

              if (shouldSetState) {
                setState(() {});
              }

              if (widget.onBoundsChanged != null && !_isDragging) {
                _boundsDebounce?.cancel();
                _boundsDebounce = Timer(const Duration(milliseconds: 300), () {
                  if (_isDragging) return; // Double check inside timer
                  final b = _mapController.camera.visibleBounds;
                  widget.onBoundsChanged!(b);
                });
              }
            },
          ),
          children: [
            TileLayer(
              urlTemplate: _currentMapType.urlTemplate,
              userAgentPackageName: 'id.bpsparepare.direktori',
              // Allow app to zoom beyond provider's native max zoom by stretching tiles
              maxZoom: (_currentMapType.maxZoom + 2).toDouble(),
              maxNativeZoom: _currentMapType.maxZoom,
              minZoom: _currentMapType.minZoom,
              subdomains: _currentMapType.subdomains,
              additionalOptions: const {'crossOrigin': 'anonymous'},
              tileBuilder: (context, tileWidget, tile) {
                // Apply dynamic offset only for Esri satellite maps
                if (_currentMapType == MapType.satellite &&
                    (_offsetX != 0.0 || _offsetY != 0.0)) {
                  // Calculate dynamic offset based on current zoom level
                  double dynamicOffsetX = _getDynamicOffsetX(_offsetX, _zoom);
                  double dynamicOffsetY = _getDynamicOffsetY(_offsetY, _zoom);

                  return Transform.translate(
                    offset: Offset(dynamicOffsetX, dynamicOffsetY),
                    child: tileWidget,
                  );
                }
                return tileWidget;
              },
            ),
            if (widget.selectedPolygons.isNotEmpty)
              PolygonLayer(
                polygons: widget.selectedPolygons.map((p) {
                  return Polygon(
                    points: p.points,
                    color: Colors.blue.withValues(alpha: 0.3),
                    borderColor: Colors.blue,
                    borderStrokeWidth: 2,
                    label: p.name, // Use name (nmsls) instead of idsls
                    labelStyle: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  );
                }).toList(),
              )
            else if (widget.polygon.isNotEmpty)
              PolygonLayer(
                polygons: [
                  Polygon(
                    points: widget.polygon,
                    color: Colors.blue.withValues(alpha: 0.3),
                    borderColor: Colors.blue,
                    borderStrokeWidth: 2,
                  ),
                ],
              ),
            if (widget.polygon.isNotEmpty &&
                widget.polygonLabel != null &&
                centroid != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: centroid,
                    width: labelWidth,
                    height: labelHeight,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Outline putih agar teks tetap terbaca di atas peta
                        Text(
                          widget.polygonLabel!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: fontSize,
                            fontWeight: FontWeight.w600,
                            foreground: Paint()
                              ..style = PaintingStyle.stroke
                              ..strokeWidth = 3
                              ..color = Colors.white,
                          ),
                          overflow: TextOverflow.visible,
                        ),
                        // Isi teks berwarna
                        Text(
                          widget.polygonLabel!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: fontSize,
                            fontWeight: FontWeight.w600,
                            color: Colors.blueAccent,
                          ),
                          overflow: TextOverflow.visible,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            // Draggable markers: split into groundcheck and main (above)
            if (renderList.isNotEmpty) ...[
              if (_showGroundcheckMarkers && groundcheckList.isNotEmpty)
                DragMarkers(
                  markers: groundcheckList.map((p) {
                    final isSelected = widget.selectedPlace?.id == p.id;
                    final double fontSize = _baseFontSize;
                    return DragMarker(
                      key: ValueKey(p.id),
                      point: p.position,
                      size: Size(170, isSelected ? 86 : 78),
                      offset: Offset(0, isSelected ? -20 : -16),
                      useLongPress: true,
                      builder: (_, __, isDragging) {
                        Color baseColor;
                        IconData icon;

                        if (isDragging) {
                          baseColor = Colors.blue;
                          icon = Icons.edit_location_alt;
                        } else {
                          switch (p.gcsResult) {
                            case '1': // Ditemukan
                              baseColor = Colors.green;
                              icon = Icons.check_circle;
                              break;
                            case '99': // Tidak ditemukan
                              baseColor = Colors.red;
                              icon = Icons.cancel;
                              break;
                            case '3': // Tutup
                              baseColor = Colors.pinkAccent;
                              icon = Icons.block;
                              break;
                            case '4': // Ganda
                              baseColor = Colors.deepPurpleAccent;
                              icon = Icons.content_copy;
                              break;
                            case '5': // Usaha Baru
                              baseColor = Colors.blue;
                              icon = Icons.add_location;
                              break;
                            default: // Belum Groundcheck (null/empty)
                              baseColor = Colors.orange;
                              icon = Icons.help;
                              break;
                          }
                        }

                        // Highlight color when selected if needed, or just keep status color
                        if (isSelected) {
                          // Optional: make it slightly different or just rely on size
                        }

                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              decoration: isSelected
                                  ? BoxDecoration(
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: baseColor.withValues(
                                            alpha: 0.5,
                                          ),
                                          blurRadius: 10,
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    )
                                  : null,
                              child: Icon(
                                icon,
                                color: baseColor,
                                size: isSelected ? 40 : 32,
                              ),
                            ),
                            const SizedBox(height: 2),
                            if (_showMarkerLabels)
                              Stack(
                                alignment: Alignment.center,
                                children: [
                                  Text(
                                    p.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: fontSize.toDouble(),
                                      fontWeight: FontWeight.w600,
                                      foreground: Paint()
                                        ..style = PaintingStyle.stroke
                                        ..strokeWidth = 3
                                        ..color = Colors.black,
                                    ),
                                  ),
                                  Text(
                                    p.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: fontSize.toDouble(),
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        );
                      },
                      onTap: (_) {
                        final d = const Distance();
                        final nearby = groundcheckList
                            .where(
                              (other) =>
                                  d.as(
                                    LengthUnit.Meter,
                                    p.position,
                                    other.position,
                                  ) <=
                                  4.0,
                            )
                            .toList();
                        if (widget.onNearbyPlacesTap != null) {
                          final list = nearby.isNotEmpty ? nearby : [p];
                          widget.onNearbyPlacesTap!(list);
                        } else {
                          widget.onPlaceTap(p);
                        }
                      },
                      onDragStart: (_, __) {
                        _isDragging = true;
                      },
                      onDragEnd: (_, newPoint) {
                        _isDragging = false;
                        widget.onPlaceDragEnd?.call(p, newPoint);
                      },
                      onLongDragEnd: (_, newPoint) {
                        _isDragging = false;
                        widget.onPlaceDragEnd?.call(p, newPoint);
                      },
                      scrollMapNearEdge: true,
                      scrollNearEdgeRatio: 2.0,
                      scrollNearEdgeSpeed: 2.0,
                    );
                  }).toList(),
                ),
              if (_showDirectoryMarkers && mainList.isNotEmpty)
                DragMarkers(
                  markers: mainList.map((p) {
                    final isSelected = widget.selectedPlace?.id == p.id;
                    final double fontSize = _baseFontSize;
                    return DragMarker(
                      key: ValueKey(p.id),
                      point: p.position,
                      size: Size(170, isSelected ? 86 : 78),
                      offset: Offset(0, isSelected ? -20 : -16),
                      useLongPress: true,
                      builder: (_, __, isDragging) {
                        final Color baseColor = isSelected
                            ? Colors.blue
                            : Colors.red;
                        final IconData icon = isDragging
                            ? Icons.edit_location
                            : Icons.location_on;
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              decoration: isSelected
                                  ? BoxDecoration(
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: baseColor.withValues(
                                            alpha: 0.5,
                                          ),
                                          blurRadius: 10,
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    )
                                  : null,
                              child: Icon(
                                icon,
                                color: baseColor,
                                size: isSelected ? 40 : 32,
                              ),
                            ),
                            const SizedBox(height: 2),
                            if (_showMarkerLabels)
                              Stack(
                                alignment: Alignment.center,
                                children: [
                                  Text(
                                    p.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: fontSize.toDouble(),
                                      fontWeight: FontWeight.w600,
                                      foreground: Paint()
                                        ..style = PaintingStyle.stroke
                                        ..strokeWidth = 3
                                        ..color = Colors.black,
                                    ),
                                  ),
                                  Text(
                                    p.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: fontSize.toDouble(),
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        );
                      },
                      onTap: (_) => widget.onPlaceTap(p),
                      onDragStart: (_, __) {
                        _isDragging = true;
                      },
                      onDragEnd: (_, newPoint) {
                        _isDragging = false;
                        widget.onPlaceDragEnd?.call(p, newPoint);
                      },
                      onLongDragEnd: (_, newPoint) {
                        _isDragging = false;
                        widget.onPlaceDragEnd?.call(p, newPoint);
                      },
                      scrollMapNearEdge: true,
                      scrollNearEdgeRatio: 2.0,
                      scrollNearEdgeSpeed: 2.0,
                    );
                  }).toList(),
                ),
            ],
            // Keep non-draggable markers (current location and temporary)
            MarkerLayer(
              markers: [
                // Current location marker
                if (_currentLocation != null)
                  Marker(
                    point: _currentLocation!,
                    width: _getMarkerSize(),
                    height: _getMarkerSize(),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.3),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.blue, width: 2),
                      ),
                      child: Icon(
                        Icons.my_location,
                        color: Colors.blue,
                        size: _getIconSize(),
                      ),
                    ),
                  ),
                // Temporary marker for long press
                if (widget.temporaryMarker != null)
                  Marker(
                    point: widget.temporaryMarker!,
                    width: 40,
                    height: 40,
                    child: const Icon(
                      Icons.place,
                      color: Colors.orange,
                      size: 32,
                    ),
                  ),
              ],
            ),
          ],
        ),
        // Map Controls
        MapControls(
          mapController: _mapController,
          initialCenter: widget.config.center,
          rotation: _rotation,
          polygonsMeta: widget.polygonsMeta,
          currentMapType: _currentMapType,
          showDirectoryMarkers: _showDirectoryMarkers,
          showGroundcheckMarkers: _showGroundcheckMarkers,
          showMarkerLabels: _showMarkerLabels,
          showNonVerifiedGroundchecks: _showNonVerifiedGroundchecks,
          onResetPosition: () {
            // Animate rotation to north smoothly
            _animateToNorth();
          },
          onLocationUpdate: (LatLng location) {
            // Update current location marker
            setState(() {
              _currentLocation = location;
            });
          },
          onPolygonSelected: widget.onPolygonSelected,
          onMultiplePolygonsSelected: widget.onMultiplePolygonsSelected,
          onMapTypeChanged: (MapType mapType) {
            setState(() {
              _currentMapType = mapType;
            });
          },
          onToggleDirectoryMarkers: (bool value) {
            setState(() {
              _showDirectoryMarkers = value;
            });
          },
          onToggleGroundcheckMarkers: (bool value) {
            setState(() {
              _showGroundcheckMarkers = value;
            });
          },
          onToggleMarkerLabels: (bool value) {
            setState(() {
              _showMarkerLabels = value;
            });
          },
          onToggleNonVerifiedGroundchecks: (bool value) {
            setState(() {
              _showNonVerifiedGroundchecks = value;
            });
          },
          onOffsetChanged: (double offsetX, double offsetY) {
            setState(() {
              _offsetX = offsetX;
              _offsetY = offsetY;
            });
          },
          currentOffsetX: _offsetX,
          currentOffsetY: _offsetY,
          isPolygonSelected: widget.isPolygonSelected, // Pass property
          onToggleFontSize: () {
            setState(() {
              // Cycle: 9 -> 10 -> 11 -> 12 -> 9
              if (_baseFontSize == 9.0) {
                _baseFontSize = 10.0;
              } else if (_baseFontSize == 10.0) {
                _baseFontSize = 11.0;
              } else if (_baseFontSize == 11.0) {
                _baseFontSize = 12.0;
              } else {
                _baseFontSize = 9.0;
              }
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Ukuran font marker: $_baseFontSize'),
                duration: const Duration(seconds: 1),
              ),
            );
          },
        ),
        // Debug Info Panel (only show for Esri satellite with offset)
        if (_currentMapType == MapType.satellite &&
            (_offsetX != 0.0 || _offsetY != 0.0))
          Positioned(
            left: 16,
            bottom: 100,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Debug Offset:',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Base X: ${_offsetX.toStringAsFixed(1)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                  Text(
                    'Base Y: ${_offsetY.toStringAsFixed(1)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                  Text(
                    'Dynamic X: ${_getDynamicOffsetX(_offsetX, _zoom).toStringAsFixed(1)}',
                    style: const TextStyle(
                      color: Colors.yellow,
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                  Text(
                    'Dynamic Y: ${_getDynamicOffsetY(_offsetY, _zoom).toStringAsFixed(1)}',
                    style: const TextStyle(
                      color: Colors.yellow,
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                  Text(
                    'Zoom: ${_zoom.toStringAsFixed(1)}',
                    style: const TextStyle(
                      color: Colors.lightBlue,
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  List<Place> _placesForRender(List<Place> input) {
    // 1. Filter by Polygon (Single or Multiple)
    List<Place> filteredByPolygon = input;

    if (widget.selectedPolygons.isNotEmpty) {
      // Filter for Multiple Polygons (Kelurahan)
      filteredByPolygon = input.where((p) {
        return widget.selectedPolygons.any((poly) {
          return MapUtils.isPointInPolygon(p.position, poly.points);
        });
      }).toList();
    } else if (widget.polygon.isNotEmpty) {
      // Filter for Single Polygon (SLS)
      filteredByPolygon = input.where((p) {
        return MapUtils.isPointInPolygon(p.position, widget.polygon);
      }).toList();
    }

    // Special Case: Single Polygon (SLS) - Show 100% (No Capping)
    if (widget.polygon.isNotEmpty && widget.selectedPolygons.isEmpty) {
      // Still respect selectedPlace if it exists
      final selectedId = widget.selectedPlace?.id;
      if (selectedId != null &&
          filteredByPolygon.every((p) => p.id != selectedId)) {
        // If selected place is filtered out, we don't add it back for polygon filter
        // because we strictly want to show what's inside.
      }
      debugPrint(
        'Map Render (Polygon): Zoom=${_zoom.toStringAsFixed(2)} | Rendered=${filteredByPolygon.length}/${input.length} (No Cap)',
      );
      return filteredByPolygon;
    }

    // 2. Capping Logic (For No Selection OR Multiple Polygons/Kelurahan)
    // Use filteredByPolygon as the source so we respect the polygon boundary
    final sourceList = filteredByPolygon;
    final selectedId = widget.selectedPlace?.id;
    final int? cap = _capForZoom(sourceList.length, _zoom);
    if (cap == null || sourceList.length <= cap) {
      debugPrint(
        'Map Render: Zoom=${_zoom.toStringAsFixed(2)} | Rendered=${sourceList.length}/${input.length} (Cap=$cap - Within Limit)',
      );
      return sourceList;
    }

    final List<Place> main = [];
    final List<Place> gc = [];
    for (final p in sourceList) {
      if (p.id.startsWith('gc:')) {
        gc.add(p);
      } else {
        main.add(p);
      }
    }
    final List<Place> result = [];
    int iMain = 0, iGc = 0;
    while (result.length < cap && (iMain < main.length || iGc < gc.length)) {
      if (iMain < main.length && result.length < cap) {
        result.add(main[iMain++]);
      }
      if (iGc < gc.length && result.length < cap) {
        result.add(gc[iGc++]);
      }
    }
    if (selectedId != null && result.every((p) => p.id != selectedId)) {
      // Only try to find in sourceList (must be inside polygon if filtering is active)
      try {
        final sel = sourceList.firstWhere((p) => p.id == selectedId);
        result.insert(0, sel);
        if (result.length > cap) {
          result.removeLast();
        }
      } catch (_) {
        // Selected place is not in the filtered list (outside polygon), so ignore
      }
    }
    debugPrint(
      'Map Render: Zoom=${_zoom.toStringAsFixed(2)} | Rendered=${result.length}/${input.length} (Cap=$cap)',
    );
    return result;
  }

  int? _capForZoom(int total, double z) {
    // Zoom levels:
    // < 14: Level Kecamatan/Kota (Area luas)
    // 14-16: Level Kelurahan/Lingkungan (Area menengah)
    // 16-18: Level Blok/Jalan (Detail)
    // >= 18: Level Bangunan (Sangat detail)

    // Logika Progresif:
    // Semakin zoom out (angka kecil), semakin sedikit marker (untuk hindari clutter/lag).
    // Semakin zoom in (angka besar), semakin banyak marker boleh tampil.

    if (z < 14) return 5; // Jauh: Sedikit marker
    if (z < 15) return 10; // Menengah: Mulai terlihat
    if (z < 16) return 15; // Menengah-Detail
    if (z < 17) return 20; // Detail
    if (z < 18) return 25; // Sangat Detail (Keep low)
    if (z < 19) return 30; // Hampir Maksimal (Reduced from 70)
    if (z < 20) return 40; // Extra detail before unlimited
    // Zoom >= 20: Tampilkan semua (Unlimited)
    return null;
  }

  // Helper methods for responsive marker sizing
  double _getMarkerSize() {
    // Base size is 30, scales with zoom level
    // Minimum size: 20, Maximum size: 60
    double baseSize = 30.0;
    double scaleFactor = (_zoom / 13.0); // 13 is the default zoom
    double size = baseSize * scaleFactor;
    return size.clamp(20.0, 60.0);
  }

  double _getIconSize() {
    // Icon size is proportional to marker size
    double markerSize = _getMarkerSize();
    return (markerSize * 0.6).clamp(12.0, 36.0);
  }
}
