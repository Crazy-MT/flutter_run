#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FLUTTER="$ROOT/.fvm/flutter_sdk/bin/flutter"
APP_NAME="Flutter Run"
APP_PATH="$ROOT/build/macos/Build/Products/Release/flutter_run.app"
DIST="$ROOT/dist"
VERSION="$(sed -n 's/^version: \([^+ ]*\).*/\1/p' "$ROOT/pubspec.yaml")"

if [[ ! -x "$FLUTTER" ]]; then
  echo "Flutter SDK not found at $FLUTTER. Run 'fvm install' in $ROOT first." >&2
  exit 1
fi

cd "$ROOT"
"$FLUTTER" pub get
"$FLUTTER" build macos --release

if [[ ! -d "$APP_PATH" ]]; then
  echo "Build completed but app bundle is missing: $APP_PATH" >&2
  exit 1
fi

mkdir -p "$DIST"
DMG="$DIST/Flutter-Run-$VERSION-macOS.dmg"
rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$APP_PATH" -ov -format UDZO "$DMG"

if [[ ! -w /Applications ]]; then
  echo "Cannot install into /Applications; rerun with permission to write there." >&2
  exit 1
fi

ditto "$APP_PATH" "/Applications/$APP_NAME.app"
echo "Installed: /Applications/$APP_NAME.app"
echo "Installer: $DMG"
