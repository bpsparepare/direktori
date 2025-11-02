import 'dart:io';

/// Abstract interface for image upload service
/// This allows easy migration between different upload providers (Google Drive, Firebase, etc.)
abstract class ImageUploadService {
  /// Upload an image file and return the public URL
  Future<String> uploadImage(File imageFile, {String? fileName});

  /// Upload image from bytes and return the public URL
  Future<String> uploadImageFromBytes(
    List<int> imageBytes,
    String fileName, {
    String? mimeType,
  });

  /// Delete an image by URL or file ID
  Future<bool> deleteImage(String imageUrl);

  /// Check if the service is properly configured
  Future<bool> isConfigured();

  /// Get the service name (for debugging/logging)
  String get serviceName;
}

/// Result class for upload operations
class ImageUploadResult {
  final bool success;
  final String? url;
  final String? error;
  final String? fileId;

  const ImageUploadResult({
    required this.success,
    this.url,
    this.error,
    this.fileId,
  });

  factory ImageUploadResult.success(String url, {String? fileId}) {
    return ImageUploadResult(success: true, url: url, fileId: fileId);
  }

  factory ImageUploadResult.failure(String error) {
    return ImageUploadResult(success: false, error: error);
  }
}

/// Exception class for image upload errors
class ImageUploadException implements Exception {
  final String message;
  final String? code;
  final dynamic originalError;

  const ImageUploadException(this.message, {this.code, this.originalError});

  @override
  String toString() => 'ImageUploadException: $message';
}
