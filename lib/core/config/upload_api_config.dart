import 'env.dart';

class UploadApiConfig {
  /// Base URL of the upload API, e.g., https://api.parepare.stat7300.net
  static String get baseUrl => Env.uploadApiBaseUrl;

  /// Upload path, defaults to '/upload' (pretty URL)
  static String get uploadPath => Env.uploadApiUploadPath;

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
    return Env.uploadApiMaxBytes;
  }
}
