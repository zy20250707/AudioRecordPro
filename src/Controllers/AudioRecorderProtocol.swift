import Foundation
import AVFoundation

/// 音频录制器协议
@MainActor
protocol AudioRecorderProtocol: AnyObject {
    
    // MARK: - Properties
    var isRunning: Bool { get }
    var recordingMode: AudioUtils.RecordingMode { get }
    var currentFormat: AudioUtils.AudioFormat { get }
    
    // MARK: - Callbacks
    var onLevel: ((Float) -> Void)? { get set }
    var onStatus: ((String) -> Void)? { get set }
    var onRecordingComplete: ((AudioRecording) -> Void)? { get set }
    var onPlaybackComplete: (() -> Void)? { get set }
    
    // MARK: - Recording Methods
    func startRecording()
    func stopRecording()
    
    // MARK: - Playback Methods
    func playRecording(at url: URL)
    func stopPlayback()
    
    // MARK: - Configuration Methods
    func setAudioFormat(_ format: AudioUtils.AudioFormat)
}

/// 音频录制器基础类
class BaseAudioRecorder: NSObject, AudioRecorderProtocol {
    
    // MARK: - Properties
    var isRunning = false
    let recordingMode: AudioUtils.RecordingMode
    private(set) var currentFormat: AudioUtils.AudioFormat = .m4a
    
    // Protected properties for subclasses
    var audioFile: AVAudioFile?
    var outputURL: URL?
    
    // Playback
    private var player: AVAudioPlayer?
    private let playbackEngine = AVAudioEngine()
    private let playbackPlayerNode = AVAudioPlayerNode()
    private var playbackFile: AVAudioFile?
    
    // Dependencies
    let logger = Logger.shared
    let fileManager = FileManagerUtils.shared
    let levelMonitor = LevelMonitor()
    
    // MARK: - Callbacks
    var onLevel: ((Float) -> Void)?
    var onStatus: ((String) -> Void)?
    var onRecordingComplete: ((AudioRecording) -> Void)?
    var onPlaybackComplete: (() -> Void)?
    
    // MARK: - Main Thread Callback Helpers
    @MainActor
    func callOnStatus(_ message: String) {
        onStatus?(message)
    }
    
    @MainActor
    func callOnLevel(_ level: Float) {
        onLevel?(level)
    }
    
    @MainActor
    func callOnRecordingComplete(_ recording: AudioRecording) {
        onRecordingComplete?(recording)
    }
    
    @MainActor
    func callOnPlaybackComplete() {
        onPlaybackComplete?()
    }
    
    // MARK: - Initialization
    init(mode: AudioUtils.RecordingMode) {
        self.recordingMode = mode
        super.init()
        // 不在初始化时设置播放引擎，只在需要时设置
    }
    
    // MARK: - Abstract Methods (to be overridden)
    func startRecording() {
        fatalError("Subclasses must implement startRecording()")
    }
    
    func stopRecording() {
        guard isRunning else {
            logger.warning("没有正在进行的录制")
            return
        }
        
        isRunning = false
        levelMonitor.stopMonitoring()
        
        // Close audio file
        audioFile = nil
        
        // Create recording record
        if let url = outputURL {
            createAudioRecording(from: url)
        }
        
        logger.info("录制已成功停止")
        onStatus?("录制已停止")
    }
    
    // MARK: - Configuration
    func setAudioFormat(_ format: AudioUtils.AudioFormat) {
        currentFormat = format
        logger.info("音频格式已设置为: \(format.rawValue)")
    }
    
    // MARK: - Shared Methods
    func createAudioFile(at url: URL, format: AudioUtils.AudioFormat) throws {
        let settings = format.settings
        audioFile = try AVAudioFile(forWriting: url, settings: settings)
        outputURL = url
        
        onStatus?("文件创建成功: \(url.lastPathComponent)")
        logger.info("音频文件创建成功: \(url.lastPathComponent)")
        logger.info("文件格式: \(audioFile?.processingFormat.settings ?? [:])")
    }
    
    /// 创建音频文件（支持沙盒环境）
    func createAudioFileWithSandboxSupport(format: AudioUtils.AudioFormat, completion: @escaping (Result<URL, Error>) -> Void) {
        // 首先尝试使用默认目录
        let defaultURL = fileManager.getRecordingFileURL(format: format.fileExtension)
        
        do {
            try createAudioFile(at: defaultURL, format: format)
            completion(.success(defaultURL))
        } catch {
            logger.warning("无法在默认目录创建文件，请求 Documents 目录访问权限: \(error.localizedDescription)")
            
            // 如果默认目录失败，请求 Documents 目录访问权限
            fileManager.requestDocumentsAccess { [weak self] granted in
                guard let self = self else { return }
                
                if granted {
                    // 重新尝试创建文件
                    do {
                        try self.createAudioFile(at: defaultURL, format: format)
                        completion(.success(defaultURL))
                    } catch {
                        completion(.failure(error))
                    }
                } else {
                    completion(.failure(NSError(domain: "AudioRecorder", code: -1, userInfo: [NSLocalizedDescriptionKey: "用户拒绝了 Documents 目录访问权限"])))
                }
            }
        }
    }
    
    /// 创建音频文件（支持沙盒环境，使用自定义设置）
    func createAudioFileWithSandboxSupportAndSettings(settings: [String: Any], completion: @escaping (Result<URL, Error>) -> Void) {
        // 生成文件名（使用PCM格式）
        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let fileName = "record_\(timestamp).wav"
        let defaultURL = fileManager.getRecordingFileURL(format: "wav")
        
        do {
            // 强制使用标准PCM格式，避免Apple的FLLR块
            var standardSettings = settings
            standardSettings[AVFormatIDKey] = kAudioFormatLinearPCM
            standardSettings[AVLinearPCMIsNonInterleaved] = false  // 强制交错格式
            
            // 使用标准格式创建，确保兼容性
            let standardFormat = AVAudioFormat(standardFormatWithSampleRate: standardSettings[AVSampleRateKey] as! Double, channels: standardSettings[AVNumberOfChannelsKey] as! AVAudioChannelCount)!
            audioFile = try AVAudioFile(forWriting: defaultURL, settings: standardSettings, commonFormat: standardFormat.commonFormat, interleaved: true)
            outputURL = defaultURL
            
            onStatus?("文件创建成功: \(fileName)")
            logger.info("音频文件创建成功: \(fileName)")
            logger.info("文件格式: \(settings)")
            completion(.success(defaultURL))
        } catch {
            logger.warning("无法在默认目录创建文件，请求 Documents 目录访问权限: \(error.localizedDescription)")
            
            // 如果默认目录失败，请求 Documents 目录访问权限
            fileManager.requestDocumentsAccess { [weak self] granted in
                guard let self = self else { return }
                
                if granted {
                    // 重新尝试创建文件
                    do {
                        self.audioFile = try AVAudioFile(forWriting: defaultURL, settings: settings)
                        self.outputURL = defaultURL
                        
                        self.onStatus?("文件创建成功: \(fileName)")
                        self.logger.info("音频文件创建成功: \(fileName)")
                        self.logger.info("文件格式: \(settings)")
                        completion(.success(defaultURL))
                    } catch {
                        self.logger.error("重新创建文件失败: \(error.localizedDescription)")
                        completion(.failure(error))
                    }
                } else {
                    self.logger.error("Documents 目录访问权限被拒绝")
                    completion(.failure(NSError(domain: "AudioRecorder", code: -1, userInfo: [NSLocalizedDescriptionKey: "Documents 目录访问权限被拒绝"])))
                }
            }
        }
    }
    
    func calculateRMSLevel(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0.0 }
        let frameCount = Int(buffer.frameLength)
        
        guard frameCount > 0 else { return 0.0 }
        
        // Calculate RMS level
        var sum: Float = 0.0
        for i in 0..<frameCount {
            let sample = channelData[i]
            sum += sample * sample
        }
        
        let rms = sqrt(sum / Float(frameCount))
        // 适中灵敏度：放大约×30；不设置地板，交由视图的噪声门处理
        let scaled = rms * 30.0
        let level = max(0.0, min(1.0, scaled))
        return level
    }
    
    func createAudioRecording(from url: URL) {
        guard let fileSize = fileManager.getFileSize(at: url) else {
            logger.error("无法获取文件大小")
            return
        }
        
        // Get audio file info
        var duration: TimeInterval = 0
        var sampleRate: Double = 48000
        var channels: Int = 2
        
        if let audioInfo = AudioUtils.shared.getAudioFileInfo(at: url) {
            duration = audioInfo.duration
            sampleRate = audioInfo.sampleRate
            channels = Int(audioInfo.channels)
        }
        
        let recording = AudioRecording(
            fileURL: url,
            duration: duration,
            fileSize: fileSize,
            format: currentFormat.rawValue,
            recordingMode: recordingMode.rawValue,
            sampleRate: sampleRate,
            channels: channels
        )
        
        logger.info("音频录音已创建: \(recording.fileName), 时长: \(recording.formattedDuration), 大小: \(recording.formattedFileSize)")
        onRecordingComplete?(recording)
    }
    
    // MARK: - Playback Methods
    func playRecording(at url: URL) {
        logger.info("正在播放录音: \(url.lastPathComponent)")
        logger.info("文件路径: \(url.path)")
        logger.info("文件是否存在: \(fileManager.fileExists(at: url))")
        
        // 确保播放引擎准备就绪
        ensurePlaybackEngineReady()
        
        stopPlayback()
        
        do {
            // 先尝试自动检测文件格式
            let audioFile = try AVAudioFile(forReading: url)
            logger.info("播放文件创建成功")
            logger.info("音频时长: \(audioFile.length) 帧")
            logger.info("音频格式: \(audioFile.processingFormat.settings)")
            
            let duration = Double(audioFile.length) / audioFile.processingFormat.sampleRate
            logger.info("音频时长: \(String(format: "%.2f", duration)) 秒")
            
            // 如果时长为0，尝试使用不同的格式重新读取
            if duration == 0.0 {
                logger.warning("检测到音频时长为0，尝试使用不同格式重新读取")
                
                // 尝试非交错格式
                let nonInterleavedFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44100, channels: 2, interleaved: false)
                if let nonInterleavedFormat = nonInterleavedFormat {
                    do {
                        let retryAudioFile = try AVAudioFile(forReading: url, commonFormat: nonInterleavedFormat.commonFormat, interleaved: nonInterleavedFormat.isInterleaved)
                        let retryDuration = Double(retryAudioFile.length) / retryAudioFile.processingFormat.sampleRate
                        logger.info("使用非交错格式重新读取成功，时长: \(String(format: "%.2f", retryDuration)) 秒")
                        
                        if retryDuration > 0.0 {
                            // 使用重新读取的文件
                            playbackFile = retryAudioFile
                            return
                        }
                    } catch {
                        logger.warning("使用非交错格式重新读取失败: \(error.localizedDescription)")
                    }
                }
                
                // 尝试交错格式
                let interleavedFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44100, channels: 2, interleaved: true)
                if let interleavedFormat = interleavedFormat {
                    do {
                        let retryAudioFile = try AVAudioFile(forReading: url, commonFormat: interleavedFormat.commonFormat, interleaved: interleavedFormat.isInterleaved)
                        let retryDuration = Double(retryAudioFile.length) / retryAudioFile.processingFormat.sampleRate
                        logger.info("使用交错格式重新读取成功，时长: \(String(format: "%.2f", retryDuration)) 秒")
                        
                        if retryDuration > 0.0 {
                            // 使用重新读取的文件
                            playbackFile = retryAudioFile
                            return
                        }
                    } catch {
                        logger.warning("使用交错格式重新读取失败: \(error.localizedDescription)")
                    }
                }
            }
            
            playbackFile = audioFile
            
            // 确保引擎停止后重新配置
            if playbackEngine.isRunning {
                playbackEngine.stop()
            }
            
            // 重新配置播放节点
            if playbackEngine.attachedNodes.contains(playbackPlayerNode) {
                playbackEngine.detach(playbackPlayerNode)
            }
            
            playbackEngine.attach(playbackPlayerNode)
            playbackEngine.connect(playbackPlayerNode, to: playbackEngine.mainMixerNode, format: audioFile.processingFormat)
            
            try playbackEngine.start()
            logger.info("播放引擎启动成功")
            
            installPlaybackLevelTap()
            
            playbackPlayerNode.scheduleFile(audioFile, at: nil) { [weak self] in
                Task { @MainActor in
                    self?.logger.info("播放完成回调被调用")
                    self?.levelMonitor.stopMonitoring()
                    self?.onPlaybackComplete?()
                }
            }
            
            playbackPlayerNode.play()
            levelMonitor.startMonitoring(source: .playback(player: AVAudioPlayer()))
            
            logger.info("播放启动成功，时长: \(String(format: "%.2f", duration)) 秒")
            
        } catch {
            let errorMsg = "播放失败: \(error.localizedDescription)"
            Task { @MainActor in
                self.callOnStatus(errorMsg)
            }
            logger.error("播放失败: \(error.localizedDescription)")
        }
    }
    
    func stopPlayback() {
        logger.info("停止播放")
        levelMonitor.stopMonitoring()
        
        playbackPlayerNode.stop()
        
        if playbackEngine.isRunning {
            playbackEngine.stop()
            logger.info("播放引擎已停止")
        }
        
        // Remove nodes
        if playbackEngine.attachedNodes.contains(playbackPlayerNode) {
            playbackEngine.detach(playbackPlayerNode)
        }
    }
    
    // MARK: - Private Methods
    private func ensurePlaybackEngineReady() {
        // 只在需要播放时才配置和启动引擎
        logger.info("播放引擎按需准备")
    }
    
    private func installPlaybackLevelTap() {
        guard let playbackFile = playbackFile else { return }
        
        let format = playbackFile.processingFormat
        logger.info("播放引擎格式: \(format.settings)")
        
        playbackPlayerNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, time in
            guard let self = self else { return }
            
            let level = self.calculateRMSLevel(from: buffer)
            
            if level > 0.01 {
                self.logger.info("播放电平: \(String(format: "%.3f", level)), 帧数: \(buffer.frameLength)")
            }
            
            Task { @MainActor in
                self.onLevel?(level)
            }
        }
        
        logger.info("播放电平监听已安装")
    }
}

// MARK: - AVAudioPlayerDelegate
extension BaseAudioRecorder: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.logger.info("播放完成: \(flag)")
            self.levelMonitor.stopMonitoring()
            self.onPlaybackComplete?()
        }
    }
}
