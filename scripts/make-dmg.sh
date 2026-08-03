#!/bin/zsh
# 构建 Release .app 并打包为最轻量 .dmg（UDZO zlib-level=9 + 最小镜像尺寸）。
# 用法：make dmg  （或直接 zsh scripts/make-dmg.sh）
set -euo pipefail

APP_NAME="PetDesk"
VERSION="${1:-0.1.0}"
DIST="dist"

echo "==> Release 构建"
xcodebuild -project PetDesk.xcodeproj -scheme PetDesk -configuration Release build \
  CODE_SIGNING_ALLOWED=NO >/dev/null

BUILT_PRODUCTS_DIR=$(xcodebuild -project PetDesk.xcodeproj -scheme PetDesk \
  -configuration Release -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR =/{print $3; exit}')
APP_PATH="$BUILT_PRODUCTS_DIR/$APP_NAME.app"
test -d "$APP_PATH" || { echo "ERROR: $APP_PATH 不存在" >&2; exit 1; }

echo "==> 收集到 $DIST/root"
rm -rf "$DIST"
mkdir -p "$DIST/root"
cp -R "$APP_PATH" "$DIST/root/"
ln -s /Applications "$DIST/root/Applications"

echo "==> 生成 $DIST/$APP_NAME-$VERSION.dmg（UDZO zlib-level=9）"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DIST/root" \
  -ov \
  -format UDZO \
  -imagekey zlib-level=9 \
  "$DIST/$APP_NAME-$VERSION.dmg"

echo "==> 完成"
ls -lh "$DIST/$APP_NAME-$VERSION.dmg"
