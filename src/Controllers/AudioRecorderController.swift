import Foundation

// （移除内嵌 MicrophoneRecorder，统一使用独立文件 src/Recorder/MicrophoneRecorder.swift）

// MARK: - Factory Controller

/// 音频源类型
enum AudioSourceType: String {
    case microphone = "microphone"
    case systemAudio = "system"
    case specificProcess = "process"
}

/// 重构后的音频录制控制器（支持多音源同时录制）
@MainActor
class AudioRecorderController: NSObject {
    
    // MARK: - Properties
    private var activeRecorders: [AudioSourceType: AudioRecorderProtocol] = [:]
    private var _currentFormat: AudioUtils.AudioFormat = .m4a
    private var _coreAudioTargetPID: pid_t?  // 保存CoreAudio目标PID
    private let logger = Logger.shared
    
    // 混音设置（预留，暂未实现）
    var shouldMixAudio: Bool = false
    
    // 多录制完成回调
    var onRecordingsComplete: (([AudioRecording]) -> Void)?
    
    // MARK: - Public Interface
    var isRunning: Bool {
        return !activeRecorders.isEmpty && activeRecorders.values.contains(where: { $0.isRunning })
    }
    
    var onLevel: ((Float) -> Void)? {
        didSet {
            activeRecorders.values.forEach { $0.onLevel = onLevel }
        }
    }
    
    var onStatus: ((String) -> Void)? {
        didSet {
            activeRecorders.values.forEach { $0.onStatus = onStatus }
        }
    }
    
    // 保持向后兼容
    var onRecordingComplete: ((AudioRecording) -> Void)?
    
    var onPlaybackComplete: (() -> Void)? {
        didSet {
            activeRecorders.values.forEach { $0.onPlaybackComplete = onPlaybackComplete }
        }
    }
    
    // MARK: - Initialization
    override init() {
        super.init()
    }
    
    // MARK: - Public Methods
    
    /// 设置音频格式
    func setAudioFormat(_ format: AudioUtils.AudioFormat) {
        _currentFormat = format
        activeRecorders.values.forEach { $0.setAudioFormat(format) }
        logger.info("音频格式已设置为: \(format.rawValue)")
    }
    
    /// 启动多个音源的录制
    /// - Parameters:
    ///   - wantMic: 是否录制麦克风
    ///   - wantSystem: 是否录制系统音频
    ///   - wantProcess: 是否录制特定进程
    ///   - targetPID: 特定进程的PID
    func startMultiSourceRecording(
        wantMic: Bool,
        wantSystem: Bool,
        wantProcess: Bool,
        targetPID: pid_t? = nil
    ) {
        guard !isRunning else {
            logger.warning("录制已在进行中")
            onStatus?("录制已在进行中")
            return
        }
        
        logger.info("开始多音源录制 - 麦克风:\(wantMic), 系统:\(wantSystem), 进程:\(wantProcess)")
        
        // 创建需要的录制器
        var newRecorders: [AudioSourceType: AudioRecorderProtocol] = [:]
        
        // 1. 麦克风录制器
        if wantMic {
            logger.info("创建麦克风录制器")
            let micRecorder = MicrophoneRecorder(mode: .microphone)
            micRecorder.setAudioFormat(_currentFormat)
            setupRecorderCallbacks(micRecorder, sourceType: .microphone)
            newRecorders[.microphone] = micRecorder
        }
        
        // 2. 系统音频录制器
        if wantSystem {
            logger.info("创建系统音频录制器")
            if #available(macOS 14.4, *) {
                let systemRecorder = CoreAudioProcessTapRecorder(mode: .systemMixdown)
                systemRecorder.setTargetPID(nil)
                systemRecorder.setAudioFormat(_currentFormat)
                setupRecorderCallbacks(systemRecorder, sourceType: .systemAudio)
                newRecorders[.systemAudio] = systemRecorder
            } else {
                let systemRecorder = ScreenCaptureAudioRecorder(mode: .systemMixdown)
                systemRecorder.setAudioFormat(_currentFormat)
                setupRecorderCallbacks(systemRecorder, sourceType: .systemAudio)
                newRecorders[.systemAudio] = systemRecorder
            }
        }
        
        // 3. 特定进程录制器
        if wantProcess, let pid = targetPID {
            if #available(macOS 14.4, *) {
                logger.info("创建特定进程录制器，PID: \(pid)")
                let processRecorder = CoreAudioProcessTapRecorder(mode: .specificProcess)
                processRecorder.setTargetPID(pid)
                processRecorder.setAudioFormat(_currentFormat)
                setupRecorderCallbacks(processRecorder, sourceType: .specificProcess)
                newRecorders[.specificProcess] = processRecorder
            } else {
                logger.warning("特定进程录制需要 macOS 14.4+")
                onStatus?("特定进程录制需要 macOS 14.4+")
            }
        }
        
        // 检查是否有录制器
        guard !newRecorders.isEmpty else {
            logger.warning("没有可用的录制器")
            onStatus?("请选择至少一个音频源")
            return
        }
        
        activeRecorders = newRecorders
        
        // 启动所有录制器
        for (type, recorder) in activeRecorders {
            logger.info("启动录制器: \(type.rawValue)")
            recorder.startRecording()
        }
        
        let sources = activeRecorders.keys.map { $0.rawValue }.joined(separator: ", ")
        onStatus?("正在录制: \(sources)")
    }
    
    /// 停止所有录制
    func stopRecording() {
        logger.info("停止所有录制，当前活跃录制器数: \(activeRecorders.count)")
        
        for (type, recorder) in activeRecorders {
            logger.info("停止录制器: \(type.rawValue)")
            recorder.stopRecording()
        }
    }
    
    /// 播放录音（使用第一个录制器）
    func playRecording(at url: URL) {
        activeRecorders.values.first?.playRecording(at: url)
    }
    
    /// 停止播放
    func stopPlayback() {
        activeRecorders.values.forEach { $0.stopPlayback() }
    }
    
    /// 设置CoreAudio目标PID
    func setCoreAudioTargetPID(_ pid: pid_t?) {
        _coreAudioTargetPID = pid
        logger.info("CoreAudio 目标 PID 已保存为: \(pid.map { String($0) } ?? "nil")")
        
        if #available(macOS 14.4, *) {
            if let core = activeRecorders[.specificProcess] as? CoreAudioProcessTapRecorder {
                core.setTargetPID(pid)
                logger.info("CoreAudio 目标 PID 已应用到特定进程录制器: \(pid.map { String($0) } ?? "nil")")
            }
        }
    }
    
    /// 设置多进程录制
    func setCoreAudioTargetPIDs(_ pids: [pid_t]) {
        logger.info("CoreAudio 目标 PID 列表已设置为: \(pids)")
        
        if #available(macOS 14.4, *) {
            if let core = activeRecorders[.specificProcess] as? CoreAudioProcessTapRecorder {
                core.setTargetPIDs(pids)
                logger.info("CoreAudio 目标 PID 列表已应用到特定进程录制器: \(pids)")
            }
        }
    }
    
    /// 清理所有录制器
    func clearRecorders() {
        logger.info("清理所有录制器")
        activeRecorders.removeAll()
    }
    
    // MARK: - 向后兼容的单音源录制方法
    
    /// 设置录制模式（向后兼容）
    func setRecordingMode(_ mode: AudioUtils.RecordingMode) {
        logger.info("录制模式已设置为: \(mode.rawValue)")
        // 这个方法保留用于兼容旧的调用方式
    }
    
    /// 开始录制（向后兼容，单音源）
    func startRecording() {
        logger.warning("使用了旧的单音源录制方法，建议使用 startMultiSourceRecording")
        // 默认启动麦克风录制
        startMultiSourceRecording(wantMic: true, wantSystem: false, wantProcess: false)
    }
    
    // MARK: - Private Methods
    
    private func setupRecorderCallbacks(_ recorder: AudioRecorderProtocol, sourceType: AudioSourceType) {
        recorder.onLevel = { [weak self] lvl in
            self?.onLevel?(lvl)
        }
        
        recorder.onStatus = { [weak self] status in
            self?.onStatus?(status)
        }
        
        recorder.onRecordingComplete = { [weak self] recording in
            guard let self = self else { return }
            
            self.logger.info("录制器 \(sourceType.rawValue) 完成录制: \(recording.fileURL.lastPathComponent)")
            
            // 通知单个录制完成（向后兼容）
            self.onRecordingComplete?(recording)
            
            // 检查是否所有录制器都完成了
            self.checkAllRecordingsComplete()
        }
        
        recorder.onPlaybackComplete = { [weak self] in
            self?.onPlaybackComplete?()
        }
    }
    
    private func checkAllRecordingsComplete() {
        // 检查是否所有录制器都已停止
        let allStopped = activeRecorders.values.allSatisfy { !$0.isRunning }
        
        if allStopped {
            logger.info("所有录制器已完成")
            // 这里可以触发多录制完成的回调
            // 暂时清理录制器列表
            Task { @MainActor in
                // 延迟清理，确保所有回调都执行完毕
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
                self.clearRecorders()
            }
        }
    }
    
    /// 获取当前活跃的录制器（向后兼容）
    func getCurrentRecorder() -> AudioRecorderProtocol? {
        return activeRecorders.values.first
    }
}

// MARK: - Supporting Classes (same as before)

 
