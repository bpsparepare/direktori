import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'storage_interface.dart';

StorageService createStorageService() => StorageServiceIo();

class StorageServiceIo implements StorageService {
  Future<File> _getFile(String filename) async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$filename');
  }

  @override
  Future<String?> read(String key) async {
    try {
      final file = await _getFile(key);
      if (!await file.exists()) return null;
      return await file.readAsString();
    } catch (e) {
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) async {
    try {
      final file = await _getFile(key);
      await file.writeAsString(value);
    } catch (e) {
      // Ignore error
    }
  }

  @override
  Future<void> delete(String key) async {
    try {
      final file = await _getFile(key);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      // Ignore error
    }
  }
}
