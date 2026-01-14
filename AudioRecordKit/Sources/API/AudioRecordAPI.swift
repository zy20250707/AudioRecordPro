import Foundation
import AVFoundation

/// 音频录制 API - SDK 核心类
@available(macOS 14.4, *)
@MainActor
public class AudioRecordAPI {
    
    // MARK: - 单例
    public static let shared = AudioRecordAPI()
    private init() {}
    
    // MARK: - 私有属性
    private var currentRecorder: AudioRecorderProtocol?
    private let logger = Logger.shared
    
    // MARK: - 公开属性
    public var isRecording: Bool {
        return currentRecorder?.isRunning ?? false
    }
    
    // MARK: - 权限通过 PermissionManager 统一管理
    
    // MARK: - 回调
    public var onLevel: ((Float) -> Void)?
    public var onStatus: ((String) -> Void)?
    public var onRecordingComplete: ((AudioRecording) -> Void)?
    
    // MARK: - 核心 API
    
    /// 获取媒体流
    /// - Parameter constraints: 音频约束
    /// - Returns: 媒体流对象
    public func getUserMedia(constraints: AudioConstraints) async throws -> MediaStream {
        
        // 检查权限
        try await checkPermissions(for: constraints)
        
        // 创建对应的录制器
        let recorder = try createRecorder(for: constraints)
        
        // 创建媒体流
        let stream = MediaStream(recorder: recorder, constraints: constraints)
        
        return stream
    }
    
    /// 开始录制
    /// - Parameter stream: 媒体流
    public func startRecording(stream: MediaStream) throws {
        guard !isRecording else {
            throw AudioRecordError.alreadyRecording
        }
        
        currentRecorder = stream.recorder
        setupRecorderCallbacks()
        currentRecorder?.startRecording()
    }
    
    /// 停止录制
    public func stopRecording() {
        currentRecorder?.stopRecording()
        currentRecorder = nil
    }
    
    // MARK: - 私有方法
    
    private func checkPermissions(for constraints: AudioConstraints) async throws {
        // 麦克风权限（只检查，不弹窗）
        let micStatus = PermissionManager.shared.getMicrophonePermissionStatus()
        switch micStatus {
        case .granted:
            break
        case .notDetermined:
            // 需要时再申请（会弹窗）
            let granted = await PermissionManager.shared.requestMicrophonePermissionAsync()
            guard granted else { throw AudioRecordError.microphonePermissionDenied }
        case .denied, .restricted:
            throw AudioRecordError.microphonePermissionDenied
        }
        
        // 如果需要系统音频，预留检查/申请入口
        if constraints.includeSystemAudio {
            logger.info("需要系统音频权限")
            // 系统音频捕获权限（如有 TCC 能力，可在此调用 PermissionManager）
            // let status = PermissionManager.shared.preflightSystemAudioCapture() // 示例
        }
    }
    
    private func createRecorder(for constraints: AudioConstraints) throws -> AudioRecorderProtocol {
        if constraints.includeSystemAudio {
            // 创建混音录制器
            let recorder = MixedAudioRecorder(mode: .systemMixdown)
            return recorder
        } else {
            // 创建麦克风录制器
            let recorder = MicrophoneRecorder(mode: .microphone)
            return recorder
        }
    }
    
    private func setupRecorderCallbacks() {
        currentRecorder?.onLevel = { [weak self] level in
            self?.onLevel?(level)
        }
        
        currentRecorder?.onStatus = { [weak self] status in
            self?.onStatus?(status)
        }
        
        currentRecorder?.onRecordingComplete = { [weak self] recording in
            self?.onRecordingComplete?(recording)
        }
    }
}
