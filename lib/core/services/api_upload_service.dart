import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import '../config/upload_api_config.dart';
import 'image_upload_service.dart';

class ApiUploadService implements ImageUploadService {
  final String endpoint;

  ApiUploadService({String? endpoint})
    : endpoint = endpoint ?? UploadApiConfig.uploadEndpoint;

  @override
  String get serviceName => 'Upload API';

  @override
  Future<bool> isConfigured() async {
    return endpoint.isNotEmpty;
  }

  @override
  Future<String> uploadImage(File imageFile, {String? fileName}) async {
    try {
      final filename = fileName ?? p.basename(imageFile.path);
      final mimeType =
          lookupMimeType(imageFile.path) ?? 'application/octet-stream';
      final uri = Uri.parse(endpoint);

      final request = http.MultipartRequest('POST', uri);
      request.files.add(
        await http.MultipartFile.fromPath(
          'file',
          imageFile.path,
          filename: filename,
          contentType: _contentTypeFromMime(mimeType),
        ),
      );

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);
      return _parseUploadResponse(response);
    } catch (e) {
      throw ImageUploadException(
        'Upload gagal: ${e.toString()}',
        originalError: e,
      );
    }
  }

  @override
  Future<String> uploadImageFromBytes(
    List<int> imageBytes,
    String fileName, {
    String? mimeType,
  }) async {
    try {
      final actualMime = mimeType ?? 'application/octet-stream';
      final uri = Uri.parse(endpoint);

      final request = http.MultipartRequest('POST', uri);
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          imageBytes,
          filename: fileName,
          contentType: _contentTypeFromMime(actualMime),
        ),
      );

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);
      return _parseUploadResponse(response);
    } catch (e) {
      throw ImageUploadException(
        'Upload gagal: ${e.toString()}',
        originalError: e,
      );
    }
  }

  @override
  Future<bool> deleteImage(String imageUrl) async {
    // Not supported by simple Upload API
    throw ImageUploadException('Delete tidak didukung di Upload API sederhana');
  }

  String _parseUploadResponse(http.Response response) {
    if (response.statusCode != 200) {
      // Try to parse JSON error
      try {
        final data = json.decode(response.body);
        final err = data['error'] ?? 'Status ${response.statusCode}';
        throw ImageUploadException('Server error: $err');
      } catch (_) {
        throw ImageUploadException(
          'Server mengembalikan status ${response.statusCode}',
        );
      }
    }

    try {
      final data = json.decode(response.body);
      final success = data['success'] == true;
      final url = data['url'] as String?;
      if (!success || url == null || url.isEmpty) {
        throw ImageUploadException('Respon tidak valid dari server upload');
      }
      return url;
    } catch (e) {
      throw ImageUploadException(
        'Gagal memproses respon server',
        originalError: e,
      );
    }
  }

  /// Convert MIME string to MediaType for http package
  static MediaType? _contentTypeFromMime(String mime) {
    try {
      final parts = mime.split('/');
      if (parts.length == 2) {
        return MediaType(parts[0], parts[1]);
      }
    } catch (_) {}
    return null;
  }
}
