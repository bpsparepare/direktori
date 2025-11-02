import 'dart:io';
import 'image_upload_service.dart';
import 'api_upload_service.dart';

/// Service locator for image upload services
/// This makes it easy to switch between different providers
class ImageServiceLocator {
  static ImageUploadService? _instance;

  /// Get current image upload service instance
  static ImageUploadService get instance {
    if (_instance == null) {
      throw Exception(
        'ImageUploadService not initialized. Call initialize() first.',
      );
    }
    return _instance!;
  }

  // Google Drive initialization methods removed as integration is no longer used

  /// Initialize with custom service (for future migration)
  static void initializeWithCustomService(ImageUploadService service) {
    _instance = service;
  }

  /// Initialize with Upload API service (shared hosting)
  static Future<void> initializeWithUploadApi({String? endpoint}) async {
    final service = ApiUploadService(endpoint: endpoint);
    _instance = service;
  }

  /// Check if service is initialized
  static bool get isInitialized => _instance != null;

  /// Reset service (useful for testing)
  static void reset() {
    _instance = null;
  }

  /// Get service name for debugging
  static String? get currentServiceName => _instance?.serviceName;
}

/// Future implementation placeholder for your own server
class CustomServerUploadService implements ImageUploadService {
  final String baseUrl;
  final String? apiKey;

  CustomServerUploadService({required this.baseUrl, this.apiKey});

  @override
  Future<String> uploadImage(File imageFile, {String? fileName}) async {
    // TODO: Implement your server upload logic here
    // This will be easy to implement when you have your own server
    throw UnimplementedError('Custom server upload not implemented yet');
  }

  @override
  Future<String> uploadImageFromBytes(
    List<int> imageBytes,
    String fileName, {
    String? mimeType,
  }) async {
    // TODO: Implement your server upload logic here
    throw UnimplementedError('Custom server upload not implemented yet');
  }

  @override
  Future<bool> deleteImage(String imageUrl) async {
    // TODO: Implement your server delete logic here
    throw UnimplementedError('Custom server delete not implemented yet');
  }

  @override
  Future<bool> isConfigured() async {
    // TODO: Check server connectivity
    return false;
  }

  @override
  String get serviceName => 'Custom Server';
}
