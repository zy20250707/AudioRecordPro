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
  "$STAGE_DIR/src/Views/MainWindowView.swift" \
  "$STAGE_DIR/src/Controllers/MicrophoneRecorder.swift" \
  "$STAGE_DIR/src/Controllers/SystemAudioRecorder.swift" \
  "$STAGE_DIR/src/Controllers/AudioRecorderController.swift" \
  "$STAGE_DIR/src/Controllers/MainViewController.swift" \
  "$STAGE_DIR/src/Controllers/AppDelegate.swift"

echo "[3/4] 拷贝 Info.plist 与资源..."
plutil -convert binary1 "$ROOT_DIR/Info.plist" -o "$CONTENTS_DIR/Info.plist"

echo "[3.5/4] 代码签名..."
# 使用 ad-hoc 签名，这样系统会认为这是同一个应用
codesign --force --sign - "$APP_DIR"

echo "[4/4] 完成，应用位于: $APP_DIR"
echo "运行: open \"$APP_DIR\""


