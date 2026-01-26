import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_version.dart';
import '../config/supabase_config.dart';

class UpdateInfo {
  final bool hasUpdate;
  final bool forceUpdate;
  final String? downloadUrl;
  final String latestVersion;

  UpdateInfo({
    required this.hasUpdate,
    this.forceUpdate = false,
    this.downloadUrl,
    required this.latestVersion,
  });
}

class VersionCheckService {
  /// Memeriksa pembaruan aplikasi untuk semua platform.
  Future<UpdateInfo?> checkUpdate() async {
    try {
      // 1. Cek Throttle (Jeda 2 Jam)
      final prefs = await SharedPreferences.getInstance();
      final lastCheck = prefs.getInt('last_version_check_time');
      final now = DateTime.now().millisecondsSinceEpoch;
      const throttleDuration = 2 * 60 * 60 * 1000; // 2 Jam dalam milidetik

      if (lastCheck != null) {
        final diff = now - lastCheck;
        if (diff < throttleDuration) {
          // debugPrint('Version check skipped. Next check in: ${(throttleDuration - diff) / 60000} mins');
          return null;
        }
      }

      final localVersion = AppVersion.version;
      final localBuildNumber = int.tryParse(AppVersion.buildNumber) ?? 0;

      debugPrint('Local Version: $localVersion+$localBuildNumber');

      // Ambil versi terbaru dari Supabase
      final client = SupabaseConfig.client;

      // Mengambil data versi terbaru berdasarkan created_at desc
      final response = await client
          .from('app_versions')
          .select()
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response != null) {
        final data = response;
        final serverVersion = data['version'] as String;
        final serverBuildNumber =
            int.tryParse(data['build_number'].toString()) ?? 0;
        final forceUpdate = data['force_update'] as bool? ?? false;

        // Tentukan download URL berdasarkan platform
        String? downloadUrl = data['download_url']; // Default / Web URL
        if (!kIsWeb) {
          if (Platform.isAndroid) {
            downloadUrl = data['android_url'] ?? downloadUrl;
          } else if (Platform.isWindows) {
            downloadUrl = data['windows_url'] ?? downloadUrl;
          } else if (Platform.isIOS) {
            downloadUrl = data['ios_url'] ?? downloadUrl;
          }
        }

        debugPrint('Server Version: $serverVersion+$serverBuildNumber');

        // Logika perbandingan versi
        bool hasUpdate = false;
        if (serverBuildNumber > localBuildNumber) {
          hasUpdate = true;
        } else if (serverBuildNumber == localBuildNumber) {
          // Jika build number sama, cek string version (opsional)
          if (serverVersion != localVersion) {
            // Bisa tambahkan logic semver di sini jika perlu
          }
        }

        if (hasUpdate) {
          return UpdateInfo(
            hasUpdate: true,
            forceUpdate: forceUpdate,
            downloadUrl: downloadUrl,
            latestVersion: serverVersion,
          );
        }
      } else {
        debugPrint('Tidak ada data versi ditemukan di database.');
      }
    } catch (e) {
      debugPrint('Error checking version from Supabase: $e');
    }
    return null;
  }
}
