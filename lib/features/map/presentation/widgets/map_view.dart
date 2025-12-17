import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_dragmarker/flutter_map_dragmarker.dart';
import 'package:latlong2/latlong.dart';
import '../../domain/entities/map_config.dart';
import '../../domain/entities/place.dart';
import '../../domain/entities/polygon_data.dart';
import 'map_controls.dart';
import 'map_type.dart';

class MapView extends StatefulWidget {
  final MapConfig config;
  final List<Place> places;
  final Place? selectedPlace; // Add selectedPlace parameter
  final List<LatLng> polygon;
  final String? polygonLabel;
  final LatLng? temporaryMarker;
  final List<PolygonData> polygonsMeta;
  final void Function(Place) onPlaceTap;
  final void Function(Place, LatLng)? onPlaceDragEnd;
  final void Function(LatLng)? onLongPress;
  final void Function(int)? onPolygonSelected;
  final MapController? mapController; // Add optional MapController parameter
  final void Function(LatLngBounds)? onBoundsChanged;

  const MapView({
    super.key,
    required this.config,
    required this.places,
    this.selectedPlace, // Add to constructor
    required this.polygon,
    this.polygonLabel,
    this.temporaryMarker,
    this.polygonsMeta = const [],
    required this.onPlaceTap,
    this.onPlaceDragEnd,
    this.onLongPress,
    this.onPolygonSelected,
    this.mapController, // Add to constructor
    this.onBoundsChanged,
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

  // Offset variables for manual map adjustment
  double _offsetX = 0.0;
  double _offsetY = 0.0;

  // Toggle scraped markers visibility
  bool _showScrapedMarkers = true;
  bool _showMarkerLabels = true;
  Timer? _boundsDebounce;

  @override
  void initState() {
    super.initState();
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

  @override
  void didUpdateWidget(MapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.polygon != widget.polygon && widget.polygon.isNotEmpty) {
      // Zoom to fit the new polygon instead of just moving to centroid
      _fitPolygonToBounds(widget.polygon);
    }
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
    final centroid = _centroid(widget.polygon);
    final double fontSize = _scaledFontSize();
    final double labelWidth = widget.polygonLabel != null
        ? _scaledWidth(widget.polygonLabel!, fontSize)
        : 120;
    final double labelHeight = _scaledHeight(fontSize);
    final List<Place> renderList = _placesForRender(widget.places);
    final List<Place> scrapedList = renderList
        .where((p) => p.id.startsWith('scrape:'))
        .toList();
    final List<Place> mainList = renderList
        .where((p) => !p.id.startsWith('scrape:'))
        .toList();

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: widget.config.center,
            initialZoom: widget.config.zoom,
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
              setState(() {
                _zoom = evt.camera.zoom;
                _rotation = evt.camera.rotation;
              });
              if (widget.onBoundsChanged != null) {
                _boundsDebounce?.cancel();
                _boundsDebounce = Timer(const Duration(milliseconds: 300), () {
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
            if (widget.polygon.isNotEmpty)
              PolygonLayer(
                polygons: [
                  Polygon(
                    points: widget.polygon,
                    color: Colors.blue.withOpacity(0.3),
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
            // Draggable markers: split into scraped (below) and main (above)
            if (renderList.isNotEmpty) ...[
              // Scraped markers layer (rendered first = below)
              if (_showScrapedMarkers)
                MarkerLayer(
                  markers: scrapedList.map((p) {
                    final isSelected = widget.selectedPlace?.id == p.id;
                    final Color baseColor = isSelected
                        ? Colors.blue
                        : Colors.purple;
                    final double fontSize = (_scaledFontSize() - 8).clamp(
                      10,
                      14,
                    );
                    return Marker(
                      point: p.position,
                      width: 160,
                      height: isSelected ? 84 : 76,
                      child: GestureDetector(
                        onTap: () => widget.onPlaceTap(p),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              decoration: isSelected
                                  ? BoxDecoration(
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: baseColor.withOpacity(0.5),
                                          blurRadius: 10,
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    )
                                  : null,
                              child: Icon(
                                Icons.location_pin,
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
                        ),
                      ),
                    );
                  }).toList(),
                ),
              // Main markers layer (rendered after = above)
              DragMarkers(
                markers: mainList.map((p) {
                  final isSelected = widget.selectedPlace?.id == p.id;
                  final double fontSize = (_scaledFontSize() - 8).clamp(10, 14);
                  return DragMarker(
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
                                        color: baseColor.withOpacity(0.5),
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
                    onDragEnd: (_, newPoint) =>
                        widget.onPlaceDragEnd?.call(p, newPoint),
                    onLongDragEnd: (_, newPoint) =>
                        widget.onPlaceDragEnd?.call(p, newPoint),
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
                        color: Colors.blue.withOpacity(0.3),
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
          showScrapedMarkers: _showScrapedMarkers,
          showMarkerLabels: _showMarkerLabels,
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
          onMapTypeChanged: (MapType mapType) {
            setState(() {
              _currentMapType = mapType;
            });
          },
          onToggleScrapedMarkers: (bool value) {
            setState(() {
              _showScrapedMarkers = value;
            });
          },
          onToggleMarkerLabels: (bool value) {
            setState(() {
              _showMarkerLabels = value;
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
                color: Colors.black.withOpacity(0.8),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
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
    final selectedId = widget.selectedPlace?.id;
    final int? cap = _capForZoom(input.length, _zoom);
    if (cap == null || input.length <= cap) return input;
    final List<Place> result = input.take(cap).toList();
    if (selectedId != null && result.every((p) => p.id != selectedId)) {
      final sel = input.firstWhere(
        (p) => p.id == selectedId,
        orElse: () => result.first,
      );
      result.add(sel);
    }
    return result;
  }

  int? _capForZoom(int total, double z) {
    // if (z < 11) return 5;
    // if (z < 12) return 10;
    // if (z < 13) return 20;
    // if (z < 14) return 5;
    if (z < 14) return 5;
    if (z < 16) return 10;
    if (z < 17) return 20;
    if (z < 18) return 30;
    if (z < 19) return 40;
    if (z < 20) return 50;
    return null; // >=19 show all
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
