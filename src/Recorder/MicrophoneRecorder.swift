import Foundation
import AVFoundation

/// 麦克风录制器
@MainActor
class MicrophoneRecorder: BaseAudioRecorder {
    
    // MARK: - Properties
    private let engine = AVAudioEngine()
    private let recordMixer = AVAudioMixerNode()
    private var mixerFormat: AVAudioFormat?
    private var totalFramesWritten: AVAudioFrameCount = 0
    private var lastStatsLogTime: TimeInterval = 0
    // 调试用：强制使用PCM(WAV)参数写入，验证输入链路（与输入buffer格式一致，避免编码干扰）
    private let forcePCMForDebug: Bool = true
    
    // MARK: - Initialization
    override init(mode: AudioUtils.RecordingMode) {
        super.init(mode: .microphone)
    }
    
    // MARK: - Recording Implementation
    override func startRecording() {
        guard !isRunning else {
            logger.warning("录制已在进行中")
            return
        }
        
        // 若使用PCM调试写入，强制使用 .wav 扩展名，避免后续读取/播放因扩展名与容器不符报错
        let targetExtension = forcePCMForDebug ? "wav" : currentFormat.fileExtension
        let url = fileManager.getRecordingFileURL(recordingMode: recordingMode, format: targetExtension)
        logger.info("开始录制，模式: \(recordingMode.rawValue), 格式: \(currentFormat.rawValue)")
        
        do {
            // 打印可用麦克风输入设备信息，帮助诊断“有缓冲但为静音”的情况
            logAvailableAudioInputDevices()

            // 1) 搭建图
            setupAudioEngine()
            
            // 2) 使用 inputNode 原生格式创建文件（最稳妥）
            let inputFormat = engine.inputNode.inputFormat(forBus: 0)
            try createAudioFileForInput(at: url, inputFormat: inputFormat)
            
            // 3) 在 inputNode 安装 tap（旁路抓取麦克风PCM）
            installMicrophoneRecordingTap()
            
            // 4) 启动引擎（确保节点实际输出格式稳定）
            try startAudioEngine()
            
            // Start monitoring
            levelMonitor.startMonitoring(source: .recording(engine: engine))
            
            isRunning = true
            onStatus?("正在录制麦克风...")
            
        } catch {
            let errorMsg = "录制启动失败: \(error.localizedDescription)"
            onStatus?(errorMsg)
            logger.error("麦克风录制启动失败: \(error.localizedDescription)")
            
            // Check for permission issues
            if error.localizedDescription.contains("permission") || 
               error.localizedDescription.contains("权限") ||
               error.localizedDescription.contains("denied") {
                onStatus?("需要麦克风权限才能录制，请在系统设置中允许")
            }
        }
    }
    
    override func stopRecording() {
        // Stop microphone recording specific components
        if isRunning {
            engine.inputNode.removeTap(onBus: 0)
            recordMixer.removeTap(onBus: 0)
            engine.stop()
            logger.info("麦克风录制引擎已停止")
        }
        
        // Call parent implementation
        super.stopRecording()
    }
    
    // MARK: - Private Methods
    private func setupAudioEngine() {
        engine.attach(recordMixer)
        
        let desiredSampleRate: Double = 48000
        let commonFormat = AVAudioCommonFormat.pcmFormatFloat32
        let mixerOutputFormat = AVAudioFormat(commonFormat: commonFormat, sampleRate: desiredSampleRate, channels: 2, interleaved: false)
        mixerFormat = mixerOutputFormat
        
        // Connect microphone input directly to main mixer，尽量简化拉流链路
        let input = engine.inputNode
        let inputFormat = getSafeInputFormat()
        logger.info("麦克风输入格式: \(inputFormat.settings)")
        logger.info("麦克风采样率: \(inputFormat.sampleRate), 声道数: \(inputFormat.channelCount)")
        
        // Use microphone's (safe) format 直连 mainMixerNode
        engine.connect(input, to: engine.mainMixerNode, format: inputFormat)
        logger.info("已连接麦克风输入到主混音器")
    }

    private func logAvailableAudioInputDevices() {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInMicrophone, .externalUnknown],
            mediaType: .audio,
            position: .unspecified
        )
        let audioDevices = session.devices
        if audioDevices.isEmpty {
            logger.warning("未发现音频输入设备（DiscoverySession.devices 为空）")
            return
        }
        logger.info("发现音频输入设备数量: \(audioDevices.count)")
        for (idx, dev) in audioDevices.enumerated() {
            logger.info("输入设备[\(idx)]: name=\(dev.localizedName), uniqueID=\(dev.uniqueID), connected=\(dev.isConnected)")
        }
        if let defaultDevice = AVCaptureDevice.default(for: .audio) {
            logger.info("默认音频输入设备: \(defaultDevice.localizedName) (\(defaultDevice.uniqueID))")
        } else {
            logger.warning("无法获取默认音频输入设备（AVCaptureDevice.default 为 nil）")
        }
    }
    
    override func createAudioFile(at url: URL, format: AudioUtils.AudioFormat) throws {
        // 录制时根据 inputNode 的原生格式创建
        let inputFormat = engine.inputNode.inputFormat(forBus: 0)
        try createAudioFileForInput(at: url, inputFormat: inputFormat)
    }

    private func createAudioFileForInput(at url: URL, inputFormat: AVAudioFormat) throws {
        let sampleRate = inputFormat.sampleRate
        let channels = Int(inputFormat.channelCount)
        let audioSettings: [String: Any]
        if forcePCMForDebug {
            // 与 input buffer 完全一致的 WAV(PCM Float32, non-interleaved)，避免格式不匹配导致的静音
            audioSettings = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channels,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: true
            ]
            logger.info("调试模式：使用WAV(PCM Float32)写入，rate=\(sampleRate), ch=\(channels)")
        } else {
            audioSettings = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channels,
                AVEncoderBitRateKey: 128000
            ]
            logger.info("麦克风录制使用AAC: rate=\(sampleRate), ch=\(channels)")
        }
        audioFile = try AVAudioFile(forWriting: url, settings: audioSettings)
        outputURL = url
        onStatus?("文件创建成功: \(url.lastPathComponent)")
        logger.info("麦克风录制文件创建成功: \(url.lastPathComponent)")
        logger.info("文件格式: \(audioFile?.processingFormat.settings ?? [:])")
    }
    
    private func installMicrophoneRecordingTap() {
        // 直接在 inputNode 上安装 tap（使用其安全格式抓取）
        let input = engine.inputNode
        let inputFormat = getSafeInputFormat()
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, time in
            guard let self = self, let file = self.audioFile else { return }
            
            // Write to audio file
            do {
                try file.write(from: buffer)
                self.totalFramesWritten += buffer.frameLength
            } catch {
                self.logger.error("写入麦克风音频失败: \(error.localizedDescription)")
            }
            
            // Calculate and update level
            let level = self.calculateRMSLevel(from: buffer)
            
            // Add debug info
            if level > 0.005 {
                self.logger.info("麦克风录制电平: \(String(format: "%.4f", level)), 帧数: \(buffer.frameLength), rate=\(buffer.format.sampleRate), ch=\(buffer.format.channelCount)")
            }
            
            // 统计日志：每秒打印一次累计帧数
            let now = CFAbsoluteTimeGetCurrent()
            if now - self.lastStatsLogTime > 1.0 {
                self.lastStatsLogTime = now
                self.logger.info("累计写入帧数: \(self.totalFramesWritten)")
            }
            Task { @MainActor in self.onLevel?(level) }
        }
        
        logger.info("麦克风录制监听已安装（inputNode）")
    }
    
    private func startAudioEngine() throws {
        // 为避免啸叫，主混音器音量保持很低但不为0以驱动pull
        engine.mainMixerNode.outputVolume = 0.01
        
        // 录制链路已将 input 直连 mainMixer，这里无需再接 recordMixer
        logger.info("麦克风链路：input -> mainMixer 建立")
        
        // 在主混音器安装一个空tap，强制驱动渲染循环
        let mainFmt = engine.mainMixerNode.outputFormat(forBus: 0)
        engine.mainMixerNode.removeTap(onBus: 0)
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: mainFmt) { _, _ in }
        engine.prepare()
        
        try engine.start()
        logger.info("麦克风录制引擎启动成功")
    }

    private func getSafeInputFormat() -> AVAudioFormat {
        let raw = engine.inputNode.inputFormat(forBus: 0)
        let sampleRate = raw.sampleRate
        let channels = raw.channelCount
        if sampleRate > 0, channels > 0 {
            return raw
        }
        // 回退：尝试主混音器输出格式
        let mixerFmt = engine.mainMixerNode.outputFormat(forBus: 0)
        if mixerFmt.sampleRate > 0, mixerFmt.channelCount > 0 {
            return mixerFmt
        }
        // 最终兜底：48k/单声道 Float32 非交织
        return AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 1, interleaved: false)!
    }
}
