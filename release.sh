#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="Comic"
APP_BUNDLE="$SCRIPT_DIR/$APP_NAME.app"
BINARY_DIR="$SCRIPT_DIR/.build/arm64-apple-macosx/release"
SIGN_IDENTITY="Apple Development: pokkys@gmail.com (5TRPW6KZWL)"
ENTITLEMENTS="$SCRIPT_DIR/Comic-dev.entitlements"

echo "==> 清除舊的 app bundle"
rm -rf "$APP_BUNDLE"

echo "==> 產生圖示"
if [ ! -f "$SCRIPT_DIR/Comic.icns" ] || [ "$SCRIPT_DIR/icon.svg" -nt "$SCRIPT_DIR/Comic.icns" ]; then
    qlmanage -t -s 1024 -o /tmp/ "$SCRIPT_DIR/icon.svg" 2>/dev/null
    cp /tmp/icon.svg.png "$SCRIPT_DIR/icon_1024.png"
    mkdir -p "$SCRIPT_DIR/icon.iconset"
    sips -z 16   16   icon_1024.png --out icon.iconset/icon_16x16.png      2>/dev/null
    sips -z 32   32   icon_1024.png --out icon.iconset/icon_16x16@2x.png   2>/dev/null
    sips -z 32   32   icon_1024.png --out icon.iconset/icon_32x32.png      2>/dev/null
    sips -z 64   64   icon_1024.png --out icon.iconset/icon_32x32@2x.png   2>/dev/null
    sips -z 128  128  icon_1024.png --out icon.iconset/icon_128x128.png    2>/dev/null
    sips -z 256  256  icon_1024.png --out icon.iconset/icon_128x128@2x.png 2>/dev/null
    sips -z 256  256  icon_1024.png --out icon.iconset/icon_256x256.png    2>/dev/null
    sips -z 512  512  icon_1024.png --out icon.iconset/icon_256x256@2x.png 2>/dev/null
    sips -z 512  512  icon_1024.png --out icon.iconset/icon_512x512.png    2>/dev/null
    cp icon_1024.png icon.iconset/icon_512x512@2x.png
    iconutil -c icns icon.iconset -o "$SCRIPT_DIR/Comic.icns"
    echo "    圖示產生完成"
else
    echo "    圖示已是最新，略過"
fi

echo "==> 編譯 (release)"
swift build -c release --arch arm64 2>&1

echo "==> 建立 app bundle"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BINARY_DIR/$APP_NAME"  "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$SCRIPT_DIR/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "$SCRIPT_DIR/Comic.icns" "$APP_BUNDLE/Contents/Resources/Comic.icns"

chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

echo "==> 簽署 app（含 iCloud entitlements）"
codesign --force --deep \
    --sign "$SIGN_IDENTITY" \
    --entitlements "$ENTITLEMENTS" \
    --options runtime \
    "$APP_BUNDLE"

echo "==> 驗證簽署"
codesign --verify --deep --strict "$APP_BUNDLE" && echo "    簽署驗證通過"

echo "==> 移除 Gatekeeper 隔離旗標"
xattr -cr "$APP_BUNDLE"

pkill -x "$APP_NAME" 2>/dev/null || true
sleep 0.3

nohup "$APP_BUNDLE/Contents/MacOS/$APP_NAME" > /tmp/comic.log 2>&1 &
disown

echo ""
echo "✓ 完成並已啟動：$APP_BUNDLE"
echo "  大小：$(du -sh "$APP_BUNDLE" | cut -f1)"
echo "  log: /tmp/comic.log"
