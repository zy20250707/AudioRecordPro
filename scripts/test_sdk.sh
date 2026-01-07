#!/bin/bash
set -euo pipefail

# AudioRecord SDK 测试脚本

APP_NAME="sdk_test"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SRC_DIR="$ROOT_DIR/src"
BUILD_DIR="$ROOT_DIR/build"
TEST_BUILD_DIR="$BUILD_DIR/test"

# 解析命令行参数
TEST_MODE="basic"  # basic, mic, mixed
HELP=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -m|--mic|--microphone)
            TEST_MODE="mic"
            shift
            ;;
        -x|--mixed|--fusion)
            TEST_MODE="mixed"
            shift
            ;;
        -b|--basic)
            TEST_MODE="basic"
            shift
            ;;
        -h|--help)
            HELP=true
            shift
            ;;
        *)
            echo "未知参数: $1"
            HELP=true
            shift
            ;;
    esac
done

# 显示帮助信息
if [ "$HELP" = true ]; then
    echo "AudioRecord SDK 测试脚本"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -b, --basic      只进行基础测试（默认）"
    echo "  -m, --mic        进行麦克风录制测试"
    echo "  -x, --mixed      进行混音录制测试（系统音频+麦克风）"
    echo "  -h, --help       显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0               # 只进行基础测试"
    echo "  $0 --mic         # 麦克风录制测试"
    echo "  $0 --mixed       # 混音录制测试"
    exit 0
fi

echo "🧪 AudioRecord SDK 测试脚本"
echo "================================"
case "$TEST_MODE" in
    "mic")
        echo "🎤 测试模式: 麦克风录制"
        ;;
    "mixed")
        echo "🎵 测试模式: 混音录制（系统音频+麦克风）"
        ;;
    *)
        echo "📋 测试模式: 基础测试"
        ;;
esac
echo "================================"

# 清理测试构建目录
echo "[1/3] 清理测试构建目录..."
rm -rf "$TEST_BUILD_DIR"
mkdir -p "$TEST_BUILD_DIR"

# 编译测试程序
echo "[2/3] 编译 SDK 测试程序..."
swiftc \
  -sdk "$(xcrun --show-sdk-path --sdk macosx)" \
  -target "$(uname -m)-apple-macosx14.4" \
  -framework AppKit \
  -framework AVFoundation \
  -framework Accelerate \
  -framework CoreAudio \
  -framework AudioToolbox \
  -framework ScreenCaptureKit \
  -o "$TEST_BUILD_DIR/$APP_NAME" \
  "$SRC_DIR/Utils/Logger.swift" \
  "$SRC_DIR/Utils/FileManagerUtils.swift" \
  "$SRC_DIR/Utils/AudioUtils.swift" \
  "$SRC_DIR/Utils/LevelMonitor.swift" \
  "$SRC_DIR/Utils/PermissionManager.swift" \
  "$SRC_DIR/Models/AudioRecording.swift" \
  "$SRC_DIR/Recorder/AudioRecorderProtocol.swift" \
  "$SRC_DIR/Recorder/MicrophoneRecorder.swift" \
  "$SRC_DIR/Recorder/MixedAudioRecorder.swift" \
  "$SRC_DIR/ProcessTapRecorder/AudioProcessEnumerator.swift" \
  "$SRC_DIR/ProcessTapRecorder/ProcessTapManager.swift" \
  "$SRC_DIR/ProcessTapRecorder/AggregateDeviceManager.swift" \
  "$SRC_DIR/ProcessTapRecorder/AudioToolboxFileManager.swift" \
  "$SRC_DIR/ProcessTapRecorder/AudioCallbackHandler.swift" \
  "$SRC_DIR/ProcessTapRecorder/CoreAudioProcessTapRecorder.swift" \
  "$SRC_DIR/ProcessTapRecorder/SwiftProcessTapManager.swift" \
  "$SRC_DIR/AudioRecordSDK/AudioRecordAPI.swift" \
  "$SRC_DIR/AudioRecordSDK/AudioConstraints.swift" \
  "$SRC_DIR/AudioRecordSDK/MediaStream.swift" \
  "$SRC_DIR/AudioRecordSDK/MediaStreamTrack.swift" \
  "$SRC_DIR/AudioRecordSDK/AudioRecordError.swift" \
  "$SRC_DIR/AudioRecordSDK/AudioRecordSDK.swift" \
  "$SRC_DIR/AudioRecordSDK/Tests/SDKTestRunner.swift" \
  "$SRC_DIR/AudioRecordSDK/Tests/TestMain.swift"

echo "[3/3] 运行测试程序..."
echo "================================"

# 根据测试模式运行不同的测试
case "$TEST_MODE" in
    "mic")
        echo "2" | "$TEST_BUILD_DIR/$APP_NAME"
        ;;
    "mixed")
        echo "3" | "$TEST_BUILD_DIR/$APP_NAME"
        ;;
    *)
        echo "1" | "$TEST_BUILD_DIR/$APP_NAME"
        ;;
esac

echo "================================"
echo "✅ SDK 测试完成"
