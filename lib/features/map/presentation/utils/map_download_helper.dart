import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/services/groundcheck_supabase_service.dart';
import '../../data/repositories/map_repository_impl.dart';
import '../pages/groundcheck_page.dart'; // Import GroundcheckRecord definition
import '../bloc/map_bloc.dart';
import '../bloc/map_event.dart';

class MapDownloadHelper {
  /// Menampilkan dialog konfirmasi untuk download awal (saat data kosong).
  static Future<void> showInitialDownloadDialog(
    BuildContext context, {
    Function(List<GroundcheckRecord>)? onSuccess,
  }) async {
    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Download Data Awal'),
        content: const Text(
          'Database lokal kosong. Perlu mendownload data wilayah (±48.000 data).\n\n'
          'Proses ini membutuhkan koneksi internet.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Nanti'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Download Sekarang'),
          ),
        ],
      ),
    );

    if (confirm == true && context.mounted) {
      await _performDownload(context, onSuccess);
    }
  }

  /// Menampilkan dialog konfirmasi untuk download ulang (reset data).
  static Future<void> showRedownloadDialog(
    BuildContext context, {
    Function(List<GroundcheckRecord>)? onSuccess,
  }) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Download Semua Data?'),
        content: const Text(
          'Ini akan menghapus data lokal dan mendownload ulang 48.000+ data.\n\n'
          'Proses ini membutuhkan waktu lama dan kuota internet yang besar.\n'
          'Aplikasi tidak dapat digunakan selama proses ini.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Download Ulang'),
          ),
        ],
      ),
    );

    if (confirm == true && context.mounted) {
      await _performDownload(context, onSuccess);
    }
  }

  static Future<void> _performDownload(
    BuildContext context,
    Function(List<GroundcheckRecord>)? onSuccess,
  ) async {
    // Show blocking progress dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: Dialog(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                CircularProgressIndicator(),
                SizedBox(height: 20),
                Text(
                  'Sedang mendownload data...',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Text(
                  'Mohon tunggu, jangan tutup aplikasi.\nIni mungkin memakan waktu beberapa menit.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final service = GroundcheckSupabaseService();

      // 1. Download Full Data (Service handles saving to local)
      final records = await service.downloadFullData();

      // 2. Invalidate Repository Cache (so next getPlaces reads new data)
      MapRepositoryImpl().invalidatePlacesCache();

      if (context.mounted) {
        // Close progress dialog
        Navigator.pop(context);

        // 3. Refresh Map UI via Bloc
        context.read<MapBloc>().add(const PlacesRequested());

        // 4. Show Success Message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Download selesai! ${records.length} data berhasil diperbarui.',
            ),
            backgroundColor: Colors.green,
          ),
        );

        // 5. Callback for specific page updates (e.g. GroundcheckPage table)
        onSuccess?.call(records);
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // Close progress dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal mendownload data: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
