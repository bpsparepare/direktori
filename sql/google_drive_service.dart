// import 'dart:convert';
// import 'dart:typed_data';

// import 'package:flutter/foundation.dart';
// import 'package:flutter_riverpod/flutter_riverpod.dart';
// import 'package:http/http.dart' as http;
// import 'package:http_parser/http_parser.dart';
// import 'package:supabase_flutter/supabase_flutter.dart';

// import '../../features/auth/presentation/providers/auth_provider.dart';

// final googleDriveServiceProvider = Provider<GoogleDriveService>((ref) {
//   return GoogleDriveService(ref);
// });

// class GoogleDriveService {
//   final Ref _ref;
//   final SupabaseClient _supabaseClient = Supabase.instance.client;
//   Map<String, dynamic>? _lastSelectedTokenMeta;

//   GoogleDriveService(this._ref);

//   DateTime? _tryParseTokenExpiry(String? raw) {
//     if (raw == null) return null;
//     var normalized = raw.contains('T') ? raw : raw.replaceFirst(' ', 'T');
//     if (RegExp(r'[+-]\d\d$').hasMatch(normalized)) {
//       normalized = '${normalized.substring(0, normalized.length - 3)}'
//           '${normalized.substring(normalized.length - 3)}:00';
//     } else if (normalized.endsWith('+00')) {
//       normalized = '$normalized:00';
//     }
//     final parsed = DateTime.tryParse(normalized);
//     if (parsed == null) {
//       debugPrint('GoogleDriveService: token_expiry tidak bisa diparse: $raw');
//     }
//     return parsed;
//   }

//   void _setAndLogTokenMeta({
//     required String source,
//     required Map<String, dynamic> tokenData,
//   }) {
//     final tokenId = tokenData['id'];
//     final email = tokenData['google_email'];
//     final expiryRaw = tokenData['token_expiry'];
//     final refreshToken = tokenData['refresh_token'] as String?;
//     final isShared = tokenData['is_shared_company_account'];
//     _lastSelectedTokenMeta = {
//       'source': source,
//       'id': tokenId,
//       'google_email': email,
//       'token_expiry': expiryRaw,
//       'has_refresh_token': refreshToken != null && refreshToken.isNotEmpty,
//       'is_shared_company_account': isShared,
//     };
//     debugPrint(
//       'GoogleDriveService: token_source=$source email=$email is_shared=$isShared '
//       'has_refresh=${_lastSelectedTokenMeta?['has_refresh_token']} expiry=$expiryRaw id=$tokenId',
//     );
//   }

//   void _logOpTokenMeta(String op) {
//     final meta = _lastSelectedTokenMeta;
//     if (meta == null) {
//       debugPrint('GoogleDriveService: $op token_meta=none');
//       return;
//     }
//     debugPrint(
//       'GoogleDriveService: $op token_source=${meta['source']} email=${meta['google_email']} '
//       'is_shared=${meta['is_shared_company_account']} has_refresh=${meta['has_refresh_token']} '
//       'expiry=${meta['token_expiry']} id=${meta['id']}',
//     );
//   }

//   Future<String?> getAccessToken({bool forceRefresh = false}) async {
//     try {
//       Map<String, dynamic>? tokenData;

//       final user = _supabaseClient.auth.currentUser;
//       if (user != null) {
//         Map<String, dynamic>? userData;
//         try {
//           userData = await _supabaseClient
//               .from('users')
//               .select('id')
//               .eq('auth_uid', user.id)
//               .maybeSingle();
//         } catch (e) {
//           debugPrint('GoogleDriveService: gagal baca internal user id: $e');
//           userData = null;
//         }

//         if (userData != null) {
//           final internalUserId = userData['id'] as String;
//           try {
//             tokenData = await _supabaseClient
//                 .from('google_account_tokens')
//                 .select(
//                     'id, access_token, refresh_token, token_expiry, user_id, google_email, is_shared_company_account')
//                 .eq('user_id', internalUserId)
//                 .or('is_shared_company_account.is.null,is_shared_company_account.eq.false')
//                 .order('updated_at', ascending: false)
//                 .limit(1)
//                 .maybeSingle();
//             if (tokenData != null) {
//               _setAndLogTokenMeta(source: 'personal', tokenData: tokenData);
//             }
//           } catch (e) {
//             debugPrint('GoogleDriveService: gagal baca token personal: $e');
//           }
//         }
//       }

//       try {
//         if (tokenData == null) {
//           tokenData = await _supabaseClient
//               .from('google_account_tokens')
//               .select(
//                   'id, access_token, refresh_token, token_expiry, user_id, google_email, is_shared_company_account')
//               .eq('google_email', 'bps737273@gmail.com')
//               .limit(1)
//               .maybeSingle();
//           if (tokenData != null) {
//             _setAndLogTokenMeta(source: 'primary_email', tokenData: tokenData);
//           }
//         }
//       } catch (e) {
//         debugPrint(
//             'GoogleDriveService: gagal baca token primary (bps737273@gmail.com): $e');
//       }

//       if (tokenData == null) {
//         try {
//           tokenData = await _supabaseClient
//               .from('google_account_tokens')
//               .select(
//                   'id, access_token, refresh_token, token_expiry, user_id, google_email, is_shared_company_account')
//               .eq('is_shared_company_account', true)
//               .order('updated_at', ascending: false)
//               .limit(1)
//               .maybeSingle();
//           if (tokenData != null) {
//             _setAndLogTokenMeta(source: 'shared_flag', tokenData: tokenData);
//           }
//         } catch (e) {
//           debugPrint(
//               'GoogleDriveService: gagal baca token shared (is_shared_company_account=true): $e');
//         }
//       }

//       if (tokenData == null) return null;

//       final accessTokenRaw = tokenData['access_token'] as String?;
//       if (accessTokenRaw == null || accessTokenRaw.isEmpty) return null;
//       String accessToken = accessTokenRaw;
//       final refreshToken = tokenData['refresh_token'] as String?;
//       final tokenExpiryStr = tokenData['token_expiry'] as String?;
//       final tokenId = tokenData['id'] as String?;

//       if (tokenExpiryStr != null) {
//         final expiryDate = _tryParseTokenExpiry(tokenExpiryStr);
//         final now = DateTime.now();

//         final buffer = const Duration(minutes: 5);
//         if (expiryDate != null &&
//             (forceRefresh || now.isAfter(expiryDate.subtract(buffer)))) {
//           if (refreshToken != null) {
//             debugPrint(
//                 'GoogleDriveService: refresh token dipakai (source=${_lastSelectedTokenMeta?['source']}, email=${tokenData['google_email']})');
//             final newAccessToken = await _ref
//                 .read(authProvider.notifier)
//                 .refreshGoogleToken(refreshToken);
//             if (newAccessToken != null) {
//               accessToken = newAccessToken;

//               if (tokenId != null) {
//                 await _supabaseClient.from('google_account_tokens').update({
//                   'access_token': newAccessToken,
//                   'updated_at': DateTime.now().toIso8601String(),
//                   'token_expiry': DateTime.now()
//                       .add(const Duration(seconds: 3500))
//                       .toIso8601String(),
//                 }).eq('id', tokenId);
//               }
//             } else {
//               debugPrint('Failed to refresh Google Token');
//               return null;
//             }
//           } else {
//             debugPrint(
//               'GoogleDriveService: token dekat expired tapi refresh_token kosong '
//               '(source=${_lastSelectedTokenMeta?['source']}, email=${tokenData['google_email']}, expiry=$tokenExpiryStr)',
//             );
//             return null;
//           }
//         }
//         if (expiryDate != null && now.isAfter(expiryDate)) {
//           debugPrint(
//               'GoogleDriveService: token sudah expired (email=${tokenData['google_email']}, expiry=$tokenExpiryStr)');
//           return null;
//         }
//       } else if (forceRefresh && refreshToken != null) {
//         debugPrint(
//             'GoogleDriveService: forceRefresh tanpa expiry, coba refresh');
//         final newAccessToken = await _ref
//             .read(authProvider.notifier)
//             .refreshGoogleToken(refreshToken);
//         if (newAccessToken != null) {
//           accessToken = newAccessToken;
//           if (tokenId != null) {
//             await _supabaseClient.from('google_account_tokens').update({
//               'access_token': newAccessToken,
//               'updated_at': DateTime.now().toIso8601String(),
//               'token_expiry': DateTime.now()
//                   .add(const Duration(seconds: 3500))
//                   .toIso8601String(),
//             }).eq('id', tokenId);
//           }
//         } else {
//           return null;
//         }
//       }
//       return accessToken;
//     } catch (e) {
//       debugPrint('Error fetching Google Token: $e');
//       return null;
//     }
//   }

//   Future<Map<String, dynamic>> getDriveConnectionStatus() async {
//     Map<String, dynamic>? sharedToken;
//     Map<String, dynamic>? personalToken;

//     try {
//       sharedToken = await _supabaseClient
//           .from('google_account_tokens')
//           .select('google_email')
//           .eq('is_shared_company_account', true)
//           .order('updated_at', ascending: false)
//           .limit(1)
//           .maybeSingle();

//       sharedToken ??= await _supabaseClient
//           .from('google_account_tokens')
//           .select('google_email')
//           .eq('google_email', 'bps737273@gmail.com')
//           .limit(1)
//           .maybeSingle();
//     } catch (e) {
//       debugPrint('GoogleDriveService: gagal cek shared token: $e');
//     }

//     try {
//       final user = _supabaseClient.auth.currentUser;
//       if (user != null) {
//         final userData = await _supabaseClient
//             .from('users')
//             .select('id')
//             .eq('auth_uid', user.id)
//             .maybeSingle();

//         final internalUserId = userData?['id'] as String?;
//         if (internalUserId != null) {
//           personalToken = await _supabaseClient
//               .from('google_account_tokens')
//               .select('google_email')
//               .eq('user_id', internalUserId)
//               .or('is_shared_company_account.is.null,is_shared_company_account.eq.false')
//               .order('updated_at', ascending: false)
//               .limit(1)
//               .maybeSingle();
//         }
//       }
//     } catch (e) {
//       debugPrint('GoogleDriveService: gagal cek personal token: $e');
//     }

//     return {
//       'isSharedConnected': sharedToken != null,
//       'sharedEmail': sharedToken?['google_email'] as String?,
//       'isPersonalConnected': personalToken != null,
//       'personalEmail': personalToken?['google_email'] as String?,
//     };
//   }

//   Future<List<Map<String, dynamic>>> listFiles(String folderId) async {
//     String? token = await getAccessToken();
//     if (token == null) {
//       throw 'Token Google Drive kadaluarsa. Mohon hubungkan ulang akun Google Drive.';
//     }
//     _logOpTokenMeta('listFiles');

//     Future<http.Response> fetch(String t) {
//       final q = "'$folderId' in parents and trashed=false";
//       final uri = Uri.parse(
//           'https://www.googleapis.com/drive/v3/files?q=$q&fields=files(id, name, mimeType, webViewLink, iconLink, thumbnailLink, size, createdTime)&orderBy=createdTime desc');
//       return http.get(uri, headers: {'Authorization': 'Bearer $t'});
//     }

//     var response = await fetch(token);

//     if (response.statusCode == 401) {
//       token = await getAccessToken(forceRefresh: true);
//       if (token != null) {
//         response = await fetch(token);
//       }
//     }

//     if (response.statusCode == 403) {
//       final body = jsonDecode(response.body);
//       final error = body['error'];
//       final message = error?['message'] ?? 'Unknown error';

//       if (message.toString().contains('insufficient authentication scopes')) {
//         throw 'Izin kurang (Scope). Mohon hubungkan ulang akun Google dengan izin penuh.';
//       }

//       final errors = error?['errors'] as List?;
//       if (errors != null && errors.isNotEmpty) {
//         final reason = errors[0]['reason'];
//         if (reason == 'insufficientPermissions') {
//           throw 'Akses ditolak. Pastikan akun Google yang terhubung memiliki akses edit ke folder ini.';
//         }
//       }

//       throw 'Akses ditolak (403): $message';
//     }

//     if (response.statusCode == 200) {
//       final data = jsonDecode(response.body);
//       return List<Map<String, dynamic>>.from(data['files'] ?? []);
//     } else {
//       throw 'Gagal memuat file (${response.statusCode}): ${response.body}';
//     }
//   }

//   Future<Map<String, dynamic>> uploadFile(
//       String folderId, String fileName, Uint8List fileBytes) async {
//     String? token = await getAccessToken();
//     if (token == null) {
//       throw 'Token Google Drive kadaluarsa. Mohon hubungkan ulang akun Google Drive.';
//     }
//     _logOpTokenMeta('uploadFile');

//     Future<http.Response> performUpload(String t) async {
//       final uri = Uri.parse(
//           'https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id,webViewLink,thumbnailLink,name');
//       var request = http.MultipartRequest('POST', uri);
//       request.headers['Authorization'] = 'Bearer $t';

//       final metadata = jsonEncode({
//         'name': fileName,
//         'parents': [folderId]
//       });

//       request.files.add(http.MultipartFile.fromString(
//         'metadata',
//         metadata,
//         contentType: MediaType('application', 'json', {'charset': 'UTF-8'}),
//       ));

//       String extension = fileName.split('.').last.toLowerCase();
//       String mimeType = 'application/octet-stream';
//       if (extension == 'pdf') mimeType = 'application/pdf';
//       if (['jpg', 'jpeg'].contains(extension)) mimeType = 'image/jpeg';
//       if (extension == 'png') mimeType = 'image/png';

//       request.files.add(http.MultipartFile.fromBytes(
//         'file',
//         fileBytes,
//         filename: fileName,
//         contentType: MediaType.parse(mimeType),
//       ));

//       final streamedResponse = await request.send();
//       return await http.Response.fromStream(streamedResponse);
//     }

//     var response = await performUpload(token);

//     if (response.statusCode == 401) {
//       token = await getAccessToken(forceRefresh: true);
//       if (token != null) {
//         _logOpTokenMeta('uploadFile_retry');
//         response = await performUpload(token);
//       }
//     }

//     if (response.statusCode == 403) {
//       final body = jsonDecode(response.body);
//       final error = body['error'];
//       final message = error?['message'] ?? 'Unknown error';

//       if (message.toString().contains('insufficient authentication scopes')) {
//         throw 'Izin kurang (Scope). Mohon hubungkan ulang akun Google dengan izin penuh.';
//       }

//       final errors = error?['errors'] as List?;
//       if (errors != null && errors.isNotEmpty) {
//         final reason = errors[0]['reason'];
//         if (reason == 'insufficientPermissions') {
//           throw 'Akses ditolak. Pastikan akun Google yang terhubung memiliki akses edit ke folder ini.';
//         }
//       }

//       throw 'Akses ditolak (403): $message';
//     }

//     if (response.statusCode == 200) {
//       final data = jsonDecode(response.body);
//       final fileId = data['id'] as String?;
//       if (fileId != null) {
//         try {
//           await _makeFilePublic(fileId);
//         } catch (e) {
//           debugPrint('Drive: make public failed: $e');
//         }
//       }
//       return data;
//     } else {
//       throw 'Gagal upload (${response.statusCode}): ${response.body}';
//     }
//   }

//   Future<void> deleteFile(String fileId) async {
//     String? token = await getAccessToken();
//     if (token == null) {
//       throw 'Token Google Drive kadaluarsa. Mohon hubungkan ulang akun Google Drive.';
//     }
//     _logOpTokenMeta('deleteFile');

//     Future<http.Response> performDelete(String t) {
//       final uri =
//           Uri.parse('https://www.googleapis.com/drive/v3/files/$fileId');
//       return http.delete(uri, headers: {'Authorization': 'Bearer $t'});
//     }

//     var response = await performDelete(token);

//     if (response.statusCode == 401) {
//       token = await getAccessToken(forceRefresh: true);
//       if (token != null) {
//         response = await performDelete(token);
//       }
//     }

//     if (response.statusCode != 204 && response.statusCode != 200) {
//       throw 'Gagal menghapus file (${response.statusCode}): ${response.body}';
//     }
//   }

//   Future<String> createFolder(String parentId, String folderName) async {
//     String? token = await getAccessToken();
//     if (token == null) {
//       throw 'Token Google Drive kadaluarsa. Mohon hubungkan ulang akun Google Drive.';
//     }
//     _logOpTokenMeta('createFolder');

//     Future<http.Response> performCreate(String t) {
//       final uri = Uri.parse('https://www.googleapis.com/drive/v3/files');
//       final body = jsonEncode({
//         'name': folderName,
//         'mimeType': 'application/vnd.google-apps.folder',
//         'parents': [parentId]
//       });
//       return http.post(
//         uri,
//         headers: {
//           'Authorization': 'Bearer $t',
//           'Content-Type': 'application/json',
//         },
//         body: body,
//       );
//     }

//     var response = await performCreate(token);

//     if (response.statusCode == 401) {
//       token = await getAccessToken(forceRefresh: true);
//       if (token != null) {
//         response = await performCreate(token);
//       }
//     }

//     if (response.statusCode == 200) {
//       final data = jsonDecode(response.body);
//       return data['id'];
//     } else {
//       throw 'Gagal membuat folder (${response.statusCode}): ${response.body}';
//     }
//   }

//   Future<void> _makeFilePublic(String fileId) async {
//     String? token = await getAccessToken();
//     if (token == null) {
//       throw 'Token Google Drive kadaluarsa. Mohon hubungkan ulang akun Google Drive.';
//     }
//     _logOpTokenMeta('_makeFilePublic');
//     Future<http.Response> performSet(String t) {
//       final uri = Uri.parse(
//           'https://www.googleapis.com/drive/v3/files/$fileId/permissions');
//       final body = jsonEncode({'role': 'reader', 'type': 'anyone'});
//       return http.post(
//         uri,
//         headers: {
//           'Authorization': 'Bearer $t',
//           'Content-Type': 'application/json',
//         },
//         body: body,
//       );
//     }

//     var response = await performSet(token);
//     if (response.statusCode == 401) {
//       token = await getAccessToken(forceRefresh: true);
//       if (token != null) {
//         response = await performSet(token);
//       }
//     }
//     if (response.statusCode != 200 && response.statusCode != 201) {
//       throw 'Gagal set public (${response.statusCode}): ${response.body}';
//     }
//   }
// }
