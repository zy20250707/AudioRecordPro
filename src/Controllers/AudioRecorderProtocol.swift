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
@MainActor
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
    
    // MARK: - Initialization
    init(mode: AudioUtils.RecordingMode) {
        self.recordingMode = mode
        super.init()
        setupPlaybackEngine()
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
        let level = min(1.0, rms * 20.0) // Scale up for better visualization
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
        
        stopPlayback()
        
        do {
            let audioFile = try AVAudioFile(forReading: url)
            logger.info("播放文件创建成功")
            logger.info("音频时长: \(audioFile.length) 帧")
            logger.info("音频格式: \(audioFile.processingFormat.settings)")
            
            let duration = Double(audioFile.length) / audioFile.processingFormat.sampleRate
            logger.info("音频时长: \(String(format: "%.2f", duration)) 秒")
            
            playbackFile = audioFile
            playbackEngine.attach(playbackPlayerNode)
            playbackEngine.connect(playbackPlayerNode, to: playbackEngine.mainMixerNode, format: audioFile.processingFormat)
            
            try playbackEngine.start()
            logger.info("播放引擎重新启动")
            
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
            onStatus?(errorMsg)
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
    private func setupPlaybackEngine() {
        do {
            try playbackEngine.start()
            logger.info("播放引擎启动成功")
        } catch {
            logger.error("播放引擎启动失败: \(error.localizedDescription)")
        }
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
