import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

class GoogleDriveException implements Exception {
  final String message;

  const GoogleDriveException(this.message);

  @override
  String toString() => message;
}

class GoogleDriveService {
  static const String _tokenFunctionName = 'google-drive-refresh';
  static const String _defaultTokenError =
      'Token Google Drive kadaluarsa. Mohon hubungkan ulang akun Google Drive.';

  GoogleDriveService({SupabaseClient? client})
    : _supabaseClient = client ?? SupabaseConfig.client;

  final SupabaseClient _supabaseClient;
  final Map<String, String> _folderIdCache = {};

  /// Access token terakhir dari server; dipakai ulang sampai mendekati expiry
  /// supaya tidak memanggil Edge Function di setiap request Drive.
  String? _cachedAccessToken;
  DateTime? _cachedExpiry;
  Map<String, dynamic>? _lastTokenMeta;
  String? _lastTokenError;

  void _logOpTokenMeta(String op) {
    final meta = _lastTokenMeta;
    if (meta == null) {
      debugPrint('GoogleDriveService: $op token_meta=none');
      return;
    }

    debugPrint(
      'GoogleDriveService: $op token_source=${meta['source']} '
      'email=${meta['google_email']} '
      'is_shared=${meta['is_shared_company_account']} '
      'refreshed=${meta['refreshed']} '
      'expiry=${meta['expires_at']} id=${meta['token_id']}',
    );
  }

  /// Ambil access token Google Drive lewat Edge Function `google-drive-refresh`.
  ///
  /// Pemilihan akun, refresh, dan penyimpanan token dilakukan di server dengan
  /// service role, sehingga `refresh_token` tidak pernah sampai ke aplikasi.
  /// Mengembalikan null bila gagal; alasannya disimpan di [_lastTokenError].
  Future<String?> getAccessToken({bool forceRefresh = false}) async {
    final cached = _cachedAccessToken;
    final cachedExpiry = _cachedExpiry;
    if (!forceRefresh &&
        cached != null &&
        cachedExpiry != null &&
        DateTime.now().isBefore(
          cachedExpiry.subtract(const Duration(minutes: 1)),
        )) {
      return cached;
    }

    _cachedAccessToken = null;
    _cachedExpiry = null;
    _lastTokenError = null;

    try {
      final response = await _supabaseClient.functions.invoke(
        _tokenFunctionName,
        body: {'mode': 'access_token', 'force_refresh': forceRefresh},
      );
      final data = response.data;
      if (data is! Map) {
        debugPrint('GoogleDriveService: token function payload tidak valid');
        return null;
      }

      final accessToken = data['access_token']?.toString() ?? '';
      if (accessToken.isEmpty) {
        debugPrint('GoogleDriveService: token function tanpa access_token');
        return null;
      }

      _lastTokenMeta = Map<String, dynamic>.from(data)..remove('access_token');
      _logOpTokenMeta('getAccessToken');
      _cachedAccessToken = accessToken;
      _cachedExpiry = DateTime.tryParse(data['expires_at']?.toString() ?? '');
      return accessToken;
    } on FunctionException catch (e) {
      final details = e.details;
      if (details is Map) {
        _lastTokenMeta = Map<String, dynamic>.from(details);
        final message = details['message']?.toString();
        if (message != null && message.isNotEmpty) _lastTokenError = message;
      }
      debugPrint(
        'GoogleDriveService: token function gagal (${e.status}): $details',
      );
      return null;
    } catch (e) {
      debugPrint('GoogleDriveService: gagal mendapatkan access token: $e');
      return null;
    }
  }

  Future<http.Response> _authorizedRequest(
    String opName,
    Future<http.Response> Function(String token) performer,
  ) async {
    var token = await getAccessToken();
    if (token == null || token.isEmpty) {
      throw GoogleDriveException(_lastTokenError ?? _defaultTokenError);
    }

    _logOpTokenMeta(opName);
    var response = await performer(token);
    if (response.statusCode == 401) {
      token = await getAccessToken(forceRefresh: true);
      if (token != null && token.isNotEmpty) {
        _logOpTokenMeta('${opName}_retry');
        response = await performer(token);
      }
    }

    return response;
  }

  Never _throwGoogleApiError(
    http.Response response, {
    String action = 'Proses',
  }) {
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final error = body['error'];
      final message = error is Map<String, dynamic>
          ? error['message']?.toString() ?? 'Unknown error'
          : 'Unknown error';

      if (response.statusCode == 403) {
        if (message.contains('insufficient authentication scopes')) {
          throw const GoogleDriveException(
            'Izin kurang (scope). Mohon hubungkan ulang akun Google dengan izin penuh.',
          );
        }

        final errors = error is Map<String, dynamic>
            ? error['errors'] as List<dynamic>?
            : null;
        if (errors != null && errors.isNotEmpty) {
          final reason = (errors.first as Map<String, dynamic>)['reason']
              ?.toString();
          if (reason == 'insufficientPermissions') {
            throw const GoogleDriveException(
              'Akses ditolak. Pastikan akun Google yang terhubung memiliki akses edit ke folder ini.',
            );
          }
        }
      }

      throw GoogleDriveException(
        '$action gagal (${response.statusCode}): $message',
      );
    } catch (e) {
      if (e is GoogleDriveException) rethrow;
      throw GoogleDriveException(
        '$action gagal (${response.statusCode}): ${response.body}',
      );
    }
  }

  Future<List<Map<String, dynamic>>> listFiles(String folderId) async {
    final response = await _authorizedRequest('listFiles', (token) {
      final uri = Uri.https('www.googleapis.com', '/drive/v3/files', {
        'q': "'$folderId' in parents and trashed=false",
        'fields':
            'files(id,name,mimeType,webViewLink,webContentLink,iconLink,'
            'thumbnailLink,size,createdTime)',
        'orderBy': 'createdTime desc',
        'includeItemsFromAllDrives': 'true',
        'supportsAllDrives': 'true',
      });
      return http.get(uri, headers: {'Authorization': 'Bearer $token'});
    });

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return List<Map<String, dynamic>>.from(data['files'] ?? const []);
    }

    _throwGoogleApiError(response, action: 'Memuat file');
  }

  Future<String> ensureFolderInParent(
    String parentId,
    String folderName,
  ) async {
    final cacheKey = '$parentId|$folderName';
    final cached = _folderIdCache[cacheKey];
    if (cached != null && cached.isNotEmpty) return cached;

    final existingId = await _findFolderIdInParent(
      parentId: parentId,
      folderName: folderName,
    );
    if (existingId != null && existingId.isNotEmpty) {
      _folderIdCache[cacheKey] = existingId;
      return existingId;
    }

    final createdId = await createFolder(parentId, folderName);
    if (createdId.isNotEmpty) {
      _folderIdCache[cacheKey] = createdId;
    }
    return createdId;
  }

  Future<String?> _findFolderIdInParent({
    required String parentId,
    required String folderName,
  }) async {
    final escaped = _escapeDriveQueryLiteral(folderName);
    final response = await _authorizedRequest('findFolder', (token) {
      final uri = Uri.https('www.googleapis.com', '/drive/v3/files', {
        'q':
            "mimeType='application/vnd.google-apps.folder' and "
            "name='$escaped' and "
            "'$parentId' in parents and trashed=false",
        'fields': 'files(id,name)',
        'pageSize': '1',
        'includeItemsFromAllDrives': 'true',
        'supportsAllDrives': 'true',
      });
      return http.get(uri, headers: {'Authorization': 'Bearer $token'});
    });

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final files = data['files'];
      if (files is List && files.isNotEmpty) {
        final first = files.first;
        if (first is Map) {
          final id = first['id']?.toString();
          return id != null && id.isNotEmpty ? id : null;
        }
      }
      return null;
    }

    _throwGoogleApiError(response, action: 'Mencari folder');
  }

  Future<Map<String, dynamic>> uploadFile(
    String folderId,
    String fileName,
    Uint8List fileBytes,
  ) async {
    final response = await _authorizedRequest('uploadFile', (token) async {
      final uri = Uri.parse(
        'https://www.googleapis.com/upload/drive/v3/files'
        '?uploadType=multipart'
        '&supportsAllDrives=true'
        '&fields=id,webViewLink,webContentLink,thumbnailLink,name',
      );
      final request = http.MultipartRequest('POST', uri);
      request.headers['Authorization'] = 'Bearer $token';

      final metadata = jsonEncode({
        'name': fileName,
        'parents': [folderId],
      });

      request.files.add(
        http.MultipartFile.fromString(
          'metadata',
          metadata,
          contentType: MediaType('application', 'json', {'charset': 'UTF-8'}),
        ),
      );

      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          fileBytes,
          filename: fileName,
          contentType: MediaType.parse(_mimeTypeForFileName(fileName)),
        ),
      );

      final streamed = await request.send();
      return http.Response.fromStream(streamed);
    });

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final fileId = data['id']?.toString();
      if (fileId != null && fileId.isNotEmpty) {
        try {
          await makeFilePublic(fileId);
        } catch (e) {
          debugPrint('GoogleDriveService: gagal set public file $fileId: $e');
        }
      }
      return data;
    }

    _throwGoogleApiError(response, action: 'Upload file');
  }

  Future<void> deleteFile(String fileId) async {
    final response = await _authorizedRequest('deleteFile', (token) {
      final uri = Uri.https('www.googleapis.com', '/drive/v3/files/$fileId', {
        'supportsAllDrives': 'true',
      });
      return http.delete(uri, headers: {'Authorization': 'Bearer $token'});
    });

    if (response.statusCode == 204 || response.statusCode == 200) {
      return;
    }

    _throwGoogleApiError(response, action: 'Menghapus file');
  }

  Future<String> createFolder(String parentId, String folderName) async {
    final response = await _authorizedRequest('createFolder', (token) {
      final uri = Uri.https('www.googleapis.com', '/drive/v3/files', {
        'supportsAllDrives': 'true',
        'fields': 'id,name,webViewLink',
      });
      return http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'name': folderName,
          'mimeType': 'application/vnd.google-apps.folder',
          'parents': [parentId],
        }),
      );
    });

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['id']?.toString() ?? '';
    }

    _throwGoogleApiError(response, action: 'Membuat folder');
  }

  Future<void> makeFilePublic(String fileId) async {
    final response = await _authorizedRequest('makeFilePublic', (token) {
      final uri = Uri.https(
        'www.googleapis.com',
        '/drive/v3/files/$fileId/permissions',
        {'supportsAllDrives': 'true'},
      );
      return http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'role': 'reader', 'type': 'anyone'}),
      );
    });

    if (response.statusCode == 200 || response.statusCode == 201) {
      return;
    }

    _throwGoogleApiError(response, action: 'Mengubah akses file');
  }

  String _mimeTypeForFileName(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.heic')) return 'image/heic';
    return 'image/jpeg';
  }

  String _escapeDriveQueryLiteral(String value) {
    return value.replaceAll("'", r"\'");
  }
}
