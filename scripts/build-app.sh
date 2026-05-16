#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="AgentsBar"
APP_DIR="${ROOT}/${APP_NAME}.app"
BUILD_DIR="${ROOT}/.build/release"
BINARY="${BUILD_DIR}/${APP_NAME}"
BUNDLE_ID="app.agentsbar"
ICON_FILE="Sources/AgentsBar/Resources/codex-icon.icns"
ICON_PLIST_ENTRY=""

cd "$ROOT"
swift build -c release
BUILD_DIR="$(cd "$BUILD_DIR" && pwd -P)"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BINARY" "$APP_DIR/Contents/MacOS/${APP_NAME}"

RESOURCE_BUNDLE="$(find "$BUILD_DIR" -maxdepth 1 -name "${APP_NAME}_${APP_NAME}.bundle" -type d -print -quit)"
if [ -n "${RESOURCE_BUNDLE:-}" ]; then
  cp -R "$RESOURCE_BUNDLE" "$APP_DIR/Contents/Resources/"
fi

if [ -f "$ICON_FILE" ]; then
  cp "$ICON_FILE" "$APP_DIR/Contents/Resources/codex-icon.icns"
  ICON_PLIST_ENTRY=$'  <key>CFBundleIconFile</key>\n  <string>codex-icon</string>'
fi

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>${APP_NAME}</string>
${ICON_PLIST_ENTRY}
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_ID}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
PLIST

echo "$APP_DIR"
