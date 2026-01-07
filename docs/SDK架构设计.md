# AudioRecordSDK 架构设计文档

## 📌 概述

本文档描述 AudioRecordSDK 的整体架构设计，目标是将 macOS 音频录制能力打包为 SDK，供以下场景使用：

- **Chromium** (C++) - 浏览器引擎集成
- **Electron** (Node.js) - 桌面应用
- **Swift/OC 应用** - 原生 macOS 应用

---

## 🏗️ 整体架构

```
┌─────────────────────────────────────────────────────────────────┐
│                         调用方层                                 │
├──────────────────┬──────────────────┬───────────────────────────┤
│   Swift 应用     │    Chromium      │       Electron            │
│                  │     (C++)        │      (Node.js)            │
│   使用 Swift API │   使用 C API     │   使用 N-API Addon        │
└────────┬─────────┴────────┬─────────┴─────────────┬─────────────┘
         │                  │                       │
         ▼                  ▼                       ▼
┌─────────────────────────────────────────────────────────────────┐
│                        API 接口层                                │
├──────────────────┬──────────────────┬───────────────────────────┤
│   Swift API      │     C API        │    N-API Addon            │
│   (原生体验)      │   (跨语言)        │   (Node.js 绑定)          │
│                  │                  │                           │
│  AudioRecordAPI  │ AudioRecord_xxx  │  audio_record.node        │
│   async/await    │   函数导出        │   预编译二进制             │
└────────┬─────────┴────────┬─────────┴─────────────┬─────────────┘
         │                  │                       │
         └──────────────────┼───────────────────────┘
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                        C API 导出层                              │
│                                                                 │
│   AudioRecordSDK.h (头文件) + AudioRecordSDK_C.swift (@_cdecl)  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Swift 核心实现层                            │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │  AudioRecordCore                                            ││
│  │  ├── MicrophoneRecorder (AVAudioEngine)                     ││
│  │  ├── MixedAudioRecorder (AVAudioEngine + ProcessTap)        ││
│  │  ├── CoreAudioProcessTapRecorder (系统/进程音频)             ││
│  │  ├── ProcessTapManager / AggregateDeviceManager             ││
│  │  └── AudioToolboxFileManager (文件写入)                      ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                        系统框架层                                │
│   AVFoundation │ CoreAudio │ AudioToolbox │ ScreenCaptureKit    │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🔤 语言选择决策

| 层级 | 语言 | 原因 |
|------|------|------|
| **核心实现** | Swift | 现有代码、类型安全、现代 API、Apple 新框架支持 |
| **Swift API** | Swift | 原生体验、async/await、类型安全 |
| **C API** | Swift + @_cdecl | 导出 C 函数，最大兼容性 |
| **N-API Addon** | C++ | 高性能、直接链接 Framework |

---

## 📡 C API 设计要点

### 核心函数

```c
// 生命周期
AudioRecordHandle AudioRecord_Create(void);
void AudioRecord_Destroy(AudioRecordHandle handle);

// 录制控制
AudioRecordError AudioRecord_Start(AudioRecordHandle handle, AudioRecordMode mode);
AudioRecordError AudioRecord_Stop(AudioRecordHandle handle);
bool AudioRecord_IsRecording(AudioRecordHandle handle);

// 回调设置
void AudioRecord_SetLevelCallback(AudioRecordHandle handle, AudioLevelCallback callback, void* userData);
void AudioRecord_SetCompleteCallback(AudioRecordHandle handle, AudioCompleteCallback callback, void* userData);
```

---

## 🚀 开发路线图

### Phase 1: C API 层 ⏳
- [ ] 创建 `AudioRecordSDK.h` 头文件
- [ ] 实现 `AudioRecordSDK_C.swift` (@_cdecl 导出)
- [ ] 构建脚本生成 `.framework`

### Phase 2: N-API Addon
- [ ] 创建 `audio_record_addon.cc`
- [ ] 配置 `binding.gyp`
- [ ] 预编译 arm64/x86_64

### Phase 3: 集成测试
- [ ] Chromium 集成测试
- [ ] Electron 集成测试
- [ ] 文档完善

---

## ⚠️ 注意事项

### 系统要求
- **基础功能**: macOS 13.0+
- **混音功能**: macOS 14.4+ (Process Tap API)

### 权限要求
- 麦克风权限 (NSMicrophoneUsageDescription)
- 屏幕录制权限 (用于系统音频捕获)

### 线程安全
- C API 内部使用 `DispatchQueue.main.async` 确保 UI 线程安全
- 回调在主线程执行
- 音频数据处理使用 `NSLock` 保护

详细设计请参考根目录的 `SDK_Architecture_Design.md` 文件。

