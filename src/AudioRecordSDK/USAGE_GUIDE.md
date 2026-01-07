# AudioRecord SDK 使用指南

## 🚀 快速开始

### 1. 基本设置

```swift
import Foundation

// 获取 SDK 实例
let audioAPI = AudioAPI.shared

// 设置回调
audioAPI.onRecordingComplete = { recording in
    print("录制完成: \(recording.fileName)")
}
```

### 2. 麦克风录制

```swift
@MainActor
func startMicrophoneRecording() async {
    do {
        // 创建麦克风约束
        let constraints = createMicrophoneConstraints(
            echoCancellation: true,
            noiseSuppression: true
        )
        
        // 获取媒体流
        let stream = try await audioAPI.getUserMedia(constraints: constraints)
        
        // 开始录制
        try audioAPI.startRecording(stream: stream)
        
        print("麦克风录制已开始")
        
    } catch {
        print("录制失败: \(error.localizedDescription)")
    }
}
```

### 3. 混音录制 (麦克风 + 系统音频)

```swift
@MainActor
func startMixedRecording() async {
    do {
        // 创建混音约束
        let constraints = createMixedAudioConstraints(
            echoCancellation: true,
            noiseSuppression: false  // 混音时可能不需要噪音抑制
        )
        
        // 获取媒体流
        let stream = try await audioAPI.getUserMedia(constraints: constraints)
        
        // 开始录制
        try audioAPI.startRecording(stream: stream)
        
        print("混音录制已开始")
        
    } catch {
        print("混音录制失败: \(error.localizedDescription)")
    }
}
```

### 4. 停止录制

```swift
func stopRecording() {
    audioAPI.stopRecording()
    print("录制已停止")
}
```

## 📊 监控和回调

### 音频电平监控

```swift
audioAPI.onLevel = { level in
    // level 范围: 0.0 - 1.0
    let percentage = Int(level * 100)
    print("音频电平: \(percentage)%")
    
    // 更新 UI
    DispatchQueue.main.async {
        self.levelMeter.value = level
    }
}
```

### 状态更新

```swift
audioAPI.onStatus = { status in
    print("状态更新: \(status)")
    
    // 更新 UI 状态
    DispatchQueue.main.async {
        self.statusLabel.text = status
    }
}
```

### 录制完成

```swift
audioAPI.onRecordingComplete = { recording in
    print("录制完成:")
    print("  文件名: \(recording.fileName)")
    print("  时长: \(recording.formattedDuration)")
    print("  大小: \(recording.formattedFileSize)")
    print("  路径: \(recording.fileURL.path)")
    
    // 播放录制的文件
    playRecording(recording)
}
```

## 🔧 高级用法

### 检查录制状态

```swift
func checkRecordingStatus() {
    if audioAPI.isRecording {
        print("正在录制中...")
    } else {
        print("未在录制")
    }
}
```

### 流信息获取

```swift
func getStreamInfo(stream: AudioStream) {
    print("流 ID: \(stream.id)")
    print("录制模式: \(stream.recordingMode)")
    print("流状态: \(stream.active ? "活跃" : "非活跃")")
    
    let tracks = stream.getAudioTracks()
    for (index, track) in tracks.enumerated() {
        print("轨道 \(index + 1):")
        print("  ID: \(track.id)")
        print("  标签: \(track.label)")
        print("  启用: \(track.enabled)")
        print("  状态: \(track.readyState)")
    }
}
```

## ⚠️ 错误处理

### 完整的错误处理示例

```swift
@MainActor
func startRecordingWithErrorHandling() async {
    do {
        let constraints = createMicrophoneConstraints()
        let stream = try await audioAPI.getUserMedia(constraints: constraints)
        try audioAPI.startRecording(stream: stream)
        
    } catch AudioError.microphonePermissionDenied {
        showAlert("请在系统设置中允许麦克风权限")
        
    } catch AudioError.systemAudioPermissionDenied {
        showAlert("请在系统设置中允许系统音频权限")
        
    } catch AudioError.deviceNotFound {
        showAlert("未找到音频设备，请检查设备连接")
        
    } catch AudioError.alreadyRecording {
        showAlert("录制已在进行中，请先停止当前录制")
        
    } catch AudioError.notSupported(let feature) {
        showAlert("当前版本不支持: \(feature)")
        
    } catch {
        showAlert("录制失败: \(error.localizedDescription)")
    }
}

func showAlert(_ message: String) {
    // 显示错误提示
    print("错误: \(message)")
}
```

## 🎯 SwiftUI 集成示例

```swift
import SwiftUI

@available(macOS 14.4, *)
struct AudioRecorderView: View {
    @State private var isRecording = false
    @State private var audioLevel: Float = 0.0
    @State private var statusMessage = "准备就绪"
    
    private let audioAPI = AudioAPI.shared
    
    var body: some View {
        VStack(spacing: 20) {
            Text("音频录制器")
                .font(.title)
            
            Text(statusMessage)
                .foregroundColor(isRecording ? .green : .primary)
            
            if isRecording {
                ProgressView(value: Double(audioLevel), in: 0...1)
                    .progressViewStyle(LinearProgressViewStyle())
            }
            
            HStack {
                Button("开始录制") {
                    Task { await startRecording() }
                }
                .disabled(isRecording)
                
                Button("停止录制") {
                    stopRecording()
                }
                .disabled(!isRecording)
            }
        }
        .padding()
        .onAppear {
            setupCallbacks()
        }
    }
    
    private func setupCallbacks() {
        audioAPI.onLevel = { level in
            audioLevel = level
        }
        
        audioAPI.onStatus = { status in
            statusMessage = status
        }
        
        audioAPI.onRecordingComplete = { recording in
            statusMessage = "录制完成: \(recording.fileName)"
            isRecording = false
        }
    }
    
    private func startRecording() async {
        do {
            let constraints = createMicrophoneConstraints()
            let stream = try await audioAPI.getUserMedia(constraints: constraints)
            try audioAPI.startRecording(stream: stream)
            isRecording = true
        } catch {
            statusMessage = "录制失败: \(error.localizedDescription)"
        }
    }
    
    private func stopRecording() {
        audioAPI.stopRecording()
        isRecording = false
    }
}
```

## 🔍 调试和测试

### 运行 SDK 测试

```bash
# 运行完整测试
./scripts/test_sdk.sh

# 自动运行实际录制测试
echo "y" | ./scripts/test_sdk.sh
```

### 在应用中集成测试

```swift
// 在 AppDelegate 中添加
@available(macOS 14.4, *)
func applicationDidFinishLaunching(_ notification: Notification) {
    // 运行快速测试
    IntegratedSDKTest.runStartupTests()
    
    // 开发模式下运行完整测试
    #if DEBUG
    IntegratedSDKTest.runDevelopmentTests()
    #endif
}
```

## 📋 最佳实践

### 1. 权限管理
- 在使用前检查权限状态
- 提供清晰的权限请求说明
- 处理权限被拒绝的情况

### 2. 错误处理
- 使用完整的 do-catch 块
- 为每种错误类型提供用户友好的提示
- 记录错误日志用于调试

### 3. UI 更新
- 使用 `@MainActor` 确保 UI 更新在主线程
- 提供实时的录制状态反馈
- 显示音频电平指示器

### 4. 资源管理
- 及时停止不需要的录制
- 在应用退出时清理资源
- 监控内存使用情况

## 🔗 相关文档

- [SDK README](README.md) - 完整的 API 文档
- [测试结果](Tests/TestResults.md) - 测试报告
- [基础示例](Examples/BasicUsage.swift) - 代码示例
- [集成示例](Examples/IntegrationExample.swift) - SwiftUI 示例

## 💡 常见问题

### Q: 如何选择录制格式？
A: SDK 自动选择最佳格式（WAV PCM Float32），确保高质量录制。

### Q: 可以同时录制多个流吗？
A: 当前版本不支持同时录制多个流，这是 MVP 版本的限制。

### Q: 如何处理录制中断？
A: SDK 会自动处理中断，并通过 `onStatus` 回调通知状态变化。

### Q: 支持哪些音频设备？
A: 支持所有 macOS 兼容的音频输入设备，包括内置麦克风和外接设备。

