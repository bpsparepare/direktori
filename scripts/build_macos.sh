#!/usr/bin/env bash
#
# Build aplikasi "direktori" untuk macOS menjadi .app siap pakai (dan .dmg).
#
# Pemakaian:
#   ./scripts/build_macos.sh                      # build + buat DMG
#   ./scripts/build_macos.sh --env-file env/env.staging.json
#   ./scripts/build_macos.sh --clean              # bersihkan dulu (build ulang total)
#   ./scripts/build_macos.sh --no-dmg             # cukup .app saja
#   ./scripts/build_macos.sh --open               # buka folder hasil build setelah selesai
#
# Hasil akhir ada di folder: dist/macos/
#
set -euo pipefail

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'; BLUE=$'\033[0;34m'; NC=$'\033[0m'
info()  { printf '%s==>%s %s\n' "$BLUE" "$NC" "$1"; }
ok()    { printf '%s✔%s  %s\n' "$GREEN" "$NC" "$1"; }
warn()  { printf '%s!%s  %s\n' "$YELLOW" "$NC" "$1"; }
die()   { printf '%sX%s  %s\n' "$RED" "$NC" "$1" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

ENV_FILE="env/env.local.json"
MAKE_DMG=1
DO_CLEAN=0
OPEN_RESULT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file) ENV_FILE="${2:-}"; [[ -n "$ENV_FILE" ]] || die "--env-file butuh path file."; shift 2 ;;
    --env-file=*) ENV_FILE="${1#*=}"; shift ;;
    --no-dmg) MAKE_DMG=0; shift ;;
    --dmg) MAKE_DMG=1; shift ;;
    --clean) DO_CLEAN=1; shift ;;
    --open) OPEN_RESULT=1; shift ;;
    -h|--help) awk 'NR>1 && /^#/ { sub(/^# ?/, ""); print; next } NR>1 { exit }' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) die "Opsi tidak dikenal: $1 (lihat --help)" ;;
  esac
done

# ---------------------------------------------------------------- prasyarat --
[[ "$(uname -s)" == "Darwin" ]] || die "Script ini hanya bisa dijalankan di macOS. Untuk build dari Windows/Linux, pakai GitHub Actions: .github/workflows/build-macos.yml"
command -v flutter >/dev/null 2>&1 || die "Flutter tidak ditemukan di PATH. Install dulu: https://docs.flutter.dev/get-started/install/macos"
command -v xcodebuild >/dev/null 2>&1 || die "Xcode belum terpasang. Install Xcode dari App Store, lalu jalankan: sudo xcodebuild -runFirstLaunch"

if [[ ! -f "assets/env" ]]; then
  die "File 'assets/env' tidak ada, padahal terdaftar di pubspec.yaml sehingga build akan gagal.
    Salin dari contoh lalu isi nilainya:  cp .env.example assets/env"
fi

DART_DEFINE_ARGS=()
if [[ -f "$ENV_FILE" ]]; then
  DART_DEFINE_ARGS+=("--dart-define-from-file=$ENV_FILE")
  info "Memakai env file: $ENV_FILE"
else
  warn "File env '$ENV_FILE' tidak ditemukan. Build tetap lanjut memakai fallback 'assets/env'."
  warn "Kalau ingin memakai dart-define, buat dulu: cp env/env.example.json $ENV_FILE"
fi

VERSION_RAW="$(grep -m1 '^version:' pubspec.yaml | awk '{print $2}')"
VERSION="${VERSION_RAW%%+*}"
info "Build direktori v${VERSION} untuk macOS ($(uname -m))"

# -------------------------------------------------------------------- build --
flutter config --enable-macos-desktop >/dev/null

if [[ "$DO_CLEAN" == "1" ]]; then
  info "flutter clean"
  flutter clean
fi

info "flutter pub get"
flutter pub get

info "flutter build macos --release"
flutter build macos --release "${DART_DEFINE_ARGS[@]}"

APP_PATH="$(find build/macos/Build/Products/Release -maxdepth 1 -name '*.app' -print -quit)"
[[ -n "$APP_PATH" ]] || die "Build selesai tapi file .app tidak ditemukan di build/macos/Build/Products/Release."
APP_NAME="$(basename "$APP_PATH")"
ok "Aplikasi terbentuk: $APP_PATH"

# ------------------------------------------------------------------ kemasan --
DIST_DIR="dist/macos"
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"
cp -R "$APP_PATH" "$DIST_DIR/"
# Buang atribut karantina supaya .app langsung bisa dibuka di Mac ini.
xattr -dr com.apple.quarantine "$DIST_DIR/$APP_NAME" 2>/dev/null || true
ok "Disalin ke: $DIST_DIR/$APP_NAME"

if [[ "$MAKE_DMG" == "1" ]]; then
  info "Membuat DMG"
  DMG_NAME="direktori-${VERSION}-macos-$(uname -m).dmg"
  STAGING="$(mktemp -d)"
  trap 'rm -rf "$STAGING"' EXIT
  cp -R "$DIST_DIR/$APP_NAME" "$STAGING/"
  ln -s /Applications "$STAGING/Applications"
  hdiutil create -volname "direktori ${VERSION}" \
    -srcfolder "$STAGING" -ov -format UDZO \
    "$DIST_DIR/$DMG_NAME" >/dev/null
  ok "DMG siap: $DIST_DIR/$DMG_NAME"
fi

echo
ok "Selesai."
cat <<EOT

Cara pakai tanpa editor:
  1. Buka Finder ke folder: $PROJECT_ROOT/$DIST_DIR
  2. Seret "$APP_NAME" ke folder /Applications (atau buka DMG lalu seret ke Applications).
  3. Buka lewat Launchpad / Spotlight seperti aplikasi biasa.

Kalau di Mac lain muncul peringatan "aplikasi tidak dapat dibuka karena
pengembang tidak dapat diverifikasi" (aplikasi ini belum ditandatangani
Apple Developer ID), jalankan sekali di Mac tersebut:
  xattr -dr com.apple.quarantine "/Applications/$APP_NAME"
atau klik kanan aplikasi > Open > Open.
EOT

if [[ "$OPEN_RESULT" == "1" ]]; then
  open "$DIST_DIR"
fi
