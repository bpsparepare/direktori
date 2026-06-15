import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/config/supabase_config.dart';
import '../../../../core/services/google_drive_service.dart';
import '../../../../core/services/storage/storage_interface.dart';
import '../../../../core/services/storage/storage_service.dart';

class DocumentationEntry {
  final String id;
  final String fileName;
  final String localPath;
  final String driveFileId;
  final String driveViewUrl;
  final String previewUrl;
  final String category;
  final String description;
  final String uploadedAt;
  final int fileSize;

  const DocumentationEntry({
    required this.id,
    required this.fileName,
    required this.localPath,
    required this.driveFileId,
    required this.driveViewUrl,
    required this.previewUrl,
    required this.category,
    required this.description,
    required this.uploadedAt,
    required this.fileSize,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'file_name': fileName,
      'local_path': localPath,
      'drive_file_id': driveFileId,
      'drive_view_url': driveViewUrl,
      'preview_url': previewUrl,
      'category': category,
      'description': description,
      'uploaded_at': uploadedAt,
      'file_size': fileSize,
    };
  }

  factory DocumentationEntry.fromJson(Map<String, dynamic> json) {
    return DocumentationEntry(
      id: (json['id'] ?? '').toString(),
      fileName: (json['file_name'] ?? '').toString(),
      localPath: (json['local_path'] ?? '').toString(),
      driveFileId: (json['drive_file_id'] ?? '').toString(),
      driveViewUrl: (json['drive_view_url'] ?? '').toString(),
      previewUrl: (json['preview_url'] ?? '').toString(),
      category: (json['category'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      uploadedAt: (json['uploaded_at'] ?? '').toString(),
      fileSize: (json['file_size'] as num?)?.toInt() ?? 0,
    );
  }
}

class DocumentationUploadService {
  static const String _storagePrefix = 'documentation_uploads_v1';
  static const String _driveFolderId = '1lOWg2mW4px6VsWuBE2if1o4LLYZfggAk';

  final SupabaseClient _client = SupabaseConfig.client;
  final GoogleDriveService _driveService = GoogleDriveService();
  final StorageService _storage = StorageServiceFactory.create();
  final Uuid _uuid = const Uuid();

  Future<List<DocumentationEntry>> loadEntries() async {
    try {
      final key = await _storageKey();
      final raw = await _storage.read(key);
      if (raw == null || raw.isEmpty) return [];

      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];

      return decoded
          .whereType<Map<String, dynamic>>()
          .map(DocumentationEntry.fromJson)
          .toList()
        ..sort((a, b) => b.uploadedAt.compareTo(a.uploadedAt));
    } catch (_) {
      return [];
    }
  }

  Future<DocumentationEntry> uploadDocumentation(
    File pickedFile, {
    String? originalName,
    required String category,
    String? description,
  }) async {
    final context = await _resolveContext();
    final fileBytes = Uint8List.fromList(await pickedFile.readAsBytes());
    final extension = _inferExtension(
      pickedFile.path,
      originalName: originalName,
    );
    final fileName = _buildFileName(context.displayName, extension);
    final targetFolderId = await _driveService.ensureFolderInParent(
      _driveFolderId,
      _folderNameForCategory(category),
    );
    final uploadResult = await _driveService.uploadFile(
      targetFolderId,
      fileName,
      fileBytes,
    );
    final uploadedAt = DateTime.now().toIso8601String();
    final driveFileId = (uploadResult['id'] ?? '').toString();
    final driveViewUrl = (uploadResult['webViewLink'] ?? '').toString();
    final previewUrl =
        (uploadResult['thumbnailLink'] ??
                uploadResult['webContentLink'] ??
                uploadResult['webViewLink'] ??
                '')
            .toString();

    await _saveUploadMetadata(
      userId: context.userKey,
      fileName: fileName,
      category: category,
      description: description,
      driveViewUrl: driveViewUrl,
      uploadedAt: uploadedAt,
    );

    final localFile = await _persistLocalFile(
      userKey: context.userKey,
      fileName: fileName,
      bytes: fileBytes,
    );

    final entry = DocumentationEntry(
      id: _uuid.v4(),
      fileName: fileName,
      localPath: localFile.path,
      driveFileId: driveFileId,
      driveViewUrl: driveViewUrl,
      previewUrl: previewUrl,
      category: category,
      description: description?.trim() ?? '',
      uploadedAt: uploadedAt,
      fileSize: await localFile.length(),
    );

    final entries = await loadEntries();
    entries.insert(0, entry);
    await _saveEntries(entries);
    return entry;
  }

  Future<void> deleteLocalEntry(DocumentationEntry entry) async {
    final entries = await loadEntries();
    entries.removeWhere((item) => item.id == entry.id);
    await _saveEntries(entries);

    try {
      final file = File(entry.localPath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  Future<void> _saveUploadMetadata({
    required String userId,
    required String fileName,
    required String category,
    required String driveViewUrl,
    required String uploadedAt,
    String? description,
  }) async {
    await _client.from('documentation_uploads').insert({
      'user_id': userId,
      'kategori': category,
      'keterangan': _normalizeDescription(description),
      'link_file': driveViewUrl,
      'nama_file': fileName,
      'created_at': uploadedAt,
    });
  }

  Future<_DocumentationContext> _resolveContext() async {
    final authUser = _client.auth.currentUser;
    if (authUser == null) {
      throw Exception('Sesi login tidak ditemukan');
    }

    String userKey = authUser.id;
    String? displayName;

    try {
      final appUser = await _client
          .from('users')
          .select('id, name, email')
          .eq('auth_uid', authUser.id)
          .maybeSingle();

      if (appUser != null) {
        final appUserId = appUser['id']?.toString();
        if (appUserId != null && appUserId.isNotEmpty) {
          userKey = appUserId;
        }
        displayName = appUser['name']?.toString();
        displayName ??= appUser['email']?.toString().split('@').first;
      }
    } catch (_) {
      displayName = authUser.email?.split('@').first;
    }

    displayName ??=
        authUser.userMetadata?['name']?.toString() ??
        authUser.email?.split('@').first ??
        'dokumentasi';

    return _DocumentationContext(userKey: userKey, displayName: displayName);
  }

  Future<File> _persistLocalFile({
    required String userKey,
    required String fileName,
    required List<int> bytes,
  }) async {
    final baseDir = await getApplicationDocumentsDirectory();
    final targetDir = Directory(
      '${baseDir.path}/documentation_uploads/$userKey',
    );
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    final file = File('${targetDir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<void> _saveEntries(List<DocumentationEntry> entries) async {
    final key = await _storageKey();
    await _storage.write(
      key,
      jsonEncode(entries.map((entry) => entry.toJson()).toList()),
    );
  }

  Future<String> _storageKey() async {
    final context = await _resolveContext();
    return '${_storagePrefix}_${context.userKey}.json';
  }

  String _buildFileName(String displayName, String extension) {
    final sanitizedName = displayName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    final now = DateTime.now();
    final timestamp =
        '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';
    final safeName = sanitizedName.isEmpty ? 'dokumentasi' : sanitizedName;
    return '${safeName}_$timestamp.$extension';
  }

  String _inferExtension(String path, {String? originalName}) {
    final raw = (originalName?.isNotEmpty == true ? originalName! : path)
        .toLowerCase();
    if (raw.endsWith('.jpeg')) return 'jpeg';
    if (raw.endsWith('.png')) return 'png';
    if (raw.endsWith('.webp')) return 'webp';
    if (raw.endsWith('.heic')) return 'heic';
    return 'jpg';
  }

  String? _normalizeDescription(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  String _folderNameForCategory(String value) {
    final normalized = value.trim().toLowerCase();
    switch (normalized) {
      case 'koordinasi':
        return 'Koordinasi';
      case 'pendataan':
        return 'Pendataan';
      case 'pengawasan':
        return 'Pengawasan';
      case 'pertemuan':
        return 'Pertemuan';
      case 'bukti paket data':
        return 'Bukti Paket Data';
      case 'lainnya':
        return 'Lainnya';
    }
    return 'Lainnya';
  }
}

class _DocumentationContext {
  final String userKey;
  final String displayName;

  const _DocumentationContext({
    required this.userKey,
    required this.displayName,
  });
}
