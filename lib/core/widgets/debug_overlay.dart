import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../utils/debug_monitor.dart';

class DebugOverlay extends StatefulWidget {
  final Widget child;

  const DebugOverlay({super.key, required this.child});

  @override
  State<DebugOverlay> createState() => _DebugOverlayState();
}

class _DebugOverlayState extends State<DebugOverlay> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Stack(children: [widget.child, if (kDebugMode) _buildOverlay()]);
  }

  Widget _buildOverlay() {
    return Positioned(
      top: 50,
      right: 16,
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            InkWell(
              onTap: () {
                setState(() {
                  _isExpanded = !_isExpanded;
                });
              },
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.network_check,
                      color: Colors.white,
                      size: 20,
                    ),
                    if (_isExpanded) ...[
                      const SizedBox(width: 8),
                      const Text(
                        'Network Monitor',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (_isExpanded) ...[
              const SizedBox(height: 8),
              Container(
                width: 250,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ValueListenableBuilder<DebugStats>(
                  valueListenable: DebugMonitor().statsNotifier,
                  builder: (context, stats, _) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildRow(
                          'Total Upload',
                          _formatSize(stats.totalUploadKb),
                        ),
                        _buildRow(
                          'Total Download',
                          _formatSize(stats.totalDownloadKb),
                        ),
                        const Divider(color: Colors.white24, height: 16),
                        const Text(
                          'Last Request:',
                          style: TextStyle(color: Colors.white70, fontSize: 10),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          stats.lastRequest,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Size: ${_formatSize(stats.lastRequestSizeKb)}',
                          style: const TextStyle(
                            color: Colors.greenAccent,
                            fontSize: 10,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Total Requests: ${stats.requestCount}',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 10,
                          ),
                        ),
                        const Divider(color: Colors.white24, height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.redAccent.withOpacity(
                                0.8,
                              ),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                            ),
                            onPressed: _resetAppData,
                            child: const Text('Reset App Data & Cache'),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _resetAppData() async {
    try {
      // 1. Clear SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      // 2. Clear Application Documents Directory (JSON files & Cache)
      final appDir = await getApplicationDocumentsDirectory();

      // List all files
      if (appDir.existsSync()) {
        final files = appDir.listSync();
        for (var entity in files) {
          if (entity is File && entity.path.endsWith('.json')) {
            await entity.delete();
            debugPrint('Deleted: ${entity.path}');
          }
        }
      }

      // 3. Clear Temporary Directory
      final tempDir = await getTemporaryDirectory();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Data berhasil dihapus! Silakan restart aplikasi.'),
            backgroundColor: Colors.green,
          ),
        );
        setState(() {
          _isExpanded = false;
        });
      }
    } catch (e) {
      debugPrint('Error resetting data: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal menghapus data: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  String _formatSize(double kb) {
    if (kb >= 1024) {
      return '${(kb / 1024).toStringAsFixed(2)} MB';
    }
    return '${kb.toStringAsFixed(2)} KB';
  }
}
