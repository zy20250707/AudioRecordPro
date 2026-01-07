# AudioRecord SDK

macOS 音频录制 SDK，提供简洁易用的 API 来实现麦克风录制和系统音频混音录制。

## 🎯 功能特性

- ✅ **麦克风录制** - 高质量麦克风音频录制
- ✅ **系统音频录制** - 录制系统音频输出
- ✅ **混音录制** - 麦克风 + 系统音频实时混音
- ✅ **音频处理** - 回声消除、噪音抑制
- ✅ **异步 API** - 基于 async/await 的现代 Swift API
- ✅ **类型安全** - 完整的 Swift 类型系统支持

## 📦 文件结构

```
AudioRecordSDK/
├── AudioRecordAPI.swift        // 核心 API
├── AudioConstraints.swift      // 约束参数
├── MediaStream.swift           // 媒体流
├── MediaStreamTrack.swift      // 媒体轨道
├── AudioRecordError.swift      // 错误定义
├── AudioRecordSDK.swift        // 统一导出
├── Examples/
│   └── BasicUsage.swift        // 使用示例
└── README.md                   // 说明文档
```

## 🚀 快速开始

### 1. 导入 SDK

```swift
import AudioRecordSDK
```

### 2. 麦克风录制

```swift
@MainActor
class MyRecorder {
    private let audioAPI = AudioAPI.shared
    private var currentStream: AudioStream?
    
    func startMicrophoneRecording() async {
        do {
            // 创建麦克风约束
            let constraints = createMicrophoneConstraints(
                echoCancellation: true,
                noiseSuppression: true
            )
            
            // 获取媒体流
            let stream = try await audioAPI.getUserMedia(constraints: constraints)
            currentStream = stream
            
            // 设置回调
            audioAPI.onRecordingComplete = { recording in
                print("录制完成: \(recording.fileName)")
            }
            
            // 开始录制
            try audioAPI.startRecording(stream: stream)
            
        } catch {
            print("录制失败: \(error.localizedDescription)")
        }
    }
    
    func stopRecording() {
        audioAPI.stopRecording()
    }
}
```

### 3. 混音录制

```swift
func startMixedRecording() async {
    do {
        // 创建混音约束
        let constraints = createMixedAudioConstraints(
            echoCancellation: true,
            noiseSuppression: true
        )
        
        // 获取媒体流
        let stream = try await audioAPI.getUserMedia(constraints: constraints)
        
        // 开始录制
        try audioAPI.startRecording(stream: stream)
        
        print("混音录制已开始 (麦克风 + 系统音频)")
        
    } catch {
        print("混音录制失败: \(error.localizedDescription)")
    }
}
```

## 📋 API 参考

### AudioAPI (核心 API)

```swift
class AudioRecordAPI {
    static let shared: AudioRecordAPI
    
    // 属性
    var isRecording: Bool { get }
    var onLevel: ((Float) -> Void)?
    var onStatus: ((String) -> Void)?
    var onRecordingComplete: ((AudioRecording) -> Void)?
    
    // 方法
    func getUserMedia(constraints: AudioConstraints) async throws -> MediaStream
    func startRecording(stream: MediaStream) throws
    func stopRecording()
}
```

### AudioConstraints (约束参数)

```swift
struct AudioConstraints {
    let sampleRate: Int = 48000        // 固定 48kHz
    let channelCount: Int = 2          // 固定立体声
    var echoCancellation: Bool = true
    var noiseSuppression: Bool = true
    var includeSystemAudio: Bool = false
}
```

### MediaStream (媒体流)

```swift
class MediaStream {
    let id: String
    var active: Bool { get }
    var recordingMode: String { get }
    
    func getAudioTracks() -> [MediaStreamTrack]
    func getTracks() -> [MediaStreamTrack]
}
```

### MediaStreamTrack (媒体轨道)

```swift
class MediaStreamTrack {
    let kind: String = "audio"
    let id: String
    let label: String
    var enabled: Bool
    var readyState: ReadyState
    
    func stop()
}
```

## 🔧 便捷方法

SDK 提供了便捷的约束创建方法：

```swift
// 麦克风录制约束
let micConstraints = createMicrophoneConstraints(
    echoCancellation: true,
    noiseSuppression: true
)

// 混音录制约束
let mixedConstraints = createMixedAudioConstraints(
    echoCancellation: true,
    noiseSuppression: true
)
```

## ⚠️ 错误处理

```swift
enum AudioRecordError: Error {
    case microphonePermissionDenied     // 麦克风权限被拒绝
    case systemAudioPermissionDenied    // 系统音频权限被拒绝
    case deviceNotFound                 // 音频设备未找到
    case alreadyRecording              // 录制已在进行中
    case notSupported(String)          // 功能不支持
    case unknown(Error)                // 未知错误
}
```

## 📊 回调事件

```swift
// 音频电平监控
audioAPI.onLevel = { level in
    print("音频电平: \(level)")
}

// 状态更新
audioAPI.onStatus = { status in
    print("状态: \(status)")
}

// 录制完成
audioAPI.onRecordingComplete = { recording in
    print("录制完成: \(recording.fileName)")
    print("时长: \(recording.formattedDuration)")
    print("大小: \(recording.formattedFileSize)")
}
```

## 🎵 完整示例

查看 `Examples/BasicUsage.swift` 文件获取完整的使用示例。

## 📝 版本信息

```swift
AudioRecordSDKInfo.printInfo()
// 输出:
// === AudioRecordSDK v1.0.0 ===
// macOS 音频录制 SDK，支持麦克风和系统音频混音录制
// 支持功能:
// - 麦克风录制
// - 系统音频录制
// - 混音录制 (麦克风 + 系统音频)
// - 回声消除和噪音抑制
```

## 🔗 依赖关系

SDK 依赖以下现有组件：
- `MicrophoneRecorder` - 麦克风录制器
- `MixedAudioRecorder` - 混音录制器
- `Logger` - 日志系统
- `FileManagerUtils` - 文件管理

## 🎯 设计理念

- **简洁易用** - 只需几行代码即可实现录制
- **类型安全** - 完整的 Swift 类型系统支持
- **异步优先** - 基于 async/await 的现代 API
- **错误友好** - 清晰的错误信息和处理
- **扩展性** - 为未来功能预留接口

## 📄 许可证

本 SDK 是 AudioRecord macOS 应用的一部分。
