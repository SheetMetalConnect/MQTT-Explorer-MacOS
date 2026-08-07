#!/bin/zsh
# Build the app (if needed) and package a drag-to-Applications DMG.
# Usage: ./make-dmg.sh
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="MQTT Explorer"
VERSION="1.3.0"
APP_DIR="build/$APP_NAME.app"
DMG="build/$APP_NAME-$VERSION.dmg"
STAGING="build/dmg-staging"

if [ ! -d "$APP_DIR" ]; then
    ./make-app.sh
fi

echo "==> staging $STAGING"
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP_DIR" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

echo "==> creating $DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
rm -rf "$STAGING"

echo "Done: $(pwd)/$DMG"
