import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../domain/entities/map_config.dart';
import '../../domain/entities/place.dart';
import '../../domain/entities/polygon_data.dart';
import 'map_controls.dart';

class MapView extends StatefulWidget {
  final MapConfig config;
  final List<Place> places;
  final List<LatLng> polygon;
  final String? polygonLabel;
  final LatLng? temporaryMarker;
  final List<PolygonData> polygonsMeta;
  final void Function(Place) onPlaceTap;
  final void Function(LatLng)? onLongPress;
  final void Function(int)? onPolygonSelected;
  final MapController? mapController; // Add optional MapController parameter

  const MapView({
    super.key,
    required this.config,
    required this.places,
    required this.polygon,
    this.polygonLabel,
    this.temporaryMarker,
    this.polygonsMeta = const [],
    required this.onPlaceTap,
    this.onLongPress,
    this.onPolygonSelected,
    this.mapController, // Add to constructor
  });

  @override
  State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView> with TickerProviderStateMixin {
  late MapController _mapController;
  double _zoom = 13.0;
  double _rotation = 0.0;
  LatLng? _currentLocation; // Add current location state
  late AnimationController _rotationAnimationController;
  late Animation<double> _rotationAnimation;

  @override
  void initState() {
    super.initState();
    _zoom = widget.config.zoom;
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

  @override
  Widget build(BuildContext context) {
    final centroid = _centroid(widget.polygon);
    final double fontSize = _scaledFontSize();
    final double labelWidth = widget.polygonLabel != null
        ? _scaledWidth(widget.polygonLabel!, fontSize)
        : 120;
    final double labelHeight = _scaledHeight(fontSize);

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
            },
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.direktori',
              maxZoom: 19,
              subdomains: const ['a', 'b', 'c'],
              additionalOptions: const {'crossOrigin': 'anonymous'},
              tileBuilder: (context, tileWidget, tile) {
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
            MarkerLayer(
              markers: [
                // Existing place markers
                ...widget.places
                    .map(
                      (p) => Marker(
                        point: p.position,
                        width: 40,
                        height: 40,
                        child: GestureDetector(
                          onTap: () => widget.onPlaceTap(p),
                          child: const Icon(
                            Icons.location_on,
                            color: Colors.red,
                            size: 32,
                          ),
                        ),
                      ),
                    )
                    .toList(),
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
        ),
      ],
    );
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