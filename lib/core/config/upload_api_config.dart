import 'package:flutter_dotenv/flutter_dotenv.dart';

class UploadApiConfig {
  /// Base URL of the upload API, e.g., https://api.parepare.stat7300.net
  static String get baseUrl =>
      dotenv.env['UPLOAD_API_BASE_URL']?.trim() ??
      'https://api.parepare.stat7300.net';

  /// Upload path, defaults to '/upload' (pretty URL)
  static String get uploadPath =>
      dotenv.env['UPLOAD_API_UPLOAD_PATH']?.trim() ?? '/upload';

  /// Full endpoint URL for upload
  static String get uploadEndpoint {
    final normalizedBase = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final normalizedPath = uploadPath.startsWith('/')
        ? uploadPath
        : '/$uploadPath';
    return '$normalizedBase$normalizedPath';
  }

  /// Maximum file size (bytes) — should match server side (10MB default)
  static int get maxFileSizeBytes {
    final v = dotenv.env['UPLOAD_API_MAX_BYTES'];
    if (v == null) return 10 * 1024 * 1024;
    final parsed = int.tryParse(v);
    return parsed ?? 10 * 1024 * 1024;
  }
}
