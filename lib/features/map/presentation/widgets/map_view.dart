import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../domain/entities/map_config.dart';
import '../../domain/entities/place.dart';

class MapView extends StatefulWidget {
  final MapConfig config;
  final List<Place> places;
  final List<LatLng> polygon;
  final String? polygonLabel;
  final void Function(Place) onPlaceTap;

  const MapView({
    super.key,
    required this.config,
    required this.places,
    required this.polygon,
    this.polygonLabel,
    required this.onPlaceTap,
  });

  @override
  State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView> {
  double _zoom = 13;
  late final MapController _mapController;

  @override
  void initState() {
    super.initState();
    _zoom = widget.config.zoom;
    _mapController = MapController();
  }

  @override
  void didUpdateWidget(covariant MapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Pindahkan kamera ke centroid polygon saat pengguna memilih polygon baru
    if (widget.polygon.isNotEmpty) {
      final LatLng? newCentroid = _centroid(widget.polygon);
      final LatLng? oldCentroid = _centroid(oldWidget.polygon);
      // Jika centroid berubah signifikan, lakukan move
      if (newCentroid != null && (oldCentroid == null || newCentroid.latitude != oldCentroid.latitude || newCentroid.longitude != oldCentroid.longitude)) {
        try {
          _mapController.move(newCentroid, _zoom);
        } catch (_) {}
      }
    }
  }

  LatLng? _centroid(List<LatLng> pts) {
    if (pts.isEmpty) return null;
    double sumLat = 0, sumLon = 0;
    for (final p in pts) {
      sumLat += p.latitude;
      sumLon += p.longitude;
    }
    return LatLng(sumLat / pts.length, sumLon / pts.length);
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
    final double labelWidth = widget.polygonLabel != null ? _scaledWidth(widget.polygonLabel!, fontSize) : 120;
    final double labelHeight = _scaledHeight(fontSize);

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: widget.config.center,
        initialZoom: widget.config.zoom,
        onMapEvent: (evt) {
          setState(() {
            _zoom = evt.camera.zoom;
          });
        },
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.direktori',
          maxZoom: 19,
          subdomains: const ['a', 'b', 'c'],
          additionalOptions: const {
            'crossOrigin': 'anonymous',
          },
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
        if (widget.polygon.isNotEmpty && widget.polygonLabel != null && centroid != null)
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
          markers: widget.places
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
        ),
      ],
    );
  }
}