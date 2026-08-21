# Contekan Run & Build dengan `--dart-define-from-file`

Gunakan perintah berikut agar tidak lupa saat menjalankan dan membangun aplikasi dengan file env JSON (`env/env.local.json`).

## Jalankan dengan file env

- Web: `flutter run -d chrome --dart-define-from-file=env/env.local.json`
- Android: `flutter run -d android --dart-define-from-file=env/env.local.json`
- iOS: `flutter run -d ios --dart-define-from-file=env/env.local.json`
- macOS: `flutter run -d macos --dart-define-from-file=env/env.local.json`

## Build rilis

- Web: `flutter build web --release --dart-define-from-file=env/env.local.json`
- Android: `flutter build apk --release --dart-define-from-file=env/env.local.json`
- iOS: `flutter build ios --release --dart-define-from-file=env/env.local.json`
- macOS: `./scripts/build_macos.sh` (setara `flutter build macos --release --dart-define-from-file=env/env.local.json` + membuat `.app` dan `.dmg` di `dist/macos/`)
- Windows (MSIX): `flutter build windows --release --dart-define-from-file=env/env.local.json` lalu `echo N | flutter pub run msix:create`

## Catatan

- Pastikan file `env/env.local.json` ada dan berisi semua kunci yang dibutuhkan (contoh tersedia di `env/env.example.json`).
- Untuk environment lain (mis. staging/production), buat file baru (mis. `env/env.staging.json`) dan ganti path pada perintah di atas.
- Android: pastikan device/emulator aktif dan terdeteksi (`flutter devices`).
- iOS: pastikan CocoaPods terpasang dan konfigurasi signing sudah sesuai project.
- Web: selain `chrome`, Anda bisa menggunakan device web lain yang tersedia pada mesin.
- Windows (MSIX): `echo N` digunakan untuk menolak install test certificate agar package siap untuk Windows Store submission.
- macOS: hasil build ada di `dist/macos/`. Seret `direktori.app` ke `/Applications` lalu buka lewat Launchpad — tidak perlu editor. Panduan lengkap (termasuk build dari Windows via GitHub Actions dan cara melewati peringatan Gatekeeper) ada di `BUILD_MACOS.md`.
- Windows: Jika ada error "Nuget.exe not found", Nuget.exe sudah tersedia di project directory (d:\flutter\direktori\nuget.exe).