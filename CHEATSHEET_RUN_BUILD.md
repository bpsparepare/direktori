# Contekan Run & Build dengan `--dart-define-from-file`

Gunakan perintah berikut agar tidak lupa saat menjalankan dan membangun aplikasi dengan file env JSON (`env/env.local.json`).

## Jalankan dengan file env

- Web: `flutter run -d chrome --dart-define-from-file=env/env.local.json`
- Android: `flutter run -d android --dart-define-from-file=env/env.local.json`
- iOS: `flutter run -d ios --dart-define-from-file=env/env.local.json`
- Windows: `flutter run -d windows --dart-define-from-file=env/env.local.json`

## Build rilis

- Web: `flutter build web --release --dart-define-from-file=env/env.local.json`
- Android: `flutter build apk --release --dart-define-from-file=env/env.local.json`
- iOS: `flutter build ios --release --dart-define-from-file=env/env.local.json`
- Windows: `flutter build windows --release --dart-define-from-file=env/env.local.json`

## Windows Store (MSIX)

### Build MSIX untuk Microsoft Store
```bash
# Build Windows app (with environment variables)
flutter build windows --release --dart-define-from-file=env/env.local.json

# Create MSIX package
dart run msix:create

# Hasil: build/windows/x64/runner/Release/direktori.msix (14.7MB)
```

### Validasi MSIX sebelum upload
```bash
# Ekstrak dan cek isi MSIX
cd build/windows/x64/runner/Release
tar -xf direktori.msix

# Validasi kunci di AppxManifest.xml:
# - DisplayName: "direktori" ✅ (reserved name)
# - PublisherDisplayName: "Statistik Ceria" ✅ (Store account)
# - Identity Name: "StatistikCeria.direktori" ✅ (package identity)
# - Publisher: "CN=9EA411D5-DB62-4E3A-9282-478993AEB351" ✅ (Publisher ID)
```

### Konfigurasi MSIX (pubspec.yaml)
```yaml
msix_config:
  display_name: direktori                    # Nama reserved di Store
  publisher_display_name: Statistik Ceria    # Publisher name
  identity_name: StatistikCeria.direktori  # Package identity
  publisher: CN=9EA411D5-DB62-4E3A-9282-478993AEB351  # Publisher ID
  capabilities: internetClient               # Hanya capability yang dibutuhkan
  manifest_path: windows/AppxManifest.xml   # Custom manifest
  msix_version: 1.0.0.0                    # Version
  languages: id,en                         # Bahasa yang didukung
  architecture: x64                        # Target architecture
  output_name: direktori-store              # Nama file output
  store: true                              # Mode untuk Store submission
```

## Catatan Penting

### Environment Variables
- Pastikan file `env/env.local.json` ada dan berisi semua kunci yang dibutuhkan (contoh tersedia di `env/env.example.json`).
- Untuk environment lain (mis. staging/production), buat file baru (mis. `env/env.staging.json`) dan ganti path pada perintah di atas.

### Platform-specific Notes
- **Android**: pastikan device/emulator aktif dan terdeteksi (`flutter devices`).
- **iOS**: pastikan CocoaPods terpasang dan konfigurasi signing sudah sesuai project.
- **Web**: selain `chrome`, Anda bisa menggunakan device web lain yang tersedia pada mesin.
- **Windows**: jika ada error LNK1104, kill proses `direktori.exe` dengan `Stop-Process -Name direktori -Force`

### Windows Store Submission ✅ SIAP UPLOAD
1. Nama `direktori` sudah reserved di Partner Center ✅
2. PublisherDisplayName "Statistik Ceria" sudah sesuai akun Store ✅
3. MSIX 14.7MB siap upload ke Windows Store ✅
4. Tidak perlu certificate untuk Store submission (Microsoft akan sign otomatis) ✅
5. Package memenuhi semua requirement Store ✅

### Troubleshooting
- **Nuget.exe not found**: Normal, MSIX akan pakai cached version
- **Build gagal**: Coba `flutter clean` sebelum build ulang
- **Run gagal**: Kill proses yang sedang berjalan, lalu coba lagi