#!/usr/bin/env bash
set -euo pipefail

# Always packages a fresh build: delegates to build_app.sh (which reads ./VERSION),
# then wraps dist/MangaGlass.app into dist/MangaGlass.dmg.
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="MangaGlass"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/${APP_NAME}.app"
DMG_PATH="$DIST_DIR/${APP_NAME}.dmg"

"$ROOT_DIR/scripts/build_app.sh" "$@"

APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_DIR/Contents/Info.plist")"

echo "Packaging $DMG_PATH ($APP_VERSION)..."
rm -f "$DMG_PATH"
hdiutil create -volname "$APP_NAME $APP_VERSION" -srcfolder "$APP_DIR" -ov -format UDZO "$DMG_PATH" >/dev/null

echo "Done: $DMG_PATH ($APP_VERSION)"
