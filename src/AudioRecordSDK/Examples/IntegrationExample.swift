import Foundation
import SwiftUI

/// 在现有应用中集成 AudioRecord SDK 的示例
@available(macOS 14.4, *)
@MainActor
class AudioRecordSDKIntegration: ObservableObject {
    
    // MARK: - 属性
    @Published var isRecording = false
    @Published var audioLevel: Float = 0.0
    @Published var statusMessage = "准备就绪"
    @Published var lastRecording: AudioRecording?
    
    private let audioAPI = AudioAPI.shared
    private var currentStream: AudioStream?
    
    // MARK: - 初始化
    init() {
        setupSDKCallbacks()
    }
    
    // MARK: - 公开方法
    
    /// 开始麦克风录制
    func startMicrophoneRecording() async {
        do {
            statusMessage = "正在启动麦克风录制..."
            
            let constraints = createMicrophoneConstraints(
                echoCancellation: true,
                noiseSuppression: true
            )
            
            let stream = try await audioAPI.getUserMedia(constraints: constraints)
            currentStream = stream
            
            try audioAPI.startRecording(stream: stream)
            
            isRecording = true
            statusMessage = "麦克风录制中..."
            
        } catch AudioError.microphonePermissionDenied {
            statusMessage = "❌ 麦克风权限被拒绝"
        } catch AudioError.alreadyRecording {
            statusMessage = "⚠️ 录制已在进行中"
        } catch {
            statusMessage = "❌ 录制失败: \(error.localizedDescription)"
        }
    }
    
    /// 开始混音录制
    func startMixedRecording() async {
        do {
            statusMessage = "正在启动混音录制..."
            
            let constraints = createMixedAudioConstraints(
                echoCancellation: true,
                noiseSuppression: false  // 混音时可能不需要噪音抑制
            )
            
            let stream = try await audioAPI.getUserMedia(constraints: constraints)
            currentStream = stream
            
            try audioAPI.startRecording(stream: stream)
            
            isRecording = true
            statusMessage = "混音录制中 (麦克风 + 系统音频)..."
            
        } catch AudioError.microphonePermissionDenied {
            statusMessage = "❌ 麦克风权限被拒绝"
        } catch AudioError.systemAudioPermissionDenied {
            statusMessage = "❌ 系统音频权限被拒绝"
        } catch AudioError.alreadyRecording {
            statusMessage = "⚠️ 录制已在进行中"
        } catch {
            statusMessage = "❌ 混音录制失败: \(error.localizedDescription)"
        }
    }
    
    /// 停止录制
    func stopRecording() {
        audioAPI.stopRecording()
        currentStream = nil
        isRecording = false
        audioLevel = 0.0
        statusMessage = "录制已停止"
    }
    
    /// 获取当前流信息
    func getCurrentStreamInfo() -> String? {
        guard let stream = currentStream else { return nil }
        
        let tracks = stream.getAudioTracks()
        let trackInfo = tracks.map { track in
            "轨道: \(track.label) (状态: \(track.readyState == .live ? "活跃" : "结束"))"
        }.joined(separator: "\n")
        
        return """
        流ID: \(stream.id)
        录制模式: \(stream.recordingMode)
        流状态: \(stream.active ? "活跃" : "非活跃")
        轨道数量: \(tracks.count)
        \(trackInfo)
        """
    }
    
    // MARK: - 私有方法
    
    private func setupSDKCallbacks() {
        // 音频电平回调
        audioAPI.onLevel = { [weak self] level in
            Task { @MainActor in
                self?.audioLevel = level
            }
        }
        
        // 状态更新回调
        audioAPI.onStatus = { [weak self] status in
            Task { @MainActor in
                self?.statusMessage = status
            }
        }
        
        // 录制完成回调
        audioAPI.onRecordingComplete = { [weak self] recording in
            Task { @MainActor in
                self?.lastRecording = recording
                self?.statusMessage = "✅ 录制完成: \(recording.fileName)"
                self?.isRecording = false
                self?.audioLevel = 0.0
            }
        }
    }
}

// MARK: - SwiftUI 视图示例

@available(macOS 14.4, *)
struct AudioRecordSDKView: View {
    @StateObject private var recorder = AudioRecordSDKIntegration()
    
    var body: some View {
        VStack(spacing: 20) {
            // 标题
            Text("AudioRecord SDK 示例")
                .font(.title)
                .fontWeight(.bold)
            
            // 状态显示
            VStack(alignment: .leading, spacing: 10) {
                Text("状态: \(recorder.statusMessage)")
                    .foregroundColor(recorder.isRecording ? .green : .primary)
                
                // 音频电平显示
                if recorder.isRecording {
                    HStack {
                        Text("音频电平:")
                        ProgressView(value: Double(recorder.audioLevel), in: 0...1)
                            .progressViewStyle(LinearProgressViewStyle())
                        Text("\(Int(recorder.audioLevel * 100))%")
                    }
                }
                
                // 流信息
                if let streamInfo = recorder.getCurrentStreamInfo() {
                    Text("流信息:")
                        .font(.headline)
                    Text(streamInfo)
                        .font(.caption)
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.05))
            .cornerRadius(10)
            
            // 控制按钮
            HStack(spacing: 15) {
                Button("麦克风录制") {
                    Task {
                        await recorder.startMicrophoneRecording()
                    }
                }
                .disabled(recorder.isRecording)
                
                Button("混音录制") {
                    Task {
                        await recorder.startMixedRecording()
                    }
                }
                .disabled(recorder.isRecording)
                
                Button("停止录制") {
                    recorder.stopRecording()
                }
                .disabled(!recorder.isRecording)
                .foregroundColor(.red)
            }
            
            // 最后录制的文件信息
            if let recording = recorder.lastRecording {
                VStack(alignment: .leading, spacing: 5) {
                    Text("最后录制:")
                        .font(.headline)
                    Text("文件名: \(recording.fileName)")
                    Text("时长: \(recording.formattedDuration)")
                    Text("大小: \(recording.formattedFileSize)")
                    Text("模式: \(recording.recordingModeDisplayName)")
                    Text("创建时间: \(recording.formattedCreatedAt)")
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(10)
            }
            
            Spacer()
        }
        .padding()
        .frame(minWidth: 400, minHeight: 500)
    }
}

// MARK: - 预览

@available(macOS 14.4, *)
struct AudioRecordSDKView_Previews: PreviewProvider {
    static var previews: some View {
        AudioRecordSDKView()
    }
}
