#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DISPLAY_NAME="Agent Sessions"
EXECUTABLE_NAME="AgentSessions"
INSTALL_DIR="${AGENT_SESSIONS_INSTALL_DIR:-/Applications}"
APP_DIR="${INSTALL_DIR}/${APP_DISPLAY_NAME}.app"
BUILD_DIR="${ROOT}/.build/release"
BINARY="${BUILD_DIR}/${EXECUTABLE_NAME}"
BUNDLE_ID="app.agentsessions"

cd "$ROOT"
swift build -c release
BUILD_DIR="$(cd "$BUILD_DIR" && pwd -P)"

# Assemble on local disk before installing: the checkout lives on Google
# Drive, and login items launched at boot must not depend on the Drive
# volume being mounted.
STAGING_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGING_DIR"' EXIT
STAGE_APP="${STAGING_DIR}/${APP_DISPLAY_NAME}.app"

mkdir -p "$STAGE_APP/Contents/MacOS" "$STAGE_APP/Contents/Resources"

cp "$BINARY" "$STAGE_APP/Contents/MacOS/${EXECUTABLE_NAME}"

RESOURCE_BUNDLE="$(find "$BUILD_DIR" -maxdepth 1 -name "${EXECUTABLE_NAME}_${EXECUTABLE_NAME}.bundle" -type d -print -quit)"
if [ -n "${RESOURCE_BUNDLE:-}" ]; then
  cp -R "$RESOURCE_BUNDLE" "$STAGE_APP/Contents/Resources/"
fi

cat > "$STAGE_APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>${EXECUTABLE_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_ID}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${APP_DISPLAY_NAME}</string>
  <key>CFBundleDisplayName</key>
  <string>${APP_DISPLAY_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>26.0</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
PLIST

# Ad-hoc sign the assembled bundle. The linker-signed binary alone leaves the
# bundle without a resource seal, which SMAppService rejects when registering
# the login item. Files copied out of the Drive-backed checkout can carry
# extended attributes codesign treats as detritus, so strip them first.
xattr -rc "$STAGE_APP"
codesign --force --sign - "$STAGE_APP"

rm -rf "$APP_DIR"
ditto "$STAGE_APP" "$APP_DIR"
codesign --verify --strict "$APP_DIR"

echo "$APP_DIR"
