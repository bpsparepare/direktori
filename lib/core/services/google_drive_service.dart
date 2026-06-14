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
  GoogleDriveService({
    SupabaseClient? client,
    this.primaryCompanyEmail = 'bps737273@gmail.com',
  }) : _supabaseClient = client ?? SupabaseConfig.client;

  final SupabaseClient _supabaseClient;
  final String primaryCompanyEmail;
  Map<String, dynamic>? _lastSelectedTokenMeta;

  DateTime? _tryParseTokenExpiry(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;

    var normalized = raw.contains('T') ? raw : raw.replaceFirst(' ', 'T');
    if (RegExp(r'[+-]\d\d$').hasMatch(normalized)) {
      normalized =
          '${normalized.substring(0, normalized.length - 3)}'
          '${normalized.substring(normalized.length - 3)}:00';
    } else if (normalized.endsWith('+00')) {
      normalized = '$normalized:00';
    }

    final parsed = DateTime.tryParse(normalized);
    if (parsed == null) {
      debugPrint('GoogleDriveService: token_expiry tidak bisa diparse: $raw');
    }
    return parsed;
  }

  void _setAndLogTokenMeta({
    required String source,
    required Map<String, dynamic> tokenData,
  }) {
    final refreshToken = tokenData['refresh_token']?.toString();
    _lastSelectedTokenMeta = {
      'source': source,
      'id': tokenData['id']?.toString(),
      'google_email': tokenData['google_email']?.toString(),
      'token_expiry': tokenData['token_expiry']?.toString(),
      'has_refresh_token': refreshToken != null && refreshToken.isNotEmpty,
      'is_shared_company_account': tokenData['is_shared_company_account'],
    };
    debugPrint(
      'GoogleDriveService: token_source=$source '
      'email=${_lastSelectedTokenMeta?['google_email']} '
      'is_shared=${_lastSelectedTokenMeta?['is_shared_company_account']} '
      'has_refresh=${_lastSelectedTokenMeta?['has_refresh_token']} '
      'expiry=${_lastSelectedTokenMeta?['token_expiry']} '
      'id=${_lastSelectedTokenMeta?['id']}',
    );
  }

  void _logOpTokenMeta(String op) {
    final meta = _lastSelectedTokenMeta;
    if (meta == null) {
      debugPrint('GoogleDriveService: $op token_meta=none');
      return;
    }

    debugPrint(
      'GoogleDriveService: $op token_source=${meta['source']} '
      'email=${meta['google_email']} '
      'is_shared=${meta['is_shared_company_account']} '
      'has_refresh=${meta['has_refresh_token']} '
      'expiry=${meta['token_expiry']} id=${meta['id']}',
    );
  }

  Future<Map<String, dynamic>?> _loadTokenData() async {
    Map<String, dynamic>? tokenData;
    final authUser = _supabaseClient.auth.currentUser;

    if (authUser != null) {
      try {
        final appUser = await _supabaseClient
            .from('users')
            .select('id')
            .eq('auth_uid', authUser.id)
            .maybeSingle();

        final internalUserId = appUser?['id']?.toString();
        if (internalUserId != null && internalUserId.isNotEmpty) {
          tokenData = await _supabaseClient
              .from('google_account_tokens')
              .select(
                'id, access_token, refresh_token, token_expiry, user_id, '
                'google_email, is_shared_company_account, updated_at',
              )
              .eq('user_id', internalUserId)
              .or(
                'is_shared_company_account.is.null,'
                'is_shared_company_account.eq.false',
              )
              .order('updated_at', ascending: false)
              .limit(1)
              .maybeSingle();

          if (tokenData != null) {
            _setAndLogTokenMeta(source: 'personal', tokenData: tokenData);
          }
        }
      } catch (e) {
        debugPrint('GoogleDriveService: gagal baca token personal: $e');
      }
    }

    if (tokenData == null) {
      try {
        tokenData = await _supabaseClient
            .from('google_account_tokens')
            .select(
              'id, access_token, refresh_token, token_expiry, user_id, '
              'google_email, is_shared_company_account, updated_at',
            )
            .eq('google_email', primaryCompanyEmail)
            .limit(1)
            .maybeSingle();

        if (tokenData != null) {
          _setAndLogTokenMeta(source: 'primary_email', tokenData: tokenData);
        }
      } catch (e) {
        debugPrint('GoogleDriveService: gagal baca token primary email: $e');
      }
    }

    if (tokenData == null) {
      try {
        tokenData = await _supabaseClient
            .from('google_account_tokens')
            .select(
              'id, access_token, refresh_token, token_expiry, user_id, '
              'google_email, is_shared_company_account, updated_at',
            )
            .eq('is_shared_company_account', true)
            .order('updated_at', ascending: false)
            .limit(1)
            .maybeSingle();

        if (tokenData != null) {
          _setAndLogTokenMeta(source: 'shared_flag', tokenData: tokenData);
        }
      } catch (e) {
        debugPrint('GoogleDriveService: gagal baca token shared: $e');
      }
    }

    return tokenData;
  }

  Future<String?> getAccessToken({bool forceRefresh = false}) async {
    try {
      final tokenData = await _loadTokenData();
      if (tokenData == null) return null;

      final accessTokenRaw = tokenData['access_token']?.toString() ?? '';
      if (accessTokenRaw.isEmpty) return null;

      var accessToken = accessTokenRaw;
      final refreshToken = tokenData['refresh_token']?.toString();
      final tokenExpiry = _tryParseTokenExpiry(
        tokenData['token_expiry']?.toString(),
      );
      final tokenId = tokenData['id']?.toString();
      final now = DateTime.now();
      const buffer = Duration(minutes: 5);

      final shouldRefresh =
          forceRefresh ||
          (tokenExpiry != null && now.isAfter(tokenExpiry.subtract(buffer)));

      if (shouldRefresh) {
        if (refreshToken == null || refreshToken.isEmpty) {
          debugPrint(
            'GoogleDriveService: token perlu refresh tetapi refresh_token kosong',
          );
          return tokenExpiry != null && now.isBefore(tokenExpiry)
              ? accessToken
              : null;
        }

        final refreshedToken = await _refreshAccessToken(refreshToken);
        if (refreshedToken == null || refreshedToken.isEmpty) {
          return null;
        }

        accessToken = refreshedToken;
        if (tokenId != null && tokenId.isNotEmpty) {
          await _supabaseClient
              .from('google_account_tokens')
              .update({
                'access_token': refreshedToken,
                'updated_at': DateTime.now().toIso8601String(),
                'token_expiry': DateTime.now()
                    .add(const Duration(seconds: 3500))
                    .toIso8601String(),
              })
              .eq('id', tokenId);
        }
      } else if (tokenExpiry != null && now.isAfter(tokenExpiry)) {
        return null;
      }

      return accessToken;
    } catch (e) {
      debugPrint('GoogleDriveService: gagal mendapatkan access token: $e');
      return null;
    }
  }

  Future<String?> _refreshAccessToken(String refreshToken) async {
    final clientId = SupabaseConfig.googleClientId.trim();
    if (clientId.isEmpty) {
      debugPrint('GoogleDriveService: GOOGLE_CLIENT_ID belum diatur');
      return null;
    }

    try {
      final response = await http.post(
        Uri.parse('https://oauth2.googleapis.com/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'client_id': clientId,
          'grant_type': 'refresh_token',
          'refresh_token': refreshToken,
        },
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint(
          'GoogleDriveService: refresh token gagal (${response.statusCode}) '
          '${response.body}',
        );
        return null;
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      return decoded['access_token']?.toString();
    } catch (e) {
      debugPrint('GoogleDriveService: exception saat refresh token: $e');
      return null;
    }
  }

  Future<http.Response> _authorizedRequest(
    String opName,
    Future<http.Response> Function(String token) performer,
  ) async {
    var token = await getAccessToken();
    if (token == null || token.isEmpty) {
      throw const GoogleDriveException(
        'Token Google Drive kadaluarsa. Mohon hubungkan ulang akun Google Drive.',
      );
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
}
