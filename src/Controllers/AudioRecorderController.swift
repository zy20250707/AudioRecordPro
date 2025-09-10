import Foundation
import AVFoundation
import Cocoa
import Accelerate
import ScreenCaptureKit

// MARK: - Protocol Definition

/// 音频录制器协议
@MainActor
protocol AudioRecorderProtocol: AnyObject {
    var isRunning: Bool { get }
    var recordingMode: AudioUtils.RecordingMode { get }
    var currentFormat: AudioUtils.AudioFormat { get }
    
    var onLevel: ((Float) -> Void)? { get set }
    var onStatus: ((String) -> Void)? { get set }
    var onRecordingComplete: ((AudioRecording) -> Void)? { get set }
    var onPlaybackComplete: (() -> Void)? { get set }
    
    func startRecording()
    func stopRecording()
    func playRecording(at url: URL)
    func stopPlayback()
    func setAudioFormat(_ format: AudioUtils.AudioFormat)
}

// MARK: - Base Recorder Class

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
        // 延迟播放引擎初始化，避免阻塞界面启动
    }
    
    // MARK: - Abstract Methods
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
        audioFile = nil
        
        if let url = outputURL {
            createAudioRecording(from: url)
        }
        
        logger.info("录制已成功停止")
        onStatus?("录制已停止")
    }
    
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
    }
    
    func calculateRMSLevel(from buffer: AVAudioPCMBuffer) -> Float {
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
    
    func createAudioRecording(from url: URL) {
        guard let fileSize = fileManager.getFileSize(at: url) else {
            logger.error("无法获取文件大小")
            return
        }
        
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
        
        logger.info("音频录音已创建: \(recording.fileName)")
        onRecordingComplete?(recording)
    }
    
    // MARK: - Playback Methods
    func playRecording(at url: URL) {
        logger.info("正在播放录音: \(url.lastPathComponent)")
        stopPlayback()
        
        do {
            let audioFile = try AVAudioFile(forReading: url)
            let duration = Double(audioFile.length) / audioFile.processingFormat.sampleRate
            onStatus?("正在播放")
            onStatus?("路径: \(url.path)")
            
            playbackFile = audioFile
            // 重新构建图：先确保未附加，再附加并连接
            if playbackEngine.attachedNodes.contains(playbackPlayerNode) {
                playbackEngine.detach(playbackPlayerNode)
            }
            playbackEngine.attach(playbackPlayerNode)
            playbackEngine.connect(playbackPlayerNode, to: playbackEngine.mainMixerNode, format: audioFile.processingFormat)
            
            // 确保安装用于电平监控的 tap（安装在主混音器，避免对输出有影响）
            playbackEngine.mainMixerNode.removeTap(onBus: 0)
            playbackEngine.mainMixerNode.installTap(onBus: 0, bufferSize: 4096, format: nil) { [weak self] buffer, _ in
                guard let self = self else { return }
                let level = self.calculateRMSLevel(from: buffer)
                if level > 0.01 {
                    self.logger.info("播放电平: \(String(format: "%.3f", level))")
                }
                Task { @MainActor in
                    self.onLevel?(level)
                }
            }

            try playbackEngine.start()
            
            playbackPlayerNode.scheduleFile(audioFile, at: nil) { [weak self] in
                Task { @MainActor in
                    // 播放完成，移除 tap 并停止电平监控
                    self?.playbackEngine.mainMixerNode.removeTap(onBus: 0)
                    self?.levelMonitor.stopMonitoring()
                    self?.onPlaybackComplete?()
                }
            }
            
            playbackPlayerNode.play()
            levelMonitor.startMonitoring(source: .playback(player: AVAudioPlayer()))
            
            logger.info("播放启动成功，时长: \(String(format: "%.2f", duration)) 秒")
            
        } catch {
            onStatus?("播放失败: \(error.localizedDescription)")
            logger.error("播放失败: \(error.localizedDescription)")
        }
    }
    
    func stopPlayback() {
        logger.info("停止播放")
        levelMonitor.stopMonitoring()
        playbackPlayerNode.stop()
        
        if playbackEngine.isRunning {
            playbackEngine.stop()
        }
        
        // 移除电平 tap，防止重复安装或资源泄漏
        playbackEngine.mainMixerNode.removeTap(onBus: 0)

        if playbackEngine.attachedNodes.contains(playbackPlayerNode) {
            playbackEngine.detach(playbackPlayerNode)
        }
        playbackEngine.reset()
    }
    
    private func setupPlaybackEngine() {
        // 保留占位：不在此处启动，引擎启动应在连接完成后进行
        playbackEngine.reset()
        logger.info("播放引擎已重置，等待连接节点后启动")
    }
}

// MARK: - Microphone Recorder

/// 麦克风录制器
@MainActor
class MicrophoneRecorder: BaseAudioRecorder {
    
    private let engine = AVAudioEngine()
    private let recordMixer = AVAudioMixerNode()
    private var mixerFormat: AVAudioFormat?
    
    override init(mode: AudioUtils.RecordingMode) {
        super.init(mode: .microphone)
    }
    
    override func startRecording() {
        guard !isRunning else {
            logger.warning("录制已在进行中")
            return
        }
        
        let url = fileManager.getRecordingFileURL(format: currentFormat.fileExtension)
        logger.info("开始麦克风录制")
        
        do {
            try createMicrophoneAudioFile(at: url)
            setupMicrophoneEngine()
            try startMicrophoneEngine()
            installMicrophoneTap()
            
            levelMonitor.startMonitoring(source: .recording(engine: engine))
            isRunning = true
            onStatus?("正在录制麦克风...")
            
        } catch {
            onStatus?("麦克风录制启动失败: \(error.localizedDescription)")
            logger.error("麦克风录制启动失败: \(error.localizedDescription)")
        }
    }
    
    override func stopRecording() {
        if isRunning {
            engine.inputNode.removeTap(onBus: 0)
            recordMixer.removeTap(onBus: 0)
            engine.stop()
            logger.info("麦克风录制引擎已停止")
        }
        super.stopRecording()
    }
    
    private func createMicrophoneAudioFile(at url: URL) throws {
        // 统一为48kHz/双声道AAC，避免与tap缓冲区格式不一致
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128000
        ]
        
        audioFile = try AVAudioFile(forWriting: url, settings: audioSettings)
        outputURL = url
        onStatus?("文件创建成功: \(url.lastPathComponent)")
        logger.info("麦克风录制文件创建成功，设置: \(audioSettings)")
    }
    
    private func setupMicrophoneEngine() {
        engine.attach(recordMixer)
        
        let desiredSampleRate: Double = 48000
        let commonFormat = AVAudioCommonFormat.pcmFormatFloat32
        mixerFormat = AVAudioFormat(commonFormat: commonFormat, sampleRate: desiredSampleRate, channels: 2, interleaved: false)
        
        let input = engine.inputNode
        let inputFormat = input.inputFormat(forBus: 0)
        logger.info("输入节点格式: rate=\(inputFormat.sampleRate), channels=\(inputFormat.channelCount), isInterleaved=\(inputFormat.isInterleaved)")
        engine.connect(input, to: recordMixer, format: inputFormat)
        logger.info("已连接麦克风输入到混音器，目标混音格式: rate=\(desiredSampleRate), channels=2")
    }
    
    private func installMicrophoneTap() {
        // 使用nil以采用节点当前输出格式（由连接到mainMixer后确定），减少格式不匹配
        recordMixer.removeTap(onBus: 0)
        recordMixer.installTap(onBus: 0, bufferSize: 4096, format: nil) { [weak self] buffer, time in
            guard let self = self, let file = self.audioFile else { return }
            
            do {
                try file.write(from: buffer)
            } catch {
                self.logger.error("写入麦克风音频失败: \(error.localizedDescription)")
                self.logger.error("文件处理格式: \(String(describing: self.audioFile?.processingFormat))，缓冲区格式: rate=\(buffer.format.sampleRate), ch=\(buffer.format.channelCount)")
            }
            
            let level = self.calculateRMSLevel(from: buffer)
            if level > 0.01 {
                self.logger.info("麦克风录制电平: \(String(format: "%.3f", level))")
            }
            
            Task { @MainActor in
                self.onLevel?(level)
            }
        }
        logger.info("麦克风录制监听已安装")
    }
    
    private func startMicrophoneEngine() throws {
        engine.mainMixerNode.outputVolume = 0
        engine.connect(recordMixer, to: engine.mainMixerNode, format: mixerFormat)
        try engine.start()
        logger.info("麦克风录制引擎启动成功，mainMixer已连接")
    }
}

// MARK: - Factory Controller

/// 重构后的音频录制控制器（工厂模式）
@MainActor
class AudioRecorderController: NSObject {
    
    // MARK: - Properties
    private var currentRecorder: AudioRecorderProtocol?
    private var _recordingMode: AudioUtils.RecordingMode = .systemAudio
    private var _currentFormat: AudioUtils.AudioFormat = .m4a
    private let logger = Logger.shared
    
    // MARK: - Public Interface (保持与原来相同)
    var isRunning: Bool {
        return currentRecorder?.isRunning ?? false
    }
    
    var onLevel: ((Float) -> Void)? {
        didSet { currentRecorder?.onLevel = onLevel }
    }
    
    var onStatus: ((String) -> Void)? {
        didSet { currentRecorder?.onStatus = onStatus }
    }
    
    var onRecordingComplete: ((AudioRecording) -> Void)? {
        didSet { currentRecorder?.onRecordingComplete = onRecordingComplete }
    }
    
    var onPlaybackComplete: (() -> Void)? {
        didSet { currentRecorder?.onPlaybackComplete = onPlaybackComplete }
    }
    
    // MARK: - Initialization
    override init() {
        super.init()
        setupRecorder()
    }
    
    // MARK: - Public Methods (保持原来的接口)
    func setRecordingMode(_ mode: AudioUtils.RecordingMode) {
        _recordingMode = mode
        logger.info("录制模式已设置为: \(mode.rawValue)")
        setupRecorder()
    }
    
    func setAudioFormat(_ format: AudioUtils.AudioFormat) {
        _currentFormat = format
        currentRecorder?.setAudioFormat(format)
        logger.info("音频格式已设置为: \(format.rawValue)")
    }
    
    func startRecording() {
        logger.info("开始录制，模式: \(_recordingMode.rawValue), 格式: \(_currentFormat.rawValue)")
        currentRecorder?.startRecording()
    }
    
    func stopRecording() {
        logger.info("停止录制")
        currentRecorder?.stopRecording()
    }
    
    func playRecording(at url: URL) {
        currentRecorder?.playRecording(at: url)
    }
    
    func stopPlayback() {
        currentRecorder?.stopPlayback()
    }
    
    // MARK: - Private Methods
    private func setupRecorder() {
        guard !isRunning else {
            logger.warning("录制进行中，无法切换录制器")
            return
        }
        
        let newRecorder: AudioRecorderProtocol
        
        switch _recordingMode {
        case .microphone:
            logger.info("创建麦克风录制器")
            newRecorder = MicrophoneRecorder(mode: .microphone)
            
        case .systemAudio:
            logger.info("创建系统音频录制器")
            newRecorder = SystemAudioRecorder(mode: .systemAudio)
        }
        
        newRecorder.setAudioFormat(_currentFormat)
        newRecorder.onLevel = onLevel
        newRecorder.onStatus = onStatus
        newRecorder.onRecordingComplete = onRecordingComplete
        newRecorder.onPlaybackComplete = onPlaybackComplete
        
        currentRecorder = newRecorder
        logger.info("录制器已切换到: \(_recordingMode.displayName)")
    }
}

// MARK: - Supporting Classes (same as before)

 
