#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="Comic"
SRC="$SCRIPT_DIR/$APP_NAME.app"
DEST="/Applications/$APP_NAME.app"

# 若還沒有 build，先執行 release
if [ ! -d "$SRC" ]; then
    echo "==> 尚未 build，先執行 release.sh"
    bash "$SCRIPT_DIR/release.sh"
fi

echo "==> 關閉正在執行的 $APP_NAME（若有）"
osascript -e "tell application \"$APP_NAME\" to quit" 2>/dev/null || true
sleep 0.5

echo "==> 安裝到 /Applications"
if [ -d "$DEST" ]; then
    rm -rf "$DEST"
fi
cp -R "$SRC" "$DEST"
xattr -cr "$DEST" 2>/dev/null || true

echo "==> 啟動 $APP_NAME"
open "$DEST"

echo ""
echo "✓ 安裝完成：$DEST"
