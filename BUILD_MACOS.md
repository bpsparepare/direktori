# Build Aplikasi macOS (.app / .dmg)

Panduan membuat aplikasi **direktori** untuk macOS supaya bisa dibuka langsung
lewat Launchpad/Finder, tanpa perlu menjalankan `flutter run` dari VS Code atau
Android Studio.

Ada dua cara: **build di Mac** (paling cepat) atau **build lewat GitHub Actions**
(kalau komputer kerja Anda Windows dan tidak punya Mac untuk build).

---

## A. Build langsung di Mac

### 1. Prasyarat (sekali saja)

| Kebutuhan | Cara |
| --- | --- |
| Xcode | Install dari App Store, lalu `sudo xcodebuild -runFirstLaunch` |
| Command line tools | `sudo xcode-select --install` |
| CocoaPods | `sudo gem install cocoapods` (atau `brew install cocoapods`) |
| Flutter | https://docs.flutter.dev/get-started/install/macos |

Cek semuanya siap:

```bash
flutter doctor
```

Pastikan baris **Xcode** dan **macOS toolchain** sudah bercentang hijau.

### 2. Siapkan file environment

```bash
cp env/env.example.json env/env.local.json   # lalu isi nilainya
cp .env.example assets/env                   # lalu isi nilainya
```

Dua-duanya diperlukan:

- `env/env.local.json` → diinject saat build lewat `--dart-define-from-file`.
- `assets/env` → terdaftar sebagai asset di `pubspec.yaml`, jadi **build gagal
  kalau file ini tidak ada**. Isinya juga dipakai sebagai fallback runtime.

### 3. Build

```bash
./scripts/build_macos.sh
```

Script ini menjalankan `flutter pub get`, `flutter build macos --release`,
menyalin hasilnya ke `dist/macos/`, dan membungkusnya jadi file `.dmg`.

Opsi yang tersedia:

```bash
./scripts/build_macos.sh --env-file env/env.staging.json   # pakai env lain
./scripts/build_macos.sh --clean                           # build ulang dari nol
./scripts/build_macos.sh --no-dmg                          # cukup .app saja
./scripts/build_macos.sh --open                            # buka folder hasil build
```

Kalau ingin manual tanpa script:

```bash
flutter build macos --release --dart-define-from-file=env/env.local.json
open build/macos/Build/Products/Release
```

### 4. Pasang dan buka

1. Buka folder `dist/macos/`.
2. Seret **direktori.app** ke folder `/Applications`
   (atau buka file `.dmg`, lalu seret ikonnya ke pintasan Applications).
3. Buka lewat Launchpad atau Spotlight (⌘ + Space, ketik "direktori").

Setelah ini aplikasi berjalan mandiri — editor tidak perlu dibuka lagi.

---

## B. Build lewat GitHub Actions (tanpa Mac)

Workflow `.github/workflows/build-macos.yml` mem-build aplikasi di runner macOS
milik GitHub, lalu menyediakan file `.dmg` untuk diunduh.

### 1. Isi secrets (sekali saja)

Di GitHub: **Settings → Secrets and variables → Actions → New repository secret**

| Nama secret | Wajib | Keterangan |
| --- | --- | --- |
| `SUPABASE_URL` | ya | URL project Supabase |
| `SUPABASE_ANON_KEY` | ya | Anon key Supabase |
| `GOOGLE_CLIENT_ID` | tidak | Untuk Google Sign-In |
| `UPLOAD_API_BASE_URL` | tidak | Default `https://api.parepare.stat7300.net` |
| `UPLOAD_API_UPLOAD_PATH` | tidak | Default `/upload` |

### 2. Jalankan

- Manual: tab **Actions → Build macOS → Run workflow**, atau
- Otomatis: setiap kali push tag versi baru (`v3.1.5`, dst).

### 3. Unduh

Buka halaman run yang sudah selesai → bagian **Artifacts** → unduh
`direktori-macos`. Di dalamnya ada file `.dmg`.

Karena file diunduh dari internet, macOS akan menandainya karantina — ikuti
langkah pada bagian *Gatekeeper* di bawah saat pertama kali membuka.

---

## Gatekeeper: "aplikasi tidak dapat dibuka karena pengembang tidak dapat diverifikasi"

Aplikasi ini di-build tanpa sertifikat **Apple Developer ID** (berbayar
$99/tahun), jadi macOS akan menahannya saat pertama dibuka. Ini normal dan
hanya perlu ditangani sekali per Mac:

**Cara 1 — lewat Finder**
Klik kanan ikon aplikasi → **Open** → pada dialog yang muncul, klik **Open**
lagi.

**Cara 2 — lewat Terminal**

```bash
xattr -dr com.apple.quarantine "/Applications/direktori.app"
```

**Cara 3 — lewat System Settings**
Buka aplikasi seperti biasa (akan ditolak), lalu ke **System Settings →
Privacy & Security**, cari pesan tentang "direktori" dan klik **Open Anyway**.

Kalau nanti sudah punya akun Apple Developer, aplikasi bisa di-*sign* dan
di-*notarize* supaya langsung terbuka tanpa langkah di atas.

---

## Izin sistem yang diminta aplikasi

Konfigurasi sandbox macOS (`macos/Runner/*.entitlements`) sudah mencakup:

| Izin | Dipakai untuk |
| --- | --- |
| Network client | Supabase, peta, Upload API |
| Lokasi | Menampilkan posisi di peta |
| Mikrofon | Pencarian dengan suara (`speech_to_text`) |
| Kamera | Ambil foto dokumentasi |
| File pilihan pengguna (baca/tulis) | Impor & ekspor file |
| Folder Downloads (baca/tulis) | Menyimpan hasil ekspor Excel |

macOS akan menampilkan dialog izin saat fitur terkait pertama kali dipakai.
Kalau izin pernah ditolak, ubah lewat **System Settings → Privacy & Security**.

---

## Troubleshooting

| Masalah | Solusi |
| --- | --- |
| `Unable to find asset` / build gagal soal `assets/env` | File `assets/env` belum dibuat — `cp .env.example assets/env` |
| `CocoaPods not installed` | `sudo gem install cocoapods` lalu ulangi build |
| Build gagal setelah ganti dependency | `./scripts/build_macos.sh --clean` |
| Pod error aneh | `cd macos && pod repo update && pod install` |
| Aplikasi terbuka tapi gagal login | Nilai `SUPABASE_URL` / `SUPABASE_ANON_KEY` salah atau kosong saat build |
| `flutter build macos` tidak dikenal | `flutter config --enable-macos-desktop` |

Minimum macOS yang didukung: **11.0 (Big Sur)** — lihat `macos/Podfile`.
