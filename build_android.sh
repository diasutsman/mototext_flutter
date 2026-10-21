#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

if ! command -v flutter >/dev/null 2>&1; then
  echo "ERROR: Flutter SDK tidak ditemukan. Install Flutter lalu jalankan script ini lagi." >&2
  exit 1
fi

if [ ! -d "android" ] || [ "${1:-}" = "--recreate" ]; then
  echo "Menginisialisasi platform Android..."
  BACKUP="$(mktemp -d)"
  cleanup() { rm -rf "$BACKUP"; }
  trap cleanup EXIT
  cp lib/main.dart "$BACKUP/main.dart"
  cp pubspec.yaml "$BACKUP/pubspec.yaml"
  if [ -d "test" ]; then cp -r test "$BACKUP/test"; fi

  flutter create --platforms=android --project-name mototext_wifi --overwrite .

  cp "$BACKUP/main.dart" lib/main.dart
  cp "$BACKUP/pubspec.yaml" pubspec.yaml
  if [ -d "$BACKUP/test" ]; then rm -rf test && cp -r "$BACKUP/test" test; fi

  python3 - <<'PY'
from pathlib import Path
import re
manifest = Path('android/app/src/main/AndroidManifest.xml')
if manifest.exists():
    text = manifest.read_text()
    if 'android.permission.INTERNET' not in text:
        text = re.sub(r'(<manifest\b[^>]*>)', r'\1\n    <uses-permission android:name="android.permission.INTERNET" />', text, count=1)
    if 'usesCleartextTraffic' not in text:
        text = text.replace('<application', '<application android:usesCleartextTraffic="true"', 1)
    manifest.write_text(text)
PY
fi

flutter pub get
flutter analyze
flutter build apk --debug
printf '\nAPK berhasil dibuat di:\n%s\n' "$ROOT/build/app/outputs/flutter-apk/app-debug.apk"
