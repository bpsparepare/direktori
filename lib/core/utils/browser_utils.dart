import 'browser_utils_stub.dart'
    if (dart.library.html) 'browser_utils_web.dart';

class BrowserUtils {
  static void reload() {
    reloadPage();
  }
}
