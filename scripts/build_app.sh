#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="MangaGlass"
APP_VERSION="1.3.1"
TMP_BASE="${TMPDIR:-/tmp}"
TMP_BASE="${TMP_BASE%/}"
BUILD_ROOT="${MANGAGLASS_BUILD_ROOT:-$TMP_BASE/${APP_NAME}-swiftpm-build}"
BUILD_DIR="$BUILD_ROOT/release"
MODULE_CACHE_DIR="$BUILD_ROOT/module-cache"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/${APP_NAME}.app"
BIN_PATH="$BUILD_DIR/$APP_NAME"
ICON_PATH="$ROOT_DIR/assets/AppIcon.icns"
INSTALL_DIR="/Applications"
DO_INSTALL=0
DO_OPEN=0

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Builds $APP_NAME.app into:
  $APP_DIR

Options:
  --install           Copy the built app to /Applications
  --install-dir DIR   Copy the built app to DIR when used with --install
  --open              Open the installed app, or the built app if not installed
  -h, --help          Show this help message

Examples:
  scripts/build_app.sh
  scripts/build_app.sh --install
  scripts/build_app.sh --install --open
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --install)
            DO_INSTALL=1
            shift
            ;;
        --install-dir)
            if [[ $# -lt 2 || -z "${2:-}" ]]; then
                echo "Error: --install-dir requires a directory path." >&2
                exit 2
            fi
            INSTALL_DIR="$2"
            shift 2
            ;;
        --open)
            DO_OPEN=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Error: unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [[ ! -x "$(command -v swift)" ]]; then
    echo "Error: swift was not found in PATH." >&2
    exit 1
fi

if [[ ! -f "$ICON_PATH" ]]; then
    echo "Error: app icon not found at $ICON_PATH" >&2
    exit 1
fi

mkdir -p "$DIST_DIR" "$MODULE_CACHE_DIR"

echo "Building $APP_NAME release binary..."
CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR" \
SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE_DIR" \
    swift build -c release --package-path "$ROOT_DIR" --build-path "$BUILD_ROOT"

echo "Assembling $APP_DIR..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$ICON_PATH" "$APP_DIR/Contents/Resources/AppIcon.icns"

# SwiftPM resources are emitted as *.bundle next to the built binary.
# Bundle.module in app context resolves these bundles from the app root.
shopt -s nullglob
for bundle in "$BUILD_DIR"/*.bundle; do
    cp -R "$bundle" "$APP_DIR/"
done
shopt -u nullglob

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.codex.$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$APP_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$APP_VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

echo "Built: $APP_DIR"

OPEN_PATH="$APP_DIR"
if [[ "$DO_INSTALL" -eq 1 ]]; then
    INSTALL_APP="$INSTALL_DIR/${APP_NAME}.app"
    echo "Installing to $INSTALL_APP..."
    mkdir -p "$INSTALL_DIR"
    rm -rf "$INSTALL_APP"
    ditto "$APP_DIR" "$INSTALL_APP"
    OPEN_PATH="$INSTALL_APP"
    echo "Installed: $INSTALL_APP"
fi

if [[ "$DO_OPEN" -eq 1 ]]; then
    echo "Opening $OPEN_PATH..."
    open "$OPEN_PATH"
fi
