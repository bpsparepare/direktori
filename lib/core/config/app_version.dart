class AppVersion {
  // Update nilai ini setiap kali melakukan build/deploy ke produksi
  // Pastikan nilai ini sama dengan yang ada di web/version.json di server
  static const String version = '1.2.2';
  static const String buildNumber = '8';

  static String get fullVersion => '$version+$buildNumber';
}
