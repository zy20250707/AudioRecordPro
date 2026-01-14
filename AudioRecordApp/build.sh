#!/bin/bash
# AudioRecordApp 构建脚本
# 依赖 AudioRecordKit SDK

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_ROOT/build"
APP_NAME="AudioRecordMac"

echo "🔨 开始构建 $APP_NAME..."
echo "项目根目录: $PROJECT_ROOT"

# 创建构建目录
mkdir -p "$BUILD_DIR/$APP_NAME.app/Contents/MacOS"
mkdir -p "$BUILD_DIR/$APP_NAME.app/Contents/Resources"

# 编译源文件
echo "📦 编译源文件..."

# SDK 源文件
SDK_SOURCES=$(find "$PROJECT_ROOT/AudioRecordKit/Sources" -name "*.swift" 2>/dev/null | tr '\n' ' ')

# App 源文件
APP_SOURCES=$(find "$SCRIPT_DIR/Sources" -name "*.swift" 2>/dev/null | tr '\n' ' ')

# 合并编译
swiftc \
    -o "$BUILD_DIR/$APP_NAME.app/Contents/MacOS/$APP_NAME" \
    -sdk $(xcrun --show-sdk-path) \
    -target arm64-apple-macos13.0 \
    -framework Cocoa \
    -framework AVFoundation \
    -framework CoreAudio \
    -framework AudioToolbox \
    -framework ScreenCaptureKit \
    $SDK_SOURCES \
    $APP_SOURCES

# 复制资源
echo "📋 复制资源..."
cp "$SCRIPT_DIR/Resources/Info.plist" "$BUILD_DIR/$APP_NAME.app/Contents/"

if [ -d "$SCRIPT_DIR/Resources/Assets" ]; then
    cp -r "$SCRIPT_DIR/Resources/Assets/"* "$BUILD_DIR/$APP_NAME.app/Contents/Resources/" 2>/dev/null || true
fi

# 代码签名
echo "🔐 代码签名..."
if [ -f "$SCRIPT_DIR/Resources/AudioRecordMac.entitlements" ]; then
    codesign --force --sign - --entitlements "$SCRIPT_DIR/Resources/AudioRecordMac.entitlements" "$BUILD_DIR/$APP_NAME.app"
else
    codesign --force --sign - "$BUILD_DIR/$APP_NAME.app"
fi

echo "✅ 构建完成: $BUILD_DIR/$APP_NAME.app"


