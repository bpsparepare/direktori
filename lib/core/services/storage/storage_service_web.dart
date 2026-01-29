import 'dart:async';
import 'dart:html' as html;
// import 'dart:indexed_db' as idb; // Removed to avoid error if unavailable
import 'storage_interface.dart';

StorageService createStorageService() => StorageServiceWeb();

class StorageServiceWeb implements StorageService {
  static const String _dbName = 'direktori_app_db';
  static const String _storeName = 'key_value_store';
  static const int _version = 1;

  // Use dynamic to avoid type errors
  dynamic _db;

  Future<void> _init() async {
    if (_db != null) return;

    if (html.window.indexedDB == null) {
      throw UnsupportedError('IndexedDB not supported');
    }

    _db = await html.window.indexedDB!.open(
      _dbName,
      version: _version,
      onUpgradeNeeded: (e) {
        // e is VersionChangeEvent, but we treat everything as dynamic to avoid missing type errors
        final request = (e as dynamic).target;
        final db = request.result;

        // We use dynamic access to avoid strict type checks
        if (!(db as dynamic).objectStoreNames.contains(_storeName)) {
          (db as dynamic).createObjectStore(_storeName);
        }
      },
    );
  }

  @override
  Future<String?> read(String key) async {
    try {
      await _init();
      final transaction = (_db as dynamic).transaction(_storeName, 'readonly');
      final store = transaction.objectStore(_storeName);
      final result = await store.getObject(key);
      return result as String?;
    } catch (e) {
      print('IndexedDB read error: $e');
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) async {
    try {
      await _init();
      final transaction = (_db as dynamic).transaction(_storeName, 'readwrite');
      final store = transaction.objectStore(_storeName);
      await store.put(value, key);
      await transaction.completed;
    } catch (e) {
      print('IndexedDB write error: $e');
    }
  }

  @override
  Future<void> delete(String key) async {
    try {
      await _init();
      final transaction = (_db as dynamic).transaction(_storeName, 'readwrite');
      final store = transaction.objectStore(_storeName);
      await store.delete(key);
      await transaction.completed;
    } catch (e) {
      print('IndexedDB delete error: $e');
    }
  }
}
