# AudioRecordKit

macOS 音频录制 SDK，提供专业级的音频录制能力。

## 功能特性

- ✅ 麦克风录制 - 高质量麦克风音频录制
- ✅ 系统音频录制 - 录制系统音频输出
- ✅ 混音录制 - 麦克风 + 系统音频实时混音
- ✅ 特定进程录制 - 录制指定应用的音频（macOS 14.4+）

## 系统要求

- macOS 13.0+（基础功能）
- macOS 14.4+（Process Tap 功能）

## 安装

### Swift Package Manager

```swift
dependencies: [
    .package(path: "../AudioRecordKit")
]
```

## 快速开始

```swift
import AudioRecordKit

// 创建约束
let constraints = AudioConstraints(
    echoCancellation: true,
    noiseSuppression: true,
    includeSystemAudio: false
)

// 获取媒体流
let stream = try await AudioRecordAPI.shared.getUserMedia(constraints: constraints)

// 开始录制
try AudioRecordAPI.shared.startRecording(stream: stream)

// 停止录制
AudioRecordAPI.shared.stopRecording()
```

## 目录结构

```
AudioRecordKit/
├── Sources/
│   ├── Core/           # 核心实现（internal）
│   │   ├── Protocols/  # 协议定义
│   │   ├── Recorders/  # 录制器实现
│   │   ├── ProcessTap/ # CoreAudio 实现
│   │   └── Models/     # 数据模型
│   ├── API/            # 公开 API（public）
│   ├── CAPI/           # C API 导出
│   └── Utils/          # 工具类（internal）
├── Tests/              # 测试代码
└── Package.swift
```

## License

MIT


