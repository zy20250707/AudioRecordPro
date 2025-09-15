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
        PermissionManager.shared.startPermissionMonitoring { [weak self] type, status in
            DispatchQueue.main.async {
                self?.handlePermissionStatusChange(type: type, status: status)
            }
        }
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
                if currentRecordingMode == .systemAudio {
                    mainWindowView.updateStatus("屏幕录制权限已授予，可以开始录制")
                }
            case .denied:
                logger.warning("屏幕录制权限被拒绝")
                if currentRecordingMode == .systemAudio {
                    mainWindowView.updateStatus("屏幕录制权限被拒绝，请在系统设置中允许")
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
        
        logger.info("开始录制，模式: \(currentRecordingMode.rawValue)")
        
        // 检查权限
        checkPermissionsBeforeRecording { [weak self] hasPermission in
            guard let self = self else { return }
            
            if !hasPermission {
                self.logger.warning("录制被阻止：缺少权限")
                return
            }
            
            // 权限检查通过，开始录制
            self.isRecording = true
            self.recordingStartTime = Date()
            
            self.mainWindowView.updateRecordingState(.preparing)
            self.mainWindowView.updateStatus("准备录制 \(self.currentRecordingMode.displayName)…")
            
            self.audioRecorderController?.startRecording()
            self.startTimer()
            
            // 延迟更新为录制状态
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if self.isRecording {
                    self.mainWindowView.updateRecordingState(.recording)
                }
            }
        }
    }
    
    private func checkPermissionsBeforeRecording(completion: @escaping (Bool) -> Void) {
        if currentRecordingMode == .microphone {
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
        } else {
            // 系统音频录制需要屏幕录制权限
            logger.info("请求屏幕录制权限...")
            mainWindowView.updateStatus("正在请求屏幕录制权限...")
            
            PermissionManager.shared.requestScreenRecordingPermission { [weak self] status in
                DispatchQueue.main.async {
                    switch status {
                    case .granted:
                        self?.logger.info("屏幕录制权限已授予")
                        completion(true)
                    case .denied, .restricted:
                        self?.logger.warning("屏幕录制权限被拒绝")
                        self?.mainWindowView.updateStatus("屏幕录制权限被拒绝，请点击权限设置按钮在系统设置中允许")
                        completion(false)
                    case .notDetermined:
                        self?.logger.warning("屏幕录制权限未确定")
                        self?.mainWindowView.updateStatus("需要屏幕录制权限，请点击权限设置按钮")
                        completion(false)
                    }
                }
            }
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
        
        // 停止录制
        audioRecorderController.stopRecording()
        
        logger.info("录制已停止")
    }
    
    private func handleRecordingComplete(_ recording: AudioRecording) {
        lastRecordedFile = recording.fileURL
        mainWindowView.updateRecordingState(.idle)
        mainWindowView.updateStatus("录制完成: \(recording.fileName)")
        
        logger.info("录制完成: \(recording.fileName), 时长: \(recording.formattedDuration), 大小: \(recording.formattedFileSize)")
        
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
        if let savedModeString = userDefaults.string(forKey: recordingModeKey),
           let savedMode = AudioUtils.RecordingMode(rawValue: savedModeString) {
            currentRecordingMode = savedMode
            logger.info("已加载上次的录制模式: \(savedMode.rawValue)")
        } else {
            logger.info("使用默认录制模式: \(currentRecordingMode.rawValue)")
        }
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
        currentRecordingMode = currentRecordingMode == .microphone ? .systemAudio : .microphone
        
        // 确保音频控制器已初始化
        ensureAudioControllerInitialized()
        
        audioRecorderController?.setRecordingMode(currentRecordingMode)
        mainWindowView.updateMode(currentRecordingMode)
        
        logger.info("录制模式已切换到: \(currentRecordingMode.rawValue)")
        
        // 如果切换到麦克风模式，检查权限
        if currentRecordingMode == .microphone {
            checkMicrophonePermissionOnModeSwitch()
        } else {
            checkScreenRecordingPermissionOnModeSwitch()
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
        
        // 方法1: 直接调用按钮的action
        logger.info("方法1: 直接调用按钮action")
        mainWindowView.perform(#selector(MainWindowView.modeSwitchButtonClicked))
        
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
}
