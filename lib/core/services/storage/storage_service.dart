import 'storage_interface.dart';
import 'storage_service_io.dart'
    if (dart.library.html) 'storage_service_web.dart'
    as impl;

class StorageServiceFactory {
  static StorageService create() {
    return impl.createStorageService();
  }
}
