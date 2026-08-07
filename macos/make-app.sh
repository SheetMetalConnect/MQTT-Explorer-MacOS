#!/bin/zsh
# Build a release binary and assemble MQTT Explorer.app.
# Usage: ./make-app.sh
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="MQTT Explorer"
BUNDLE_ID="com.sheetmetalconnect.mqttexplorer"
VERSION="1.0.0"
BUILD_DIR="build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"

echo "==> swift build (release, arm64)"
swift build -c release --arch arm64

BIN="$(swift build -c release --arch arm64 --show-bin-path)/MQTTExplorer"

echo "==> assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"
cp ../res/icon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"

echo "==> ad-hoc codesign"
codesign --force --sign - "$APP_DIR"

echo "Done: $(pwd)/$APP_DIR"
