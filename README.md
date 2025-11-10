# direktori

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Environment Configuration (dart-define-from-file)

Konfigurasi environment sekarang dibaca dari nilai yang diinject saat build menggunakan `--dart-define-from-file`. Contoh format tersedia di `env/env.example.json`.

1) Duplikasi contoh dan sesuaikan:

```
cp env/env.example.json env/env.local.json
# Edit sesuai kebutuhan
```

2) Jalankan aplikasi dengan file env:

- Web dev:
```
flutter run -d chrome --dart-define-from-file=env/env.local.json
```

- Android dev:
```
flutter run -d android --dart-define-from-file=env/env.local.json
```

- iOS dev:
```
flutter run -d ios --dart-define-from-file=env/env.local.json
```

3) Build release dengan file env:

- Web:
```
flutter build web --release --dart-define-from-file=env/env.local.json
```

- Android:
```
flutter build apk --release --dart-define-from-file=env/env.local.json
flutter build apk --release --split-per-abi --dart-define-from-file=env/env.local.json
```

- iOS:
```
flutter build ios --release --dart-define-from-file=env/env.local.json
```

Catatan keamanan:
- Nilai yang diinject akan dibundel ke artefak aplikasi (biner/JS). Jangan taruh rahasia server (admin key, private API keys) di sini.
- Aman untuk nilai publik seperti `SUPABASE_URL`, `SUPABASE_ANON_KEY`, dan base URL Upload API.
