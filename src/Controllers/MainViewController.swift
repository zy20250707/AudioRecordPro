import Cocoa
import Foundation
import AVFoundation

/// 主视图控制器
class MainViewController: NSViewController {
    
    // MARK: - Properties
    private var mainWindowView: MainWindowView!
    var audioRecorderController: AudioRecorderController!
    private let logger = Logger.shared
    private let fileManager = FileManagerUtils.shared
    
    // Recording state
    private var isRecording = false
    private var recordingStartTime: Date?
    private var recordingTimer: Timer?
    private var playbackTimer: Timer?
    private var lastRecordedFile: URL?
    private var currentRecordingMode: AudioUtils.RecordingMode = .microphone
    private let userDefaults = UserDefaults.standard
    private let recordingModeKey = "lastRecordingMode"
    private var currentFormat: AudioUtils.AudioFormat = .m4a
    private var playbackStartTime: Date?
    private var playbackDuration: TimeInterval = 0
    
    // 进程列表相关
    private var availableProcesses: [AudioProcessInfo] = []
    private var selectedProcesses: Set<AudioProcessInfo> = []
    private var selectedPIDs: [pid_t] = []
    
    // MARK: - Lifecycle
    override func loadView() {
        mainWindowView = MainWindowView()
        mainWindowView.delegate = self
        view = mainWindowView
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        logger.info("主视图控制器开始加载")
        setupInitialState()
        // 关闭启动时的权限监控与静默检查，避免任何权限链路阻塞 UI
        // checkAudioPermissionsSilently()
        logger.info("主视图控制器已加载")
    }
    
    private func ensureAudioControllerInitialized() {
        guard audioRecorderController == nil else { return }
        
        logger.info("开始初始化音频控制器")
        audioRecorderController = AudioRecorderController()
        setupAudioRecorder()
        logger.info("音频控制器初始化完成")
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        
        // 延迟检查按钮位置
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.mainWindowView.debugButtonPosition()
        }
    }
    
    // MARK: - Setup
    private func setupAudioRecorder() {
        guard let audioRecorderController = audioRecorderController else {
            logger.warning("音频控制器未初始化，跳过设置")
            return
        }
        
        audioRecorderController.onLevel = { [weak self] level in
            DispatchQueue.main.async {
                self?.mainWindowView.updateLevel(level)
            }
        }
        
        audioRecorderController.onStatus = { [weak self] status in
            DispatchQueue.main.async {
                self?.mainWindowView.updateStatus(status)
                
                // 检查是否是录音失败的状态，如果是则停止计时器
                if status.contains("失败") || 
                   status.contains("错误") || 
                   status.contains("权限") ||
                   status.contains("denied") ||
                   status.contains("permission") {
                    self?.handleRecordingFailure()
                }
            }
        }
        
        audioRecorderController.onRecordingComplete = { [weak self] recording in
            DispatchQueue.main.async {
                self?.handleRecordingComplete(recording)
            }
        }
        
        audioRecorderController.onPlaybackComplete = { [weak self] in
            DispatchQueue.main.async {
                self?.stopPlaybackTimer()
                self?.mainWindowView.updateRecordingState(.idle)
                self?.mainWindowView.updateStatus("播放完成")
            }
        }
        
        audioRecorderController.setRecordingMode(currentRecordingMode)
        audioRecorderController.setAudioFormat(currentFormat)
    }
    
    private func setupInitialState() {
        // 加载上次的录制模式
        loadLastRecordingMode()
        
        mainWindowView.updateMode(currentRecordingMode)
        mainWindowView.updateRecordingState(.idle)
        mainWindowView.updateStatus("准备就绪")
        
        // 加载可用进程列表
        loadAvailableProcesses()
        
        // 加载录音文件列表
        loadRecordedFilesOnStartup()
        
        // 清理旧日志
        logger.cleanupOldLogs()
        
        // 清理临时文件
        fileManager.cleanupTempFiles()
    }
    
    /// 静默权限检查（启动时不弹窗）
    private func checkAudioPermissionsSilently() {
        let permissions = PermissionManager.shared.checkAllPermissions()
        
        // 只记录日志，不显示状态信息
        switch permissions.microphone {
        case .granted:
            logger.info("麦克风权限已授予")
        case .denied:
            logger.info("麦克风权限被拒绝")
        case .notDetermined:
            logger.info("麦克风权限未确定")
        case .restricted:
            logger.info("麦克风权限受限制")
        }
        
        switch permissions.screenRecording {
        case .granted:
            logger.info("屏幕录制权限已授予")
        case .denied:
            logger.info("屏幕录制权限被拒绝")
        case .notDetermined:
            logger.info("屏幕录制权限未确定")
        case .restricted:
            logger.info("屏幕录制权限受限制")
        }
        
        // 开始权限监控
        startPermissionMonitoring()
    }
    
    /// 主动权限检查（录制时使用）
    private func checkAudioPermissions() {
        let permissions = PermissionManager.shared.checkAllPermissions()
        
        // 检查麦克风权限
        switch permissions.microphone {
        case .granted:
            logger.info("麦克风权限已授予")
        case .denied:
            logger.warning("麦克风权限被拒绝")
            mainWindowView.updateStatus("麦克风权限被拒绝，可以切换到系统音频模式")
        case .notDetermined:
            logger.info("麦克风权限未确定，将在需要时请求")
        case .restricted:
            logger.warning("麦克风权限受限制")
            mainWindowView.updateStatus("麦克风权限受系统限制")
        }
        
        // 检查屏幕录制权限
        switch permissions.screenRecording {
        case .granted:
            logger.info("屏幕录制权限已授予")
        case .denied:
            logger.warning("屏幕录制权限被拒绝")
            mainWindowView.updateStatus("屏幕录制权限被拒绝，请在系统设置中允许")
        case .notDetermined:
            logger.info("屏幕录制权限未确定，将在需要时请求")
        case .restricted:
            logger.warning("屏幕录制权限受限制")
            mainWindowView.updateStatus("屏幕录制权限受系统限制")
        }
    }
    
    private func startPermissionMonitoring() {
        // 注释掉权限监控，避免后台持续触发权限检查
        // PermissionManager.shared.startPermissionMonitoring { [weak self] type, status in
        //     DispatchQueue.main.async {
        //         self?.handlePermissionStatusChange(type: type, status: status)
        //     }
        // }
    }
    
    private func handlePermissionStatusChange(type: PermissionManager.PermissionType, status: PermissionManager.PermissionStatus) {
        // 只在录制过程中或权限状态发生重要变化时显示提示
        guard isRecording else { return }
        
        switch type {
        case .microphone:
            switch status {
            case .granted:
                logger.info("麦克风权限已授予")
                if currentRecordingMode == .microphone {
                    mainWindowView.updateStatus("麦克风权限已授予，可以开始录制")
                }
            case .denied:
                logger.warning("麦克风权限被拒绝")
                if currentRecordingMode == .microphone {
                    mainWindowView.updateStatus("麦克风权限被拒绝，请切换到系统音频模式")
                }
            default:
                break
            }
        case .screenRecording:
            switch status {
            case .granted:
                logger.info("屏幕录制权限已授予")
                // 屏幕录制权限相关代码已移除
            case .denied:
                logger.warning("屏幕录制权限被拒绝")
                // 屏幕录制权限相关代码已移除
            default:
                break
            }
        case .systemAudioCapture:
            switch status {
            case .granted:
                logger.info("系统音频捕获权限已授予")
            case .denied:
                logger.warning("系统音频捕获权限被拒绝")
                if currentRecordingMode == .specificProcess || currentRecordingMode == .systemMixdown {
                    mainWindowView.updateStatus("系统音频捕获权限被拒绝，请点击允许或在设置中开启")
                }
            default:
                break
            }
        }
    }
    
    // MARK: - Recording Management
    private func startRecording() {
        guard !isRecording else {
            logger.warning("录制已在进行中")
            return
        }
        // 确保音频控制器已初始化
        ensureAudioControllerInitialized()
        
        // 根据左侧选择动态确定录制源
        let wantMic = mainWindowView.isMicrophoneSourceSelected()
        let wantSystemMixdown = mainWindowView.isSystemAudioSourceSelected()
        let wantSpecificProcess = !selectedPIDs.isEmpty
        
        // 检查是否有任何选择
        guard wantMic || wantSystemMixdown || wantSpecificProcess else {
            mainWindowView.updateStatus("请先选择录制源：麦克风、系统混音或特定进程")
            return
        }
        
        logger.info("开始多音源录制 - 麦克风:\(wantMic), 系统:\(wantSystemMixdown), 进程:\(wantSpecificProcess)")
        
        // 构建录制源描述
        var sources: [String] = []
        if wantMic { sources.append("麦克风") }
        if wantSystemMixdown { sources.append("系统音频") }
        if wantSpecificProcess { sources.append("特定进程") }
        let sourcesText = sources.joined(separator: " + ")
        
        checkPermissionsBeforeRecording { [weak self] granted in
            guard let self = self else { return }
            guard granted else {
                self.logger.warning("权限未通过，取消录制")
                self.handleRecordingFailure()
                return
            }
            
            // 录制前主动请求系统音频捕获权限（TCC）
            if wantSystemMixdown || wantSpecificProcess {
                PermissionManager.shared.requestSystemAudioCapturePermission { status in
                    // 无论结果如何，继续尝试启动，系统也会再次弹窗
                }
            }
            
            self.isRecording = true
            self.recordingStartTime = Date()
            self.mainWindowView.updateRecordingState(.preparing)
            self.mainWindowView.updateStatus("准备录制 \(sourcesText)…")
            self.startTimer()
            
            // 设置音频格式
            self.audioRecorderController.setAudioFormat(self.currentFormat)
            
            // 使用新的多音源录制方法
            self.audioRecorderController.startMultiSourceRecording(
                wantMic: wantMic,
                wantSystem: wantSystemMixdown,
                wantProcess: wantSpecificProcess,
                targetPID: self.selectedPIDs.first
            )
            
            // 视觉上进入录制态
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if self.isRecording { self.mainWindowView.updateRecordingState(.recording) }
            }
        }
    }
    
    private func checkPermissionsBeforeRecording(completion: @escaping (Bool) -> Void) {
        switch currentRecordingMode {
        case .microphone:
            // 请求麦克风权限
            logger.info("请求麦克风权限...")
            mainWindowView.updateStatus("正在请求麦克风权限...")
            
            PermissionManager.shared.requestMicrophonePermission { [weak self] status in
                DispatchQueue.main.async {
                    switch status {
                    case .granted:
                        self?.logger.info("麦克风权限已授予")
                        completion(true)
                    case .denied, .restricted:
                        self?.logger.warning("麦克风权限被拒绝")
                        self?.mainWindowView.updateStatus("麦克风权限被拒绝，请切换到系统音频模式")
                        completion(false)
                    case .notDetermined:
                        self?.logger.warning("麦克风权限未确定")
                        self?.mainWindowView.updateStatus("麦克风权限未确定，请重试")
                        completion(false)
                    }
                }
            }
        case .specificProcess, .systemMixdown:
            // CoreAudio 方案不需要额外权限，直接放行（系统会在首次真正使用时提示系统音频捕获权限）
            logger.info("CoreAudio 模式：不需要额外权限，直接开始")
            DispatchQueue.main.async { completion(true) }
        
        }
    }
    
    private func stopRecording() {
        guard isRecording else {
            logger.warning("没有正在进行的录制")
            mainWindowView.updateStatus("没有正在进行的录制")
            return
        }
        
        logger.info("停止录制")
        
        isRecording = false
        mainWindowView.updateRecordingState(.stopping)
        mainWindowView.updateStatus("正在停止录制...")
        
        // 停止计时器
        stopTimer()
        
        // 停止底层录制
        audioRecorderController.stopRecording()
        
        logger.info("录制已停止")
    }
    
    private func handleRecordingComplete(_ recording: AudioRecording) {
        lastRecordedFile = recording.fileURL
        mainWindowView.updateRecordingState(.idle)
        mainWindowView.updateStatus("录制完成: \(recording.fileName)")
        
        logger.info("录制完成: \(recording.fileName), 时长: \(recording.formattedDuration), 大小: \(recording.formattedFileSize)")
        
        // 添加到已录制文件列表
        let fileInfo = RecordedFileInfo(
            url: recording.fileURL,
            name: recording.fileName,
            date: recording.createdAt,
            duration: recording.duration,
            size: recording.fileSize
        )
        mainWindowView.addRecordedFile(fileInfo)
        
        // 自动播放（如果启用）
        if AppConfiguration().autoPlayAfterRecording {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.playRecording()
            }
        }
    }
    
    // MARK: - Timer Management
    private func startTimer() {
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateTimer()
        }
    }
    
    private func stopTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        mainWindowView.updateTimer("00:00:00")
    }
    
    private func handleRecordingFailure() {
        // 录音失败时停止计时器和重置状态
        logger.warning("录音失败，停止计时器")
        isRecording = false
        recordingStartTime = nil
        stopTimer()
        mainWindowView.updateRecordingState(.idle)
    }
    
    private func updateTimer() {
        guard let startTime = recordingStartTime else { return }
        
        let elapsed = Date().timeIntervalSince(startTime)
        let hours = Int(elapsed) / 3600
        let minutes = Int(elapsed) % 3600 / 60
        let seconds = Int(elapsed) % 60
        let milliseconds = Int((elapsed.truncatingRemainder(dividingBy: 1)) * 10)
        
        let timeString = String(format: "%02d:%02d:%02d.%d", hours, minutes, seconds, milliseconds)
        mainWindowView.updateTimer(timeString)
    }
    
    // MARK: - Playback Management
    private func playRecording() {
        guard let fileURL = lastRecordedFile, fileManager.fileExists(at: fileURL) else {
            mainWindowView.updateStatus("没有可播放的录音文件")
            logger.warning("没有可播放的录音文件")
            return
        }
        
        // 确保音频控制器已初始化
        ensureAudioControllerInitialized()
        
        logger.info("正在播放录音: \(fileURL.lastPathComponent)")
        logger.info("文件路径: \(fileURL.path)")
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            let fileSize = attributes[.size] as? Int64 ?? 0
            logger.info("文件大小: \(fileSize) bytes")
        } catch {
            logger.info("无法获取文件大小: \(error.localizedDescription)")
        }
        
        // 获取音频文件时长
        do {
            let audioFile = try AVAudioFile(forReading: fileURL)
            playbackDuration = Double(audioFile.length) / audioFile.processingFormat.sampleRate
            logger.info("音频时长: \(String(format: "%.2f", playbackDuration)) 秒")
        } catch {
            logger.warning("无法获取音频时长: \(error.localizedDescription)")
            playbackDuration = 0
        }
        
        mainWindowView.updateRecordingState(.playing)
        playbackStartTime = Date()
        startPlaybackTimer()
        audioRecorderController.playRecording(at: fileURL)
    }
    
    private func stopPlayback() {
        logger.info("停止播放")
        stopPlaybackTimer()
        audioRecorderController?.stopPlayback()
        mainWindowView.updateRecordingState(.idle)
    }
    
    private func startPlaybackTimer() {
        stopPlaybackTimer() // 确保之前的定时器被停止
        
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updatePlaybackTimer()
        }
    }
    
    private func stopPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
    }
    
    private func updatePlaybackTimer() {
        guard let startTime = playbackStartTime, playbackDuration > 0 else { return }
        
        let elapsed = Date().timeIntervalSince(startTime)
        let remaining = max(0, playbackDuration - elapsed)
        
        // 更新倒计时显示
        let hours = Int(remaining) / 3600
        let minutes = Int(remaining) % 3600 / 60
        let seconds = Int(remaining) % 60
        let milliseconds = Int((remaining.truncatingRemainder(dividingBy: 1)) * 10)
        
        let timeString = String(format: "%02d:%02d:%02d.%d", hours, minutes, seconds, milliseconds)
        mainWindowView.updateTimer(timeString)
        
        // 检查是否播放完成
        if remaining <= 0 {
            stopPlaybackTimer()
            mainWindowView.updateRecordingState(.idle)
            mainWindowView.updateStatus("播放完成")
        }
    }
    
    // MARK: - Recording Mode Management
    private func loadLastRecordingMode() {
        // 不记录之前的选择，每次启动都使用默认模式
        logger.info("使用默认录制模式: \(currentRecordingMode.rawValue)")
    }
    
    private func saveRecordingMode(_ mode: AudioUtils.RecordingMode) {
        userDefaults.set(mode.rawValue, forKey: recordingModeKey)
        logger.info("已保存录制模式: \(mode.rawValue)")
    }
    
    // MARK: - File Management
    private func downloadRecording() {
        guard let fileURL = lastRecordedFile, fileManager.fileExists(at: fileURL) else {
            mainWindowView.updateStatus("没有可下载的录音文件")
            logger.warning("没有可下载的录音文件")
            return
        }
        
        logger.info("开始下载: \(fileURL.lastPathComponent)")
        
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "选择保存位置"
        panel.message = "选择录音文件的保存位置"
        
        panel.begin { [weak self] response in
            if response == .OK, let saveURL = panel.url {
                let destinationURL = saveURL.appendingPathComponent(fileURL.lastPathComponent)
                
                do {
                    try self?.fileManager.copyFile(from: fileURL, to: destinationURL)
                    self?.mainWindowView.updateStatus("文件已保存到: \(destinationURL.path)")
                    self?.logger.info("文件已保存到: \(destinationURL.path)")
                } catch {
                    let errorMsg = "保存失败: \(error.localizedDescription)"
                    self?.mainWindowView.updateStatus(errorMsg)
                    self?.logger.error("保存文件失败: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: - Mode Management
    private func switchRecordingMode() {
        // 三态循环：microphone -> specificProcess -> systemMixdown -> microphone
        switch currentRecordingMode {
        case .microphone:
            currentRecordingMode = .specificProcess
        case .specificProcess:
            currentRecordingMode = .systemMixdown
        case .systemMixdown:
            currentRecordingMode = .microphone
        }
        
        // 确保音频控制器已初始化
        ensureAudioControllerInitialized()
        
        audioRecorderController?.setRecordingMode(currentRecordingMode)
        mainWindowView.updateMode(currentRecordingMode)
        
        logger.info("录制模式已切换到: \(currentRecordingMode.rawValue)")
        
        // 根据模式提示/检查权限
        switch currentRecordingMode {
        case .microphone:
            checkMicrophonePermissionOnModeSwitch()
        case .specificProcess:
            // 特定进程录制需要 NSAudioCaptureUsageDescription（已在 Info.plist）
            mainWindowView.updateStatus("特定进程录制：需要系统音频捕获权限，开始录制时会提示授权")
            // 模式切到特定进程录制时，同步一次当前选择（若有）
            if let pid = selectedPIDs.first {
                audioRecorderController?.setCoreAudioTargetPID(pid)
            } else {
                audioRecorderController?.setCoreAudioTargetPID(nil)
            }
        case .systemMixdown:
            // 系统混音录制需要 NSAudioCaptureUsageDescription（已在 Info.plist）
            mainWindowView.updateStatus("系统混音录制：需要系统音频捕获权限，开始录制时会提示授权")
        
        }
    }
    
    private func checkMicrophonePermissionOnModeSwitch() {
        logger.info("检查麦克风权限（模式切换时）")
        
        let permissions = PermissionManager.shared.checkAllPermissions()
        switch permissions.microphone {
        case .granted:
            logger.info("麦克风权限已授予")
            mainWindowView.updateStatus("麦克风权限已授予，可以开始录制")
        case .denied, .restricted:
            logger.warning("麦克风权限被拒绝")
            mainWindowView.updateStatus("麦克风权限被拒绝，开始录制时将重新请求")
        case .notDetermined:
            logger.info("麦克风权限未确定")
            mainWindowView.updateStatus("麦克风权限未确定，开始录制时将请求权限")
        }
    }

    private func checkScreenRecordingPermissionOnModeSwitch() {
        logger.info("检查屏幕录制权限（模式切换时）")
        
        let permissions = PermissionManager.shared.checkAllPermissions()
        switch permissions.screenRecording {
        case .granted:
            logger.info("屏幕录制权限已授予")
            mainWindowView.updateStatus("屏幕录制权限已授予，可以开始录制")
        case .denied, .restricted:
            logger.warning("屏幕录制权限被拒绝")
            mainWindowView.updateStatus("屏幕录制权限被拒绝，开始录制时将重新请求")
        case .notDetermined:
            logger.info("屏幕录制权限未确定")
            mainWindowView.updateStatus("屏幕录制权限未确定，开始录制时将请求权限")
        }
    }
    
    // MARK: - Debug Methods
    private func simulateButtonClick() {
        logger.info("🤖 开始模拟按钮点击测试...")
        
        // 方法1: 直接调用按钮的action（最小化版本暂时注释）
        logger.info("方法1: 直接调用按钮action - 跳过（最小化版本）")
        // mainWindowView.perform(#selector(MainWindowView.modeSwitchButtonClicked))
        
        // 方法2: 直接调用delegate方法
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.logger.info("方法2: 直接调用delegate方法")
            self.mainWindowViewDidSwitchMode(self.mainWindowView)
        }
        
        // 方法3: 直接调用switchRecordingMode
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.logger.info("方法3: 直接调用switchRecordingMode")
            self.switchRecordingMode()
        }
    }
    
    private func changeFormat(_ formatString: String) {
        let newFormat: AudioUtils.AudioFormat
        switch formatString.lowercased() {
        case "wav":
            newFormat = .wav
        default:
            newFormat = .m4a
        }
        
        if newFormat != currentFormat {
            currentFormat = newFormat
            
            // 确保音频控制器已初始化
            ensureAudioControllerInitialized()
            
            audioRecorderController?.setAudioFormat(newFormat)
            logger.info("音频格式已更改为: \(newFormat.rawValue)")
        }
    }
}

// MARK: - MainWindowViewDelegate
extension MainViewController: MainWindowViewDelegate {
    func mainWindowViewDidSwitchMode(_ view: MainWindowView) {
        logger.info("🎯 主视图控制器收到模式切换请求")
        logger.info("切换前当前模式: \(currentRecordingMode.rawValue)")
        switchRecordingMode()
        logger.info("切换后当前模式: \(currentRecordingMode.rawValue)")
    }
    
    func mainWindowViewDidStartRecording(_ view: MainWindowView) {
        startRecording()
    }
    
    func mainWindowViewDidStopRecording(_ view: MainWindowView) {
        logger.info("🛑 主视图控制器收到停止录制请求")
        logger.info("当前录制状态: \(isRecording)")
        stopRecording()
    }
    
    func mainWindowViewDidPlayRecording(_ view: MainWindowView) {
        playRecording()
    }
    
    func mainWindowViewDidDownloadRecording(_ view: MainWindowView) {
        downloadRecording()
    }
    
    func mainWindowViewDidChangeFormat(_ view: MainWindowView, format: String) {
        changeFormat(format)
    }
    
    func mainWindowViewDidOpenPermissions(_ view: MainWindowView) {
        openSystemPreferences()
    }
    
    func mainWindowViewDidStopPlayback(_ view: MainWindowView) {
        stopPlayback()
    }
    
    func mainWindowViewDidSelectProcesses(_ view: MainWindowView, pids: [pid_t]) {
        selectedPIDs = pids
        
        // 不保存选择状态，每次启动都完全重置
        
        // 如果当前是特定进程录制模式，立即刷新目标 PID（取首个）
        if currentRecordingMode == .specificProcess {
            ensureAudioControllerInitialized()
            audioRecorderController?.setCoreAudioTargetPID(pids.first)
            if let first = pids.first {
                mainWindowView.updateStatus("已选择进程 PID=\(first)")
            } else {
                mainWindowView.updateStatus("已清空进程选择，默认录制系统混音")
            }
        }
    }
    
    func mainWindowViewDidRequestProcessRefresh(_ view: MainWindowView) {
        refreshProcessList()
    }
    
    func mainWindowViewDidRequestExportToMP3(_ view: MainWindowView, file: RecordedFileInfo) {
        exportToMP3(file: file)
    }
    
    private func refreshProcessList() {
        logger.info("🔄 刷新进程列表...")
        mainWindowView.updateStatus("正在刷新进程列表...")
        
        // 在后台线程刷新进程列表
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            if #available(macOS 14.4, *) {
                Task { @MainActor in
                    let coreAudioRecorder = CoreAudioProcessTapRecorder(mode: .systemMixdown)
                    let processes = coreAudioRecorder.getAvailableAudioProcesses()
                    
                    self.mainWindowView.updateProcessList(processes)
                    self.logger.info("✅ 进程列表刷新完成，发现 \(processes.count) 个进程")
                    self.mainWindowView.updateStatus("进程列表已刷新，发现 \(processes.count) 个进程")
                    
                    // 不恢复上次的选择状态，完全重置
                    self.logger.info("📝 进程列表刷新完成，完全重置状态")
                }
            } else {
                DispatchQueue.main.async {
                    self.mainWindowView.updateStatus("当前系统不支持 CoreAudio Process Tap")
                }
            }
        }
    }
    
    private func exportToMP3(file: RecordedFileInfo) {
        logger.info("🎵 开始导出MP3: \(file.name)")
        mainWindowView.updateStatus("正在导出MP3: \(file.name)...")
        
        // 检查原文件是否为WAV格式
        guard file.url.pathExtension.lowercased() == "wav" else {
            logger.warning("只能导出WAV文件为MP3格式")
            mainWindowView.updateStatus("只能导出WAV文件为MP3格式")
            return
        }
        
        // 生成MP3文件路径（与原文件在同一目录）
        let mp3URL = file.url.deletingPathExtension().appendingPathExtension("mp3")
        
        // 检查MP3文件是否已存在
        if fileManager.fileExists(at: mp3URL) {
            logger.info("MP3文件已存在: \(mp3URL.lastPathComponent)")
            mainWindowView.updateStatus("MP3文件已存在: \(mp3URL.lastPathComponent)")
            
            // 在Finder中显示已存在的MP3文件
            DispatchQueue.main.async {
                NSWorkspace.shared.selectFile(mp3URL.path, inFileViewerRootedAtPath: mp3URL.deletingLastPathComponent().path)
            }
            return
        }
        
        // 在后台线程执行转换
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            do {
                // 使用afconvert命令进行转换
                let success = try self.convertWAVToMP3(inputURL: file.url, outputURL: mp3URL)
                
                DispatchQueue.main.async {
                    if success {
                        self.logger.info("✅ MP3导出成功: \(mp3URL.lastPathComponent)")
                        self.mainWindowView.updateStatus("MP3导出成功: \(mp3URL.lastPathComponent)")
                        
                        // 在Finder中显示生成的MP3文件
                        NSWorkspace.shared.selectFile(mp3URL.path, inFileViewerRootedAtPath: mp3URL.deletingLastPathComponent().path)
                        
                        // 刷新文件列表
                        self.mainWindowView.refreshRecordedFiles()
                    } else {
                        self.logger.error("❌ MP3导出失败")
                        self.mainWindowView.updateStatus("MP3导出失败")
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.logger.error("❌ MP3导出失败: \(error.localizedDescription)")
                    self.mainWindowView.updateStatus("MP3导出失败: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func convertWAVToMP3(inputURL: URL, outputURL: URL) throws -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
        
        // afconvert参数：输入文件，输出文件，格式设置
        // -f mp4f 表示MP3格式，-d aac 表示使用AAC编码（兼容MP3）
        process.arguments = [
            inputURL.path,
            outputURL.path,
            "-f", "mp4f",
            "-d", "aac",
            "-q", "127"  // 最高质量
        ]
        
        logger.info("执行转换命令: afconvert \(process.arguments?.joined(separator: " ") ?? "")")
        
        try process.run()
        process.waitUntilExit()
        
        let success = process.terminationStatus == 0
        if success {
            logger.info("afconvert执行成功，退出码: \(process.terminationStatus)")
        } else {
            logger.error("afconvert执行失败，退出码: \(process.terminationStatus)")
        }
        
        return success
    }
    
    // MARK: - Process Selection Persistence

    func mainWindowViewDidRequestMode(_ view: MainWindowView, mode: AudioUtils.RecordingMode) {
        ensureAudioControllerInitialized()
        if currentRecordingMode != mode {
            currentRecordingMode = mode
            audioRecorderController?.setRecordingMode(mode)
            mainWindowView.updateMode(mode)
            saveRecordingMode(mode)
            switch mode {
            case .specificProcess:
                mainWindowView.updateStatus("特定进程录制模式：录制选中的进程")
            case .systemMixdown:
                mainWindowView.updateStatus("系统混音录制模式：录制系统所有音频输出")
            case .microphone:
                mainWindowView.updateStatus("麦克风模式已选中")
            }
        }
    }
    
    private func openSystemPreferences() {
        logger.info("打开系统偏好设置")
        PermissionManager.shared.openSystemPreferences()
        
        // 显示提示信息
        mainWindowView.updateStatus("已打开系统偏好设置，请允许麦克风和屏幕录制权限")
        
        // 3秒后重新检查权限
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            self.checkAudioPermissions()
        }
    }
    
    /// 加载可用的音频进程列表
    private func loadAvailableProcesses() {
        logger.info("开始加载可用音频进程列表")
        
        // 在主线程获取，避免 MainActor 隔离告警
        ensureAudioControllerInitialized()
        
        let processes: [AudioProcessInfo]
        if #available(macOS 14.4, *) {
            let lister = CoreAudioProcessTapRecorder(mode: .systemMixdown)
            processes = lister.getAvailableAudioProcesses()
        } else {
            logger.warning("CoreAudio Process Tap 需要 macOS 14.4+，无法加载进程列表")
            processes = []
        }
        
        self.availableProcesses = processes
        self.mainWindowView.updateProcessList(processes)
        self.logger.info("已加载 \(processes.count) 个可用音频进程")
        
        // 不恢复上次的选择状态，完全重置
        logger.info("📝 完全重置状态，不恢复上次选择")
    }
    
    /// 启动时加载录音文件列表
    private func loadRecordedFilesOnStartup() {
        logger.info("开始加载录音文件列表...")
        
        // 在后台线程加载文件列表，避免阻塞UI
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let recordingsPath = documentsPath.appendingPathComponent("AudioRecordings")
            
            var files: [RecordedFileInfo] = []
            
            do {
                // 检查录音目录是否存在
                if !FileManager.default.fileExists(atPath: recordingsPath.path) {
                    DispatchQueue.main.async {
                        self.logger.info("录音目录不存在，将在首次录制时创建")
                        self.mainWindowView.updateStatus("准备就绪")
                    }
                    return
                }
                
                let fileURLs = try FileManager.default.contentsOfDirectory(at: recordingsPath, includingPropertiesForKeys: [.fileSizeKey, .creationDateKey])
                
                for url in fileURLs {
                    let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey])
                    let fileSize = resourceValues.fileSize ?? 0
                    let creationDate = resourceValues.creationDate ?? Date()
                    
                    // 只处理音频文件
                    let pathExtension = url.pathExtension.lowercased()
                    guard ["wav", "m4a", "mp3"].contains(pathExtension) else {
                        continue
                    }
                    
                    // 获取音频文件时长
                    let duration = self.getAudioFileDuration(url: url)
                    
                    let fileInfo = RecordedFileInfo(
                        url: url,
                        name: url.lastPathComponent,
                        date: creationDate,
                        duration: duration,
                        size: Int64(fileSize)
                    )
                    
                    files.append(fileInfo)
                }
                
                // 按日期排序（最新的在前）
                files.sort { $0.date > $1.date }
                
            } catch {
                DispatchQueue.main.async {
                    self.logger.error("加载录制文件失败: \(error.localizedDescription)")
                    self.mainWindowView.updateStatus("加载录音文件失败")
                }
                return
            }
            
            // 在主线程更新UI
            DispatchQueue.main.async {
                self.logger.info("✅ 启动时加载了 \(files.count) 个录音文件")
                self.mainWindowView.updateStatus("已加载 \(files.count) 个录音文件")
                
                // 将文件列表传递给UI
                self.mainWindowView.loadRecordedFiles(files)
            }
        }
    }
    
    /// 获取音频文件时长
    private func getAudioFileDuration(url: URL) -> TimeInterval {
        do {
            let audioFile = try AVAudioFile(forReading: url)
            return Double(audioFile.length) / audioFile.fileFormat.sampleRate
        } catch {
            logger.warning("无法获取音频文件时长 \(url.lastPathComponent): \(error.localizedDescription)")
            return 0
        }
    }
}
