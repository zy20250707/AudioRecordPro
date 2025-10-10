import Foundation
import AVFoundation
import CoreMedia
import ScreenCaptureKit

/// 系统音频录制器 (基于 ScreenCaptureKit)
@MainActor
class ScreenCaptureAudioRecorder: BaseAudioRecorder {
    
    // MARK: - Properties
    private var screenCaptureStream: SCStream?
    private var retryCount = 0
    private let screenFrameOutputQueue = DispatchQueue(label: "SCStream.screen.queue", qos: .utility)
    private let audioFrameOutputQueue = DispatchQueue(label: "SCStream.audio.queue", qos: .userInitiated)
    private var audioOutputRef: SystemAudioStreamOutput?
    private var videoOutputRef: MinimalVideoStreamOutput?
    private var isStopping = false
    
    // MARK: - Initialization
    override init(mode: AudioUtils.RecordingMode) {
        super.init(mode: .systemMixdown)
    }
    
    // MARK: - Recording Implementation
    override func startRecording() {
        guard !isRunning else {
            logger.warning("录制已在进行中")
            return
        }
        
        let url = fileManager.getRecordingFileURL(recordingMode: recordingMode, format: currentFormat.fileExtension)
        logger.info("开始录制，模式: \(recordingMode.rawValue), 格式: \(currentFormat.rawValue)")
        
        do {
            // Create audio file for system audio
            try createSystemAudioFile(at: url, format: currentFormat)
            
            // Start system audio capture
            startSystemAudioCapture()
            
            // Start monitoring
            levelMonitor.startMonitoring(source: .simulated)
            
            isRunning = true
            
        } catch {
            let errorMsg = "文件创建失败: \(error.localizedDescription)"
            onStatus?(errorMsg)
            logger.error("创建音频文件失败: \(error.localizedDescription)")
        }
    }
    
    override func stopRecording() {
        guard !isStopping else { return }
        isStopping = true
        
        if let stream = screenCaptureStream {
            Task { @MainActor in
                // 停止前移除输出，避免回调过程中访问已释放资源
                if let audioOut = self.audioOutputRef {
                    try? stream.removeStreamOutput(audioOut, type: .audio)
                }
                if let videoOut = self.videoOutputRef {
                    try? stream.removeStreamOutput(videoOut, type: .screen)
                }
                
                do {
                    try await stream.stopCapture()
                    self.logger.info("系统音频录制已停止")
                } catch {
                    self.logger.error("停止系统音频录制失败: \(error.localizedDescription)")
                }
                
                // 清理引用
                self.audioOutputRef = nil
                self.videoOutputRef = nil
                self.screenCaptureStream = nil
                
                // 再调用父类停止，统一生成录音记录与回调
                super.stopRecording()
                self.isStopping = false
            }
        } else {
            isStopping = false
            super.stopRecording()
        }
    }
    
    // MARK: - Private Methods
    private func createSystemAudioFile(at url: URL, format: AudioUtils.AudioFormat) throws {
        // Use 48000Hz sample rate (consistent with ScreenCaptureKit)
        var settings = format.settings
        settings[AVSampleRateKey] = 48000  // Match ScreenCaptureKit configuration
        
        audioFile = try AVAudioFile(forWriting: url, settings: settings)
        outputURL = url
        
        onStatus?("文件创建成功: \(url.lastPathComponent)")
        logger.info("系统音频文件创建成功: \(url.lastPathComponent)")
        logger.info("文件格式: \(audioFile?.processingFormat.settings ?? [:])")
    }
    
    private func startSystemAudioCapture() {
        logger.info("开始系统音频录制（使用ScreenCaptureKit）")
        
        // Check system version
        guard #available(macOS 12.3, *) else {
            onStatus?("系统版本不支持ScreenCaptureKit，需要macOS 12.3+")
            logger.error("系统版本不支持ScreenCaptureKit")
            return
        }
        
        logger.info("系统版本支持ScreenCaptureKit")
        
        // Check screen recording permission
        checkScreenRecordingPermission { [weak self] hasPermission in
            guard let self = self else { return }
            
            if !hasPermission {
                Task { @MainActor in
                    self.onStatus?("需要屏幕录制权限才能录制系统声音，请在系统设置中允许")
                }
                self.logger.error("屏幕录制权限不足")
                return
            }
            
            // Get shareable content
            Task { [weak self] in
                guard let self = self else { return }
                
                self.logger.info("开始获取可共享内容...")
                do {
                    // Add timeout handling
                    let content = try await withThrowingTaskGroup(of: SCShareableContent.self) { group in
                        group.addTask {
                            try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                        }
                        
                        group.addTask {
                            try await Task.sleep(nanoseconds: 10_000_000_000) // 10 second timeout
                            throw NSError(domain: "Timeout", code: -1, userInfo: [NSLocalizedDescriptionKey: "获取可共享内容超时"])
                        }
                        
                        let result = try await group.next()!
                        group.cancelAll()
                        return result
                    }
                    
                    self.logger.info("✅ 获取到可共享内容，显示器数量: \(content.displays.count)")
                    
                    // Check for available displays
                    guard let display = content.displays.first else {
                        self.logger.error("没有可用的显示器")
                        Task { @MainActor in
                            self.onStatus?("没有可用的显示器，无法录制系统音频")
                        }
                        return
                    }
                    
                    self.logger.info("使用显示器: \(display.displayID)")
                    
                    // 创建过滤器：按 WWDC 建议排除当前应用，避免镜像/反馈
                    let excludedApps = content.applications.filter { app in
                        Bundle.main.bundleIdentifier == app.bundleIdentifier
                    }
                    let filter = SCContentFilter(
                        display: display,
                        excludingApplications: excludedApps,
                        exceptingWindows: []
                    )
                    
                    // Configure stream - enable audio and video capture
                    let config = SCStreamConfiguration()
                    
                    // Audio configuration
                    config.capturesAudio = true
                    // 暂时不排除本进程音频，避免测试阶段误排除
                    config.excludesCurrentProcessAudio = false
                    config.sampleRate = 48000  // Use unified 48000Hz sample rate
                    config.channelCount = 2    // Stereo
                    
                    // Video configuration (needed to drive audio capture)
                    config.width = 320
                    config.height = 240
                    config.minimumFrameInterval = CMTime(value: 1, timescale: 60) // 60fps，与示例一致，保证音频驱动稳定
                    config.showsCursor = false
                    // 提高队列深度，避免高帧率下丢帧（与示例一致）
                    config.queueDepth = 5
                    
                    self.logger.info("SCStreamConfiguration设置完成 - 音频: \(config.capturesAudio), 尺寸: \(config.width)x\(config.height), 采样率: \(config.sampleRate)")
                    
                    // Create stream
                    do {
                        self.logger.info("正在创建SCStream...")
                        let stream = SCStream(filter: filter, configuration: config, delegate: self)
                        self.logger.info("SCStream创建成功")
                        
                        // Check delegate setup
                        self.logger.info("SCStream delegate已设置")
                        
                        // Add audio output
                        self.logger.info("正在添加音频输出...")
                        let audioOutput = SystemAudioStreamOutput(audioFile: self.audioFile, onLevel: self.onLevel)
                        do {
                            try stream.addStreamOutput(audioOutput, type: .audio, sampleHandlerQueue: audioFrameOutputQueue)
                            self.audioOutputRef = audioOutput
                            self.logger.info("✅ 音频输出添加成功")
                        } catch {
                            self.logger.error("❌ 音频输出添加失败: \(error.localizedDescription)")
                            throw error
                        }
                        
                        // Add video output (minimal processing, only to drive audio stream)
                        self.logger.info("正在添加视频输出...")
                        let videoOutput = MinimalVideoStreamOutput()
                        do {
                            try stream.addStreamOutput(videoOutput, type: .screen, sampleHandlerQueue: screenFrameOutputQueue)
                            self.videoOutputRef = videoOutput
                            self.logger.info("✅ 视频输出添加成功")
                        } catch {
                            self.logger.error("❌ 视频输出添加失败: \(error.localizedDescription)")
                            throw error
                        }
                        
                        // Add debug: check stream output types
                        self.logger.info("Stream输出类型检查: 已添加音频和视频输出处理器")
                        
                        // Add debug: check stream status
                        self.logger.info("Stream配置 - 音频捕获: \(config.capturesAudio), 采样率: \(config.sampleRate)")
                        
                        self.screenCaptureStream = stream
                        self.logger.info("screenCaptureStream已设置")
                        
                        // Start capture
                        self.logger.info("准备开始捕获，stream对象: \(stream)")
                        do {
                            try await stream.startCapture()
                            self.logger.info("系统音频录制启动成功")
                            
                            // Post-startup status check
                            self.logger.info("启动后Stream状态检查完成")
                            
                            // Add delayed check to see if there's data flow
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                self.logger.info("2秒后检查：Stream对象: \(stream)")
                                self.logger.info("2秒后检查：Stream配置: \(config)")
                                
                                // Try playing test audio to verify audio capture
                                self.logger.info("尝试播放测试音频来验证音频捕获...")
                                NSSound.beep()
                            }
                            
                            Task { @MainActor in
                                self.onStatus?("系统音频录制已开始")
                            }
                        } catch {
                            self.logger.error("系统音频录制启动失败: \(error.localizedDescription)")
                            self.logger.error("错误详情: \(error)")
                            
                            Task { @MainActor in
                                self.onStatus?("系统音频录制启动失败: \(error.localizedDescription)")
                                
                                // Check if it's a permission issue
                                if error.localizedDescription.contains("permission") || 
                                   error.localizedDescription.contains("权限") ||
                                   error.localizedDescription.contains("denied") {
                                    self.onStatus?("需要屏幕录制权限才能录制系统声音，请在系统设置中允许")
                                }
                            }
                        }
                        
                    } catch {
                        self.onStatus?("创建系统音频流失败: \(error.localizedDescription)")
                        self.logger.error("创建系统音频流失败: \(error.localizedDescription)")
                    }
                    
                } catch {
                    self.onStatus?("获取系统音频失败: \(error.localizedDescription)")
                    self.logger.error("获取可共享内容失败: \(error.localizedDescription)")
                }
            }
        }
    }
    
    /// Check screen recording permission
    private func checkScreenRecordingPermission(completion: @escaping (Bool) -> Void) {
        // Try to get shareable content to check permission
        Task {
            do {
                let _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                // Able to get content means permission is normal
                completion(true)
            } catch {
                // Check if it's a permission error
                if error.localizedDescription.contains("permission") || 
                   error.localizedDescription.contains("权限") ||
                   error.localizedDescription.contains("denied") {
                    completion(false)
                } else {
                    // Other errors, permission might be fine
                    completion(true)
                }
            }
        }
    }
}

// MARK: - SCStreamDelegate
extension ScreenCaptureAudioRecorder: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in
            self.logger.error("SCStream停止，错误: \(error.localizedDescription)")
            self.isRunning = false
            self.onStatus?("系统音频录制意外停止: \(error.localizedDescription)")
        }
    }
}

// MARK: - MinimalVideoStreamOutput
class MinimalVideoStreamOutput: NSObject, SCStreamOutput {
    private let logger = Logger.shared
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        // Minimal processing, only to drive audio stream
        if type == .screen {
            // Don't process video data, just log receipt
            logger.info("📺 收到视频数据，帧数: \(CMSampleBufferGetNumSamples(sampleBuffer))")
        }
    }
}

// MARK: - SystemAudioStreamOutput
class SystemAudioStreamOutput: NSObject, SCStreamOutput {
    private weak var audioFile: AVAudioFile?
    private let onLevel: ((Float) -> Void)?
    private let logger = Logger.shared
    private var audioDataReceived = false
    private var audioDataTimer: Timer?
    
    init(audioFile: AVAudioFile?, onLevel: ((Float) -> Void)?) {
        self.audioFile = audioFile
        self.onLevel = onLevel
        super.init()
        
        // Start timer on main thread to detect audio data reception
        DispatchQueue.main.async {
            self.audioDataTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                if !self.audioDataReceived {
                    self.logger.warning("⚠️ 5秒内未接收到任何音频数据，可能系统没有播放音频或权限问题")
                }
            }
        }
    }
    
    deinit {
        audioDataTimer?.invalidate()
    }
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        logger.info("🎵 SystemAudioStreamOutput收到数据，类型: \(type)")
        
        guard sampleBuffer.isValid else { return }
        guard type == .audio else { 
            logger.info("忽略非音频数据，类型: \(type)")
            return 
        }
        
        // Mark that audio data has been received
        audioDataReceived = true
        
        // Add detailed audio data debug info
        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        let duration = CMTimeGetSeconds(CMSampleBufferGetDuration(sampleBuffer))
        logger.info("🎵 音频样本缓冲区 - 帧数: \(frameCount), 时长: \(duration)秒")
        
        logger.info("🎵 处理音频样本缓冲区，帧数: \(CMSampleBufferGetNumSamples(sampleBuffer))")
        
        // Process audio sample buffer
        guard let audioFile = audioFile else { 
            logger.error("audioFile为nil")
            return 
        }
        
        // Convert CMSampleBuffer to AVAudioPCMBuffer
        if let audioBuffer = convertToAudioBuffer(from: sampleBuffer) {
            do {
                try audioFile.write(from: audioBuffer)
                
                // Calculate level
                let level = calculateRMSLevel(from: audioBuffer)
                
                // Add debug info
                if level > 0.01 { // Only print when there's significant level
                    logger.info("系统音频录制电平: \(String(format: "%.3f", level)), 帧数: \(audioBuffer.frameLength)")
                }
                
                // Update level display in real-time
                DispatchQueue.main.async {
                    self.onLevel?(level)
                }
                
            } catch {
                logger.error("写入系统音频失败: \(error.localizedDescription)")
            }
        } else {
            // Even if conversion fails, try to calculate level from raw audio data
            let level = calculateLevelFromSampleBuffer(sampleBuffer)
            Task { @MainActor in
                self.onLevel?(level)
            }
        }
    }
    
    private func convertToAudioBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            logger.error("无法获取格式描述")
            return nil
        }
        
        guard let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            logger.error("无法获取音频流基本描述")
            return nil
        }
        
        guard let format = AVAudioFormat(streamDescription: asbd) else {
            logger.error("无法创建AVAudioFormat")
            return nil
        }
        
        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else {
            logger.error("无法创建PCM缓冲区")
            return nil
        }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        
        // 使用系统 API 直接将 PCM 数据拷贝到 AudioBufferList，避免手动指针处理导致静音
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(sampleBuffer,
                                                                 at: 0,
                                                                 frameCount: Int32(frameCount),
                                                                 into: buffer.mutableAudioBufferList)
        if status != noErr {
            logger.error("CMSampleBuffer 拷贝到 AudioBufferList 失败: \(status)")
            return nil
        }
        return buffer
    }
    
    private func calculateRMSLevel(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0.0 }
        let frameCount = Int(buffer.frameLength)
        
        guard frameCount > 0 else { return 0.0 }
        
        var sum: Float = 0.0
        for i in 0..<frameCount {
            let sample = channelData[i]
            sum += sample * sample
        }
        
        let rms = sqrt(sum / Float(frameCount))
        return min(1.0, rms * 20.0)
    }
    
    private func calculateLevelFromSampleBuffer(_ sampleBuffer: CMSampleBuffer) -> Float {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return 0.0 }
        
        var length: Int = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)
        
        guard status == noErr, let data = dataPointer, length > 0 else { return 0.0 }
        
        // Simplified calculation assuming 16-bit samples
        let sampleCount = length / MemoryLayout<Int16>.size
        let rawPtr = UnsafeMutableRawPointer(data)
        let samples = rawPtr.bindMemory(to: Int16.self, capacity: sampleCount)
        
        var sum: Float = 0.0
        for i in 0..<sampleCount {
            let sample = Float(samples[i]) / Float(Int16.max)
            sum += sample * sample
        }
        
        let rms = sqrt(sum / Float(sampleCount))
        return min(1.0, rms * 20.0)
    }
}