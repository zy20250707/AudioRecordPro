import Foundation

// （移除内嵌 MicrophoneRecorder，统一使用独立文件 src/Controllers/MicrophoneRecorder.swift）

// MARK: - Factory Controller

/// 重构后的音频录制控制器（工厂模式）
@MainActor
class AudioRecorderController: NSObject {
    
    // MARK: - Properties
    private var currentRecorder: AudioRecorderProtocol?
    private var _recordingMode: AudioUtils.RecordingMode = .microphone
    private var _currentFormat: AudioUtils.AudioFormat = .m4a
    private var _coreAudioTargetPID: pid_t?  // 保存CoreAudio目标PID
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
    
    /// 仅当当前录制器为 CoreAudio 方案时，设置目标 PID
    func setCoreAudioTargetPID(_ pid: pid_t?) {
        // 保存PID，即使当前录制器不是CoreAudio类型
        _coreAudioTargetPID = pid
        logger.info("CoreAudio 目标 PID 已保存为: \(pid.map { String($0) } ?? "nil")")
        
        if #available(macOS 14.4, *) {
            if let core = currentRecorder as? CoreAudioProcessTapRecorder {
                core.setTargetPID(pid)
                logger.info("CoreAudio 目标 PID 已应用到当前录制器: \(pid.map { String($0) } ?? "nil")")
            }
        }
    }
    
    /// 设置多进程录制（新增方法）
    func setCoreAudioTargetPIDs(_ pids: [pid_t]) {
        logger.info("CoreAudio 目标 PID 列表已设置为: \(pids)")
        
        if #available(macOS 14.4, *) {
            if let core = currentRecorder as? CoreAudioProcessTapRecorder {
                core.setTargetPIDs(pids)
                logger.info("CoreAudio 目标 PID 列表已应用到当前录制器: \(pids)")
            }
        }
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
            
        case .specificProcess:
            if #available(macOS 14.4, *) {
                logger.info("创建特定进程录制器（CoreAudio Process Tap）")
                let coreRecorder = CoreAudioProcessTapRecorder(mode: .specificProcess)
                // 应用保存的目标PID
                if let savedPID = _coreAudioTargetPID {
                    coreRecorder.setTargetPID(savedPID)
                    logger.info("应用保存的目标PID到新录制器: \(savedPID)")
                } else {
                    logger.warning("⚠️ 未指定目标进程PID，无法进行特定进程录制")
                    // 不允许没有选择就录制
                    onStatus?("请先选择要录制的进程")
                    return
                }
                newRecorder = coreRecorder
            } else {
                logger.warning("CoreAudio Process Tap 需要 macOS 14.4+，无法进行特定进程录制")
                onStatus?("特定进程录制需要 macOS 14.4+")
                return
            }
            
        case .systemMixdown:
            if #available(macOS 14.4, *) {
                logger.info("创建系统混音录制器（CoreAudio Process Tap）")
                let coreRecorder = CoreAudioProcessTapRecorder(mode: .systemMixdown)
                // 系统混音不需要指定PID
                coreRecorder.setTargetPID(nil)
                newRecorder = coreRecorder
            } else {
                logger.warning("CoreAudio Process Tap 需要 macOS 14.4+，回退到系统音频录制器")
                newRecorder = SystemAudioRecorder(mode: .systemMixdown)
            }
        }
        
        newRecorder.setAudioFormat(_currentFormat)
        newRecorder.onLevel = { [weak self] lvl in
            self?.onLevel?(lvl)
        }
        newRecorder.onStatus = onStatus
        newRecorder.onRecordingComplete = onRecordingComplete
        newRecorder.onPlaybackComplete = onPlaybackComplete
        
        currentRecorder = newRecorder
        logger.info("录制器已切换到: \(_recordingMode.displayName)")
    }
    
    /// 获取当前的录制器（用于进程列表功能）
    func getCurrentRecorder() -> AudioRecorderProtocol? {
        return currentRecorder
    }
}

// MARK: - Supporting Classes (same as before)

 
