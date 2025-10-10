#!/bin/bash
set -euo pipefail

APP_NAME="audio_record_mac"
PRODUCT_NAME="AudioRecordMac"
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$ROOT_DIR/src"
BUILD_DIR="$ROOT_DIR/build"
STAGE_DIR="$BUILD_DIR/stage"
APP_DIR="$BUILD_DIR/$PRODUCT_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "[1/4] 清理旧构建..."
rm -rf "$BUILD_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$STAGE_DIR/src"

echo "[1.5/4] 复制源码到临时目录..."
rsync -a "$SRC_DIR/" "$STAGE_DIR/src/"

echo "[2/4] 编译 Swift 源码..."
swiftc \
  -sdk "$(xcrun --show-sdk-path --sdk macosx)" \
  -target "$(uname -m)-apple-macosx13.0" \
  -framework AppKit \
  -framework AVFoundation \
  -framework Accelerate \
  -framework CoreAudio \
  -framework AudioToolbox \
  -framework ScreenCaptureKit \
  -o "$MACOS_DIR/$APP_NAME" \
  "$STAGE_DIR/src/main.swift" \
  "$STAGE_DIR/src/Utils/Logger.swift" \
  "$STAGE_DIR/src/Utils/FileManagerUtils.swift" \
  "$STAGE_DIR/src/Utils/AudioUtils.swift" \
  "$STAGE_DIR/src/Utils/LevelMonitor.swift" \
  "$STAGE_DIR/src/Utils/PermissionManager.swift" \
  "$STAGE_DIR/src/Models/AudioRecording.swift" \
  "$STAGE_DIR/src/Views/LevelMeterView.swift" \
  "$STAGE_DIR/src/Views/SidebarView.swift" \
  "$STAGE_DIR/src/Views/TracksView.swift" \
  "$STAGE_DIR/src/Views/ControlPanelView.swift" \
  "$STAGE_DIR/src/Views/StatusBarView.swift" \
  "$STAGE_DIR/src/Views/MainWindowView.swift" \
  "$STAGE_DIR/src/Views/TabContainerView.swift" \
  "$STAGE_DIR/src/Views/RecordedFilesView.swift" \
  "$STAGE_DIR/src/Views/WaveformView.swift" \
  "$STAGE_DIR/src/Recorder/AudioRecorderProtocol.swift" \
  "$STAGE_DIR/src/Recorder/MicrophoneRecorder.swift" \
  "$STAGE_DIR/src/Recorder/ScreenCaptureAudioRecorder.swift" \
  "$STAGE_DIR/src/Controllers/AudioRecorderController.swift" \
  "$STAGE_DIR/src/Controllers/MainViewController.swift" \
  "$STAGE_DIR/src/Controllers/AppDelegate.swift" \
  "$STAGE_DIR/src/ProcessTapRecorder/AudioProcessEnumerator.swift" \
  "$STAGE_DIR/src/ProcessTapRecorder/ProcessTapManager.swift" \
  "$STAGE_DIR/src/ProcessTapRecorder/AggregateDeviceManager.swift" \
  "$STAGE_DIR/src/ProcessTapRecorder/AudioToolboxFileManager.swift" \
  "$STAGE_DIR/src/ProcessTapRecorder/AudioCallbackHandler.swift" \
  "$STAGE_DIR/src/ProcessTapRecorder/CoreAudioProcessTapRecorder.swift" \
  "$STAGE_DIR/src/ProcessTapRecorder/SwiftProcessTapManager.swift"

echo "[3/4] 拷贝 Info.plist 与资源..."
plutil -convert binary1 "$ROOT_DIR/Info.plist" -o "$CONTENTS_DIR/Info.plist"

# 复制资源文件（如应用图标等）到 Resources
if [ -d "$ROOT_DIR/assets" ]; then
  rsync -a "$ROOT_DIR/assets/" "$RESOURCES_DIR/"
fi

# 生成标准 macOS App 图标（.icns）
ICON_SRC="$ROOT_DIR/assets/AudioRecordLogo.png"
if [ -f "$ICON_SRC" ]; then
  echo "[3.2/4] 生成 App 图标 (.icns)..."
  ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
  TMP_ICON="$BUILD_DIR/AppIcon-1024.png"
  rm -rf "$ICONSET_DIR"
  mkdir -p "$ICONSET_DIR"
  # 归一化为 1024x1024 正方形（等比缩放后再居中裁剪）
  sips -s format png "$ICON_SRC" --resampleHeightWidthMax 1024 --out "$TMP_ICON" >/dev/null
  sips -s format png "$TMP_ICON" --cropToHeightWidth 1024 1024 --out "$TMP_ICON" >/dev/null

  gen_icon() { local size=$1 name=$2; sips -s format png "$TMP_ICON" --resampleHeightWidth $size $size --out "$ICONSET_DIR/$name" >/dev/null; }
  gen_icon 16  icon_16x16.png
  gen_icon 32  icon_16x16@2x.png
  gen_icon 32  icon_32x32.png
  gen_icon 64  icon_32x32@2x.png
  gen_icon 128 icon_128x128.png
  gen_icon 256 icon_128x128@2x.png
  gen_icon 256 icon_256x256.png
  gen_icon 512 icon_256x256@2x.png
  gen_icon 512 icon_512x512.png
  gen_icon 1024 icon_512x512@2x.png

  iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"
fi

echo "[3.5/4] 代码签名..."
# 使用 entitlements 进行签名（若存在），否则退回 ad-hoc
ENTITLEMENTS_PLIST="$ROOT_DIR/AudioRecordMac.entitlements"
if [ -f "$ENTITLEMENTS_PLIST" ]; then
  echo "使用 entitlements 签名可执行文件与 .app"
  codesign --force --entitlements "$ENTITLEMENTS_PLIST" --options runtime --sign - "$MACOS_DIR/$APP_NAME"
  codesign --force --entitlements "$ENTITLEMENTS_PLIST" --options runtime --sign - "$APP_DIR"
else
  echo "未找到 entitlements，使用 ad-hoc 签名"
  codesign --force --sign - "$APP_DIR"
fi

echo "[4/4] 完成，应用位于: $APP_DIR"
echo "运行: open \"$APP_DIR\""


