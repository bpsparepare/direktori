class AppVersion {
  // Update nilai ini setiap kali melakukan build/deploy ke produksi
  // Pastikan nilai ini sama dengan yang ada di web/version.json di server
  static const String version = '2.2.3';
  static const String buildNumber = '19';

  static String get fullVersion => '$version+$buildNumber';
}
