#!/bin/bash
set -euo pipefail

APP_NAME="AudioRecordMac"
APP_BUNDLE="${APP_NAME}.app"
BUILD_DIR="$(cd "$(dirname "$0")/.." && pwd)/build"
APP_PATH="$BUILD_DIR/${APP_BUNDLE}"
PKG_DIR="$BUILD_DIR/pkg_simple"
VOL_NAME="AudioRecord"
DMG_PATH="$BUILD_DIR/${VOL_NAME}_simple.dmg"
MOUNT_POINT="/Volumes/${VOL_NAME}"
BG_DIR="$PKG_DIR/.background"

# 清理旧文件
rm -rf "$PKG_DIR" "$DMG_PATH" "$MOUNT_POINT" 2>/dev/null || true
mkdir -p "$PKG_DIR" "$BG_DIR"

# 复制应用
echo "📱 复制应用到DMG..."
cp -R "$APP_PATH" "$PKG_DIR/"

# 清理隔离属性
echo "🔧 清理安全属性..."
xattr -dr com.apple.quarantine "$PKG_DIR/$APP_BUNDLE" 2>/dev/null || true
xattr -dr com.apple.metadata:kMDItemWhereFroms "$PKG_DIR/$APP_BUNDLE" 2>/dev/null || true

# 背景图
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BG_SRC="$PROJECT_ROOT/assets/screenshot-main.png"
if [ -f "$BG_SRC" ]; then
    cp "$BG_SRC" "$BG_DIR/bg.png"
fi

# 卷标图标
ICON_SRC="$PROJECT_ROOT/build/AppIcon-1024.png"
if [ -f "$ICON_SRC" ]; then
    sips -s format icns "$ICON_SRC" --out "$PKG_DIR/.VolumeIcon.icns" >/dev/null 2>&1 || true
fi

# 隐藏背景目录
chflags hidden "$BG_DIR" || true

# 设置卷标图标
[ -f "$PKG_DIR/.VolumeIcon.icns" ] && {
    /usr/bin/SetFile -a C "$PKG_DIR" 2>/dev/null || true
}

# 创建DMG
echo "💿 创建DMG文件..."
hdiutil create -fs HFS+ -volname "$VOL_NAME" -srcfolder "$PKG_DIR" -ov "$DMG_PATH"

# 挂载并设置布局
echo "🎨 设置DMG布局..."
hdiutil attach "$DMG_PATH" -mountpoint "$MOUNT_POINT" -quiet || true
sleep 2

/usr/bin/osascript <<OSA
tell application "Finder"
  tell disk "$VOL_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 150, 800, 500}
    delay 0.5
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 128
    delay 0.5
    -- 设置应用位置
    set position of file "$APP_BUNDLE" to {200, 200}
    delay 0.5
    update without registering applications
    delay 0.5
    close
  end tell
end tell
OSA

sleep 1

# 卸载并压缩
echo "🗜️ 压缩DMG..."
hdiutil detach "$MOUNT_POINT" -quiet || true
sleep 1
TMP_DMG="${DMG_PATH%.dmg}_tmp.dmg"
hdiutil convert "$DMG_PATH" -format UDZO -imagekey zlib-level=9 -o "$TMP_DMG" -quiet
mv "$TMP_DMG" "$DMG_PATH"

echo "✅ 简单DMG生成完成: $DMG_PATH"
echo ""
echo "📋 使用说明："
echo "1. 双击DMG文件挂载"
echo "2. 将AudioRecordMac.app拖拽到Applications文件夹"
echo "3. 如果提示'已损坏'，请右键点击应用选择'打开'"
echo "4. 在警告对话框中点击'打开'即可使用"
