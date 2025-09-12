import Foundation

// （移除内嵌 MicrophoneRecorder，统一使用独立文件 src/Controllers/MicrophoneRecorder.swift）

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

 
