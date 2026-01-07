import Foundation

/// AudioRecord SDK 基础使用示例
@MainActor
class AudioRecordSDKExample {
    
    private let audioAPI = AudioAPI.shared
    private var currentStream: AudioStream?
    
    // MARK: - 基础麦克风录制
    
    func startMicrophoneRecording() async {
        do {
            // 1. 创建麦克风约束
            let constraints = createMicrophoneConstraints(
                echoCancellation: true,
                noiseSuppression: true
            )
            
            // 2. 获取媒体流
            let stream = try await audioAPI.getUserMedia(constraints: constraints)
            currentStream = stream
            
            // 3. 设置回调
            setupCallbacks()
            
            // 4. 开始录制
            try audioAPI.startRecording(stream: stream)
            
            print("✅ 麦克风录制已开始")
            print("录制模式: \(stream.recordingMode)")
            print("轨道数量: \(stream.getAudioTracks().count)")
            
        } catch {
            print("❌ 麦克风录制失败: \(error.localizedDescription)")
        }
    }
    
    // MARK: - 混音录制
    
    func startMixedRecording() async {
        do {
            // 1. 创建混音约束
            let constraints = createMixedAudioConstraints(
                echoCancellation: true,
                noiseSuppression: true
            )
            
            // 2. 获取媒体流
            let stream = try await audioAPI.getUserMedia(constraints: constraints)
            currentStream = stream
            
            // 3. 设置回调
            setupCallbacks()
            
            // 4. 开始录制
            try audioAPI.startRecording(stream: stream)
            
            print("✅ 混音录制已开始 (麦克风 + 系统音频)")
            print("录制模式: \(stream.recordingMode)")
            print("轨道数量: \(stream.getAudioTracks().count)")
            
        } catch {
            print("❌ 混音录制失败: \(error.localizedDescription)")
        }
    }
    
    // MARK: - 停止录制
    
    func stopRecording() {
        audioAPI.stopRecording()
        currentStream = nil
        print("🛑 录制已停止")
    }
    
    // MARK: - 设置回调
    
    private func setupCallbacks() {
        audioAPI.onLevel = { level in
            print("🎵 音频电平: \(String(format: "%.2f", level))")
        }
        
        audioAPI.onStatus = { status in
            print("📊 状态更新: \(status)")
        }
        
        audioAPI.onRecordingComplete = { recording in
            print("✅ 录制完成:")
            print("  文件名: \(recording.fileName)")
            print("  时长: \(recording.formattedDuration)")
            print("  大小: \(recording.formattedFileSize)")
            print("  路径: \(recording.fileURL.path)")
        }
    }
    
    // MARK: - 检查状态
    
    func checkRecordingStatus() {
        print("录制状态: \(audioAPI.isRecording ? "录制中" : "未录制")")
        
        if let stream = currentStream {
            print("流状态: \(stream.active ? "活跃" : "非活跃")")
            print("流ID: \(stream.id)")
            
            let tracks = stream.getAudioTracks()
            for (index, track) in tracks.enumerated() {
                print("轨道 \(index + 1):")
                print("  ID: \(track.id)")
                print("  标签: \(track.label)")
                print("  启用: \(track.enabled)")
                print("  状态: \(track.readyState)")
            }
        }
    }
}

// MARK: - 使用示例

/*
使用方法:

let example = AudioRecordSDKExample()

// 麦克风录制
await example.startMicrophoneRecording()
await Task.sleep(nanoseconds: 5_000_000_000) // 录制 5 秒
example.stopRecording()

// 混音录制
await example.startMixedRecording()
await Task.sleep(nanoseconds: 10_000_000_000) // 录制 10 秒
example.stopRecording()

// 检查状态
example.checkRecordingStatus()

// 打印 SDK 信息
AudioRecordSDKInfo.printInfo()
*/
