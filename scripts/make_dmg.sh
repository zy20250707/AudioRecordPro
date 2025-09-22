#!/bin/bash
set -euo pipefail

APP_NAME="AudioRecordMac"
APP_BUNDLE="${APP_NAME}.app"
BUILD_DIR="$(cd "$(dirname "$0")/.." && pwd)/build"
APP_PATH="$BUILD_DIR/${APP_BUNDLE}"
PKG_DIR="$BUILD_DIR/pkg_root"
VOL_NAME="AudioRecord"
DMG_PATH="$BUILD_DIR/${VOL_NAME}.dmg"
MOUNT_POINT="/Volumes/${VOL_NAME}"
RES_DIR="$PKG_DIR/.resources"
BG_DIR="$PKG_DIR/.background"

rm -rf "$PKG_DIR" "$DMG_PATH" "$MOUNT_POINT" 2>/dev/null || true
mkdir -p "$PKG_DIR" "$RES_DIR" "$BG_DIR"

# 资源准备：背景与卷标图标
# 背景图若无则使用项目 assets/screenshot-main.png 代替
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BG_SRC="$PROJECT_ROOT/assets/screenshot-main.png"
if [ ! -f "$BG_SRC" ]; then
  echo "背景图不存在: $BG_SRC" >&2
  exit 1
fi
cp "$BG_SRC" "$BG_DIR/bg.png"

# 卷标图标
ICON_SRC="$PROJECT_ROOT/build/AppIcon-1024.png"
if [ -f "$ICON_SRC" ]; then
  sips -s format icns "$ICON_SRC" --out "$PKG_DIR/.VolumeIcon.icns" >/dev/null 2>&1 || true
fi

# 安装脚本
INSTALL_SH="$RES_DIR/install.sh"
cat > "$INSTALL_SH" <<'SH'
#!/bin/bash
set -euo pipefail
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_APP="$SELF_DIR/AudioRecordMac.app"
TARGET="/Applications/AudioRecordMac.app"

echo "Installing to $TARGET ..."
rsync -a --delete "$SRC_APP" "$TARGET/.." >/dev/null 2>&1 || cp -R "$SRC_APP" "$TARGET"
open -R "$TARGET" || true
osascript -e 'display notification "安装完成" with title "AudioRecord"'
# 弹出DMG
VOL_PATH=$(df | awk '/\/Volumes\//{print $NF}' | head -n1)
if [ -n "$VOL_PATH" ]; then hdiutil detach "$VOL_PATH" -quiet || true; fi
SH
chmod +x "$INSTALL_SH"

# 复制真实应用到 .resources 隐藏目录
cp -R "$APP_PATH" "$RES_DIR/AudioRecordMac.app"

# DMG 根布局：创建带自定义图标的 AppleScript 启动器 App（内部调用 install.sh）
LAUNCH_APP_NAME="AudioRecord.app"
LAUNCH_APP_PATH="$PKG_DIR/$LAUNCH_APP_NAME"
LAUNCH_SRC="$PKG_DIR/launch_install.applescript"
cat > "$LAUNCH_SRC" <<APL
set installPath to "/Volumes/${VOL_NAME}/.resources/install.sh"
do shell script quoted form of installPath
APL
/usr/bin/osacompile -o "$LAUNCH_APP_PATH" "$LAUNCH_SRC" 2>/dev/null || true
rm -f "$LAUNCH_SRC"
ICONSET_DIR="$PROJECT_ROOT/build/AppIcon.iconset"
if [ -d "$ICONSET_DIR" ]; then
  mkdir -p "$LAUNCH_APP_PATH/Contents/Resources"
  iconutil -c icns "$ICONSET_DIR" -o "$LAUNCH_APP_PATH/Contents/Resources/applet.icns" 2>/dev/null || true
fi

# 隐藏 .background 与 .resources
chflags hidden "$BG_DIR" || true
chflags hidden "$RES_DIR" || true
[ -f "$PKG_DIR/.VolumeIcon.icns" ] && {
  /usr/bin/SetFile -a C "$PKG_DIR" 2>/dev/null || true
}

# 预创建 DMG
hdiutil create -fs HFS+ -volname "$VOL_NAME" -srcfolder "$PKG_DIR" -ov "$DMG_PATH"

# 挂载并写入 .DS_Store（设置背景与图标位置）
hdiutil attach "$DMG_PATH" -mountpoint "$MOUNT_POINT" -quiet || true
sleep 1

/usr/bin/osascript <<OSA
set volPath to POSIX file "$MOUNT_POINT" as alias
set bgPath to POSIX file "$MOUNT_POINT/.background/bg.png" as alias

tell application "Finder"
  tell disk "$VOL_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 150, 900, 650}
    delay 0.2
    set background picture of container window to bgPath
    delay 0.2
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 128
    -- 布局安装入口位置
    set position of file "$LAUNCH_APP_NAME" to {380, 240}
    update without registering applications
    delay 0.3
    close
    open
    update without registering applications
  end tell
end tell
OSA

# 卸载并压缩
hdiutil detach "$MOUNT_POINT" -quiet || true
hdiutil convert "$DMG_PATH" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH" -quiet

echo "✅ DMG 生成完成: $DMG_PATH"
