class AppVersion {
  // Update nilai ini setiap kali melakukan build/deploy ke produksi
  // Pastikan nilai ini sama dengan yang ada di web/version.json di server
  static const String version = '2.1.1';
  static const String buildNumber = '14';

  static String get fullVersion => '$version+$buildNumber';
}
