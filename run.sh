#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="Comic"
APP_BUNDLE="$SCRIPT_DIR/$APP_NAME.app"
BINARY_DIR="$SCRIPT_DIR/.build/debug"
SIGN_IDENTITY="Apple Development: pokkys@gmail.com (5TRPW6KZWL)"
ENTITLEMENTS="$SCRIPT_DIR/Comic-dev.entitlements"

swift build

pkill -x "$APP_NAME" 2>/dev/null || true
sleep 0.3

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BINARY_DIR/$APP_NAME"  "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$SCRIPT_DIR/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

if [ -f "$SCRIPT_DIR/Comic.icns" ]; then
    cp "$SCRIPT_DIR/Comic.icns" "$APP_BUNDLE/Contents/Resources/Comic.icns"
fi

chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

codesign --force --deep \
    --sign "$SIGN_IDENTITY" \
    --entitlements "$ENTITLEMENTS" \
    "$APP_BUNDLE" 2>/dev/null

xattr -cr "$APP_BUNDLE"

nohup "$APP_BUNDLE/Contents/MacOS/$APP_NAME" > /tmp/comic.log 2>&1 &
disown

echo "✓ Comic 已啟動 (log: /tmp/comic.log)"
