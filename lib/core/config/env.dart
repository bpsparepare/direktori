import 'package:flutter_dotenv/flutter_dotenv.dart' as dotenv;

/// Centralized environment configuration.
///
/// Primary source: values injected at build time via `--dart-define` or
/// `--dart-define-from-file`.
/// Fallback: `.env` via flutter_dotenv for legacy local dev on mobile/desktop.
class Env {
  // Compile-time injected values (empty string if not provided)
  static const String _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String _supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY');
  static const String _googleClientId =
      String.fromEnvironment('GOOGLE_CLIENT_ID');

  static const String _uploadApiBaseUrl =
      String.fromEnvironment('UPLOAD_API_BASE_URL');
  static const String _uploadApiUploadPath =
      String.fromEnvironment('UPLOAD_API_UPLOAD_PATH');
  static const String _uploadApiMaxBytesStr =
      String.fromEnvironment('UPLOAD_API_MAX_BYTES');

  /// Read Supabase URL, prefer dart-define, fallback to dotenv.
  static String get supabaseUrl {
    if (_supabaseUrl.isNotEmpty) return _supabaseUrl;
    try {
      return dotenv.dotenv.env['SUPABASE_URL'] ?? '';
    } catch (e) {
      // dotenv not initialized, return empty string
      return '';
    }
  }

  /// Read Supabase anon key, prefer dart-define, fallback to dotenv.
  static String get supabaseAnonKey {
    if (_supabaseAnonKey.isNotEmpty) return _supabaseAnonKey;
    try {
      return dotenv.dotenv.env['SUPABASE_ANON_KEY'] ?? '';
    } catch (e) {
      // dotenv not initialized, return empty string
      return '';
    }
  }

  /// Read Google OAuth client ID, prefer dart-define, fallback to dotenv.
  static String get googleClientId {
    if (_googleClientId.isNotEmpty) return _googleClientId;
    try {
      return dotenv.dotenv.env['GOOGLE_CLIENT_ID'] ?? '';
    } catch (e) {
      // dotenv not initialized, return empty string
      return '';
    }
  }

  /// Upload API base URL, prefer dart-define, fallback to dotenv, then default.
  static String get uploadApiBaseUrl {
    if (_uploadApiBaseUrl.trim().isNotEmpty) return _uploadApiBaseUrl.trim();
    try {
      final v = dotenv.dotenv.env['UPLOAD_API_BASE_URL']?.trim();
      if (v != null && v.isNotEmpty) return v;
    } catch (e) {
      // dotenv not initialized, continue to default
    }
    return 'https://api.parepare.stat7300.net';
  }

  /// Upload API path, prefer dart-define, fallback to dotenv, then default.
  static String get uploadApiUploadPath {
    if (_uploadApiUploadPath.trim().isNotEmpty) {
      final p = _uploadApiUploadPath.trim();
      return p.startsWith('/') ? p : '/$p';
    }
    try {
      final v = dotenv.dotenv.env['UPLOAD_API_UPLOAD_PATH']?.trim();
      if (v != null && v.isNotEmpty) {
        return v.startsWith('/') ? v : '/$v';
      }
    } catch (e) {
      // dotenv not initialized, continue to default
    }
    return '/upload';
  }

  /// Upload API max bytes, prefer dart-define, fallback to dotenv, then default 10MB.
  static int get uploadApiMaxBytes {
    // Try dart-define string -> int
    if (_uploadApiMaxBytesStr.trim().isNotEmpty) {
      final parsed = int.tryParse(_uploadApiMaxBytesStr.trim());
      if (parsed != null) return parsed;
    }
    // Try dotenv
    try {
      final v = dotenv.dotenv.env['UPLOAD_API_MAX_BYTES'];
      if (v != null) {
        final parsed = int.tryParse(v.trim());
        if (parsed != null) return parsed;
      }
    } catch (e) {
      // dotenv not initialized, continue to default
    }
    // Default 10MB
    return 10 * 1024 * 1024;
  }
}