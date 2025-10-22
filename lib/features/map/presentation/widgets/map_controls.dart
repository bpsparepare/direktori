import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';
import 'compass_widget.dart';

class MapControls extends StatefulWidget {
  final MapController mapController;
  final VoidCallback? onResetPosition;
  final LatLng? initialCenter;
  final double rotation;
  final Function(LatLng)? onLocationUpdate; // Add location update callback

  const MapControls({
    super.key,
    required this.mapController,
    this.onResetPosition,
    this.initialCenter,
    required this.rotation,
    this.onLocationUpdate, // Add to constructor
  });

  @override
  State<MapControls> createState() => _MapControlsState();
}

class _MapControlsState extends State<MapControls> {
  bool _isLoadingLocation = false;

  Future<void> _getCurrentLocation() async {
    setState(() {
      _isLoadingLocation = true;
    });

    try {
      // Cek apakah location service aktif
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showLocationError('Layanan lokasi tidak aktif. Silakan aktifkan GPS.');
        return;
      }

      // Cek permission
      LocationPermission permission = await Geolocator.checkPermission();
      
      if (permission == LocationPermission.denied) {
        // Request permission
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showLocationError('Izin lokasi ditolak. Silakan berikan izin untuk menggunakan fitur ini.');
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _showLocationError('Izin lokasi ditolak permanen. Silakan aktifkan di pengaturan aplikasi.');
        // Buka pengaturan aplikasi
        await Geolocator.openAppSettings();
        return;
      }

      // Dapatkan posisi saat ini dengan timeout
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      // Pindahkan peta ke lokasi saat ini
      final currentLocation = LatLng(position.latitude, position.longitude);
      widget.mapController.move(
        currentLocation,
        15.0, // Zoom level untuk lokasi saat ini
      );

      // Update location marker via callback
      if (widget.onLocationUpdate != null) {
        widget.onLocationUpdate!(currentLocation);
      }

      // Tampilkan pesan sukses
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Lokasi berhasil ditemukan'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      String errorMessage = 'Gagal mendapatkan lokasi';
      
      if (e.toString().contains('location_service_disabled')) {
        errorMessage = 'Layanan lokasi tidak aktif. Silakan aktifkan GPS.';
      } else if (e.toString().contains('permission_denied')) {
        errorMessage = 'Izin lokasi diperlukan untuk fitur ini.';
      } else if (e.toString().contains('timeout')) {
        errorMessage = 'Timeout mendapatkan lokasi. Coba lagi.';
      } else {
        errorMessage = 'Gagal mendapatkan lokasi: ${e.toString()}';
      }
      
      _showLocationError(errorMessage);
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingLocation = false;
        });
      }
    }
  }

  void _showLocationError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _resetToNorth() {
    // Reset rotation to 0 (north) with animation
    widget.mapController.rotate(0.0);
    widget.onResetPosition?.call();
  }

  void _zoomIn() {
    final currentZoom = widget.mapController.camera.zoom;
    widget.mapController.move(
      widget.mapController.camera.center,
      currentZoom + 1,
    );
  }

  void _zoomOut() {
    final currentZoom = widget.mapController.camera.zoom;
    widget.mapController.move(
      widget.mapController.camera.center,
      currentZoom - 1,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 16,
      top: 100,
      child: Column(
        children: [
          // Compass Widget
          CompassWidget(
            rotation: widget.rotation,
            onTap: _resetToNorth,
          ),
          const SizedBox(height: 8),
          
          // Current Location Button
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: IconButton(
              onPressed: _isLoadingLocation ? null : _getCurrentLocation,
              icon: _isLoadingLocation
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location, color: Colors.green),
              tooltip: 'Lokasi Saya',
            ),
          ),
          const SizedBox(height: 8),
          
          // Zoom In Button
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: IconButton(
              onPressed: _zoomIn,
              icon: const Icon(Icons.zoom_in, color: Colors.grey),
              tooltip: 'Perbesar',
            ),
          ),
          const SizedBox(height: 4),
          
          // Zoom Out Button
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: IconButton(
              onPressed: _zoomOut,
              icon: const Icon(Icons.zoom_out, color: Colors.grey),
              tooltip: 'Perkecil',
            ),
          ),
        ],
      ),
    );
  }
}