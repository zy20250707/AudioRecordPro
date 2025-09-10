import Foundation
import AVFoundation
import Cocoa
import Accelerate
import ScreenCaptureKit

/// 音频录制控制器
@MainActor
class AudioRecorderController: NSObject {
    
    // MARK: - Properties
    private let engine = AVAudioEngine()
    private let systemPlayerNode = AVAudioPlayerNode()
    private let recordMixer = AVAudioMixerNode()
    private var audioFile: AVAudioFile?
    private var mixerFormat: AVAudioFormat?
    private var outputURL: URL?
    private var player: AVAudioPlayer?
    
    // System Audio Recording
    private var systemAudioNode: AVAudioInputNode?
    private var screenCaptureStream: SCStream?
    
    // Playback engine for real level monitoring
    private let playbackEngine = AVAudioEngine()
    private let playbackPlayerNode = AVAudioPlayerNode()
    private var playbackFile: AVAudioFile?
    
    // Level Monitoring
    private let levelMonitor = LevelMonitor()
    
    // State
    private var isRunning = false
    private var recordingMode: AudioUtils.RecordingMode = .systemAudio
    private var currentFormat: AudioUtils.AudioFormat = .m4a
    private var retryCount = 0
    
    // Dependencies
    private let logger = Logger.shared
    private let fileManager = FileManagerUtils.shared
    private let audioUtils = AudioUtils.shared
    
    // Callbacks
    var onLevel: ((Float) -> Void)?
    var onStatus: ((String) -> Void)?
    var onRecordingComplete: ((AudioRecording) -> Void)?
    var onPlaybackComplete: (() -> Void)?
    
    // MARK: - Initialization
    override init() {
        super.init()
        setupLevelMonitor()
        setupPlaybackEngine()
        logger.info("音频录制控制器已初始化")
    }
    
    deinit {
        screenCaptureStream?.stopCapture()
        screenCaptureStream = nil
    }
    
    private func setupLevelMonitor() {
        levelMonitor.onLevelUpdate = { [weak self] level in
            self?.onLevel?(level)
        }
    }
    
    private func setupPlaybackEngine() {
        // 设置播放引擎
        playbackEngine.attach(playbackPlayerNode)
        
        // 连接到主混音器，使用默认格式
        playbackEngine.connect(playbackPlayerNode, to: playbackEngine.mainMixerNode, format: nil)
        
        // 确保连接到输出节点
        let outputNode = playbackEngine.outputNode
        playbackEngine.connect(playbackEngine.mainMixerNode, to: outputNode, format: nil)
        logger.info("播放引擎已连接到输出节点")
        
        do {
            try playbackEngine.start()
            logger.info("播放引擎启动成功")
        } catch {
            logger.error("播放引擎启动失败: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Public Methods
    func setRecordingMode(_ mode: AudioUtils.RecordingMode) {
        recordingMode = mode
        logger.info("录制模式已设置为: \(mode.rawValue)")
    }
    
    func setAudioFormat(_ format: AudioUtils.AudioFormat) {
        currentFormat = format
        logger.info("音频格式已设置为: \(format.rawValue)")
    }
    
    func startRecording() {
        guard !isRunning else {
            logger.warning("录制已在进行中")
            return
        }
        
        // 重置重试计数
        retryCount = 0
        
        logger.info("开始录制，模式: \(recordingMode.rawValue), 格式: \(currentFormat.rawValue)")
        
        // 生成文件路径
        let url = fileManager.getRecordingFileURL(format: currentFormat.fileExtension)
        outputURL = url
        
        // 开始录制
        startRecording(to: url, format: currentFormat)
    }
    
    func stopRecording() {
        guard isRunning else {
            logger.warning("没有正在进行的录制")
            onStatus?("没有正在进行的录制")
            return
        }
        
        logger.info("停止录制")
        isRunning = false
        
        // 更新状态
        onStatus?("正在停止录制...")
        
        // 停止系统音频录制
        if recordingMode == .systemAudio {
            screenCaptureStream?.stopCapture { [weak self] error in
                if let error = error {
                    self?.logger.error("停止系统音频录制失败: \(error.localizedDescription)")
                } else {
                    self?.logger.info("系统音频录制已停止")
                }
            }
            screenCaptureStream = nil
        }
        
        // 只在麦克风模式下停止音频引擎
        if recordingMode == .microphone {
            systemPlayerNode.stop()
            recordMixer.removeTap(onBus: 0)
            engine.stop()
            logger.info("AVAudioEngine已停止（麦克风模式）")
        } else {
            logger.info("跳过AVAudioEngine停止（系统音频模式使用ScreenCaptureKit）")
        }
        
        // 关闭文件
        audioFile = nil
        
        // 停止电平监控
        levelMonitor.stopMonitoring()
        
        // 移除麦克风tap（如果存在）
        if recordingMode == .microphone {
            engine.inputNode.removeTap(onBus: 0)
            logger.info("已移除麦克风电平监听")
        }
        
        // 创建录音记录
        if let url = outputURL {
            createAudioRecording(from: url)
        }
        
        logger.info("录制已成功停止")
        onStatus?("录制已停止")
    }
    
    func playRecording(at url: URL) {
        logger.info("正在播放录音: \(url.lastPathComponent)")
        logger.info("文件路径: \(url.path)")
        logger.info("文件是否存在: \(FileManager.default.fileExists(atPath: url.path))")
        
        do {
            // 停止之前的播放
            stopPlayback()
            
            // 创建音频文件
            playbackFile = try AVAudioFile(forReading: url)
            logger.info("播放文件创建成功")
            logger.info("音频时长: \(playbackFile?.length ?? 0) 帧")
            logger.info("音频格式: \(playbackFile?.processingFormat.settings ?? [:])")
            
            // 计算音频时长（秒）
            let duration = Double(playbackFile?.length ?? 0) / (playbackFile?.processingFormat.sampleRate ?? 48000)
            logger.info("音频时长: \(String(format: "%.2f", duration)) 秒")
            
            // 确保播放引擎正在运行
            if !playbackEngine.isRunning {
                try playbackEngine.start()
                logger.info("播放引擎重新启动")
            }
            
            // 先安装tap来获取真实电平
            installPlaybackLevelTap()
            
            // 调度播放
            playbackPlayerNode.scheduleFile(playbackFile!, at: nil) { [weak self] in
                Task { @MainActor in
                    self?.onStatus?("播放完成")
                    self?.onPlaybackComplete?()
                    // 不在这里调用stopPlayback，避免重复调用
                }
            }
            
            // 开始播放
            playbackPlayerNode.play()
            
            onStatus?("正在播放: \(url.lastPathComponent)")
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
        
        // 移除播放电平tap
        playbackEngine.mainMixerNode.removeTap(onBus: 0)
        
        // 停止AVAudioEngine播放
        playbackPlayerNode.stop()
        playbackFile = nil
        
        // 停止AVAudioPlayer播放（如果还在使用）
        player?.stop()
        player = nil
        
        // 确保播放引擎正确停止
        if playbackEngine.isRunning {
            playbackEngine.stop()
            logger.info("播放引擎已停止")
        }
    }
    
    // MARK: - Private Methods
    private func startRecording(to url: URL, format: AudioUtils.AudioFormat) {
        isRunning = true
        onLevel?(0)
        
        // 配置音频引擎
        setupAudioEngine()
        
        // 开始电平监控
        if recordingMode == .systemAudio {
            // 系统音频模式：电平监控由SystemAudioStreamOutput提供
            levelMonitor.startMonitoring(source: LevelMonitor.MonitoringSource.simulated)
        } else {
            // 麦克风模式：使用引擎监控
            levelMonitor.startMonitoring(source: LevelMonitor.MonitoringSource.recording(engine: engine))
        }
        
        // 创建音频文件
        do {
            try createAudioFile(at: url, format: format)
        } catch {
            let errorMsg = "文件创建失败: \(error.localizedDescription)"
            onStatus?(errorMsg)
            logger.error("创建音频文件失败: \(error.localizedDescription)")
            isRunning = false
            return
        }
        
        // 安装混音器监听
        installMixerTap()
        
        // 启动音频引擎
        do {
            try startAudioEngine()
        } catch {
            let errorMsg = "音频引擎启动失败: \(error.localizedDescription)"
            onStatus?(errorMsg)
            logger.error("启动音频引擎失败: \(error.localizedDescription)")
            isRunning = false
            
            // 检查是否是权限问题
            if error.localizedDescription.contains("permission") || 
               error.localizedDescription.contains("权限") ||
               error.localizedDescription.contains("denied") {
                onStatus?("需要麦克风权限才能录制，请在系统设置中允许")
            }
            return
        }
        
        // 根据模式启动相应的捕获
        if recordingMode == .systemAudio {
            startSystemAudioCapture()
        } else {
            onStatus?("正在录制麦克风...")
        }
    }
    
    private func setupAudioEngine() {
        engine.attach(systemPlayerNode)
        engine.attach(recordMixer)
        
        let desiredSampleRate: Double = 48000
        let commonFormat = AVAudioCommonFormat.pcmFormatFloat32
        let mixerOutputFormat = AVAudioFormat(commonFormat: commonFormat, sampleRate: desiredSampleRate, channels: 2, interleaved: false)
        mixerFormat = mixerOutputFormat
        
        if recordingMode == .microphone {
            // 麦克风模式：直接使用麦克风输入，不通过混音器
            let input = engine.inputNode
            let inputFormat = input.inputFormat(forBus: 0)
            logger.info("麦克风输入格式: \(inputFormat.settings)")
            logger.info("麦克风采样率: \(inputFormat.sampleRate), 声道数: \(inputFormat.channelCount)")
            
            // 为麦克风录制安装tap，既用于电平监控又用于文件写入
            installMicrophoneRecordingTap(input: input, format: inputFormat)
        } else {
            // 系统声音模式：连接系统播放节点到混音器
            engine.connect(systemPlayerNode, to: recordMixer, format: mixerOutputFormat)
            logger.info("已连接系统播放节点到混音器")
        }
    }
    
    private func createAudioFile(at url: URL, format: AudioUtils.AudioFormat) throws {
        // 确保目录存在
        fileManager.createDirectoryIfNeeded(at: url.deletingLastPathComponent())
        
        // 检查目录是否真的创建成功
        guard fileManager.fileExists(at: url.deletingLastPathComponent()) else {
            throw NSError(domain: "AudioRecorderController", code: -1, userInfo: [NSLocalizedDescriptionKey: "目录创建失败: \(url.deletingLastPathComponent().path)"])
        }
        
        // 根据录制模式选择音频格式
        let audioSettings: [String: Any]
        if recordingMode == .microphone {
            // 麦克风模式：使用输入节点的格式
            let inputFormat = engine.inputNode.inputFormat(forBus: 0)
            audioSettings = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: inputFormat.sampleRate,
                AVNumberOfChannelsKey: inputFormat.channelCount,
                AVEncoderBitRateKey: 128000
            ]
            logger.info("麦克风录制使用格式: \(audioSettings)")
        } else {
            // 系统音频模式：使用48000Hz采样率（与ScreenCaptureKit一致）
            var settings = format.settings
            settings[AVSampleRateKey] = 48000  // 与ScreenCaptureKit配置一致
            audioSettings = settings
            logger.info("系统音频录制使用格式: \(audioSettings)")
        }
        
        // 创建音频文件
        audioFile = try AVAudioFile(forWriting: url, settings: audioSettings)
        onStatus?("文件创建成功: \(url.lastPathComponent)")
        logger.info("音频文件创建成功: \(url.lastPathComponent)")
        logger.info("文件格式: \(audioFile?.processingFormat.settings ?? [:])")
    }
    
    private func installMixerTap() {
        // 系统音频模式使用ScreenCaptureKit，不需要混音器tap
        guard recordingMode == .microphone, let mixerOutputFormat = mixerFormat else { 
            logger.info("跳过混音器监听安装（系统音频模式使用ScreenCaptureKit）")
            return 
        }
        
        recordMixer.installTap(onBus: 0, bufferSize: 4096, format: mixerOutputFormat) { [weak self] buffer, time in
            guard let self = self, let file = self.audioFile else { return }
            
            // 写入音频文件
            do {
                try file.write(from: buffer)
            } catch {
                self.logger.error("写入音频缓冲区失败: \(error.localizedDescription)")
            }
            
            // 计算并更新电平
            let level = self.calculateRMSLevel(from: buffer)
            
            // 添加调试信息
            if level > 0.01 { // 只在有显著电平时打印
                self.logger.info("录制电平: \(String(format: "%.3f", level)), 帧数: \(buffer.frameLength)")
            }
            
            Task { @MainActor in
                self.onLevel?(level)
            }
        }
        
        logger.info("混音器监听已安装")
    }
    
    private func installPlaybackLevelTap() {
        // 移除之前的tap
        playbackEngine.mainMixerNode.removeTap(onBus: 0)
        
        // 安装新的tap来监控播放电平
        let format = playbackEngine.mainMixerNode.outputFormat(forBus: 0)
        logger.info("播放引擎格式: \(format.settings)")
        
        playbackEngine.mainMixerNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, time in
            guard let self = self else { return }
            
            // 计算并更新电平
            let level = self.calculateRMSLevel(from: buffer)
            
            // 添加调试信息
            if level > 0.01 { // 只在有显著电平时打印
                self.logger.info("播放电平: \(String(format: "%.3f", level)), 帧数: \(buffer.frameLength)")
            }
            
            Task { @MainActor in
                self.onLevel?(level)
            }
        }
        
        logger.info("播放电平监听已安装")
    }
    
    private func installMicrophoneRecordingTap(input: AVAudioInputNode, format: AVAudioFormat) {
        // 移除之前的tap（如果存在）
        input.removeTap(onBus: 0)
        
        // 安装tap来录制麦克风音频并监控电平
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, time in
            guard let self = self else { return }
            
            // 写入音频文件 - 需要格式转换
            if let file = self.audioFile {
                do {
                    // 检查格式是否匹配
                    let fileFormat = file.processingFormat
                    let bufferFormat = buffer.format
                    
                    if fileFormat.isEqual(bufferFormat) {
                        // 格式匹配，直接写入
                        try file.write(from: buffer)
                    } else {
                        // 格式不匹配，需要转换
                        self.logger.warning("音频格式不匹配，文件格式: \(fileFormat.settings), 缓冲区格式: \(bufferFormat.settings)")
                        
                        // 创建格式转换器
                        guard let converter = AVAudioConverter(from: bufferFormat, to: fileFormat) else {
                            self.logger.error("无法创建音频格式转换器")
                            return
                        }
                        
                        // 转换音频数据
                        let convertedBuffer = AVAudioPCMBuffer(pcmFormat: fileFormat, frameCapacity: buffer.frameCapacity)!
                        var error: NSError?
                        let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                            outStatus.pointee = .haveData
                            return buffer
                        }
                        
                        if status == .haveData {
                            try file.write(from: convertedBuffer)
                        } else if let error = error {
                            self.logger.error("音频格式转换失败: \(error.localizedDescription)")
                        }
                    }
                } catch {
                    self.logger.error("写入麦克风音频失败: \(error.localizedDescription)")
                }
            }
            
            // 计算并更新电平
            let level = self.calculateRMSLevel(from: buffer)
            
            // 添加调试信息
            if level > 0.01 { // 只在有显著电平时打印
                self.logger.info("麦克风录制电平: \(String(format: "%.3f", level)), 帧数: \(buffer.frameLength)")
            }
            
            Task { @MainActor in
                self.onLevel?(level)
            }
        }
        
        logger.info("麦克风录制监听已安装")
    }
    
    private func calculateRMSLevel(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0.0 }
        let frameCount = Int(buffer.frameLength)
        
        guard frameCount > 0 else { return 0.0 }
        
        // 计算RMS (Root Mean Square) 电平
        var sum: Float = 0.0
        for i in 0..<frameCount {
            let sample = channelData[i]
            sum += sample * sample
        }
        
        let rms = sqrt(sum / Float(frameCount))
        
        // 转换为0-1范围的电平值，并应用对数缩放
        let level = min(1.0, rms * 20.0) // 放大20倍以便更好地显示
        return level
    }
    
    private func startAudioEngine() throws {
        // 确保不向系统输出声音，避免回授
        engine.mainMixerNode.outputVolume = 0
        
        if recordingMode == .systemAudio {
            // 系统音频模式：将 recordMixer 连接到 mainMixer 以驱动渲染，但保持静音
            engine.connect(recordMixer, to: engine.mainMixerNode, format: mixerFormat)
            logger.info("已连接混音器到主混音器（系统音频模式）")
        } else {
            // 麦克风模式：不需要连接混音器，直接使用输入节点
            logger.info("麦克风模式，跳过混音器连接")
        }
        
        try engine.start()
        logger.info("音频引擎启动成功")
    }
    
    private func startSystemAudioCapture() {
        logger.info("开始系统音频录制（使用ScreenCaptureKit）")
        
        // 检查系统版本
        if #available(macOS 12.3, *) {
            logger.info("系统版本支持ScreenCaptureKit")
        } else {
            onStatus?("系统版本过低，需要macOS 12.3或更高版本")
            logger.error("系统版本不支持ScreenCaptureKit")
            return
        }
        
        // 显示准备状态
        onStatus?("正在准备系统音频录制...")
        
        // 检查屏幕录制权限
        checkScreenRecordingPermission { [weak self] hasPermission in
            guard let self = self else { return }
            
            if !hasPermission {
                Task { @MainActor in
                    self.onStatus?("需要屏幕录制权限才能录制系统声音，请在系统设置中允许")
                }
                self.logger.error("屏幕录制权限不足")
                return
            }
            
            // 获取可共享内容
            Task { [weak self] in
                guard let self = self else { return }
                
                self.logger.info("开始获取可共享内容...")
                do {
                    // 添加超时处理
                    let content = try await withThrowingTaskGroup(of: SCShareableContent.self) { group in
                        group.addTask {
                            try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                        }
                        
                        group.addTask {
                            try await Task.sleep(nanoseconds: 10_000_000_000) // 10秒超时
                            throw NSError(domain: "Timeout", code: -1, userInfo: [NSLocalizedDescriptionKey: "获取可共享内容超时"])
                        }
                        
                        let result = try await group.next()!
                        group.cancelAll()
                        return result
                    }
                    
                    self.logger.info("✅ 获取到可共享内容，显示器数量: \(content.displays.count)")
                    
                    // 检查是否有可用的显示器
                    guard let display = content.displays.first else {
                        self.logger.error("没有可用的显示器")
                        Task { @MainActor in
                            self.onStatus?("没有可用的显示器，无法录制系统音频")
                        }
                        return
                    }
                    
                    self.logger.info("使用显示器: \(display.displayID)")
                    
                    // 创建内容过滤器 - 使用应用程序捕获音频
                    let filter: SCContentFilter
                    
                    // 获取所有运行的应用程序
                    let runningApps = content.applications.filter { $0.applicationName != "audio_record_mac" }
                    self.logger.info("找到 \(runningApps.count) 个可录制的应用程序")
                    
                    if !runningApps.isEmpty {
                        // 使用应用程序过滤器来捕获音频
                        self.logger.info("使用应用程序捕获模式")
                        filter = SCContentFilter(display: display, including: runningApps, exceptingWindows: [])
                    } else {
                        // 如果没有应用程序，使用显示器捕获
                        self.logger.info("使用显示器捕获模式")
                        filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
                    }
                    
                    // 配置流 - 启用音频和视频捕获
                    let config = SCStreamConfiguration()
                    
                    // 音频配置
                    config.capturesAudio = true
                    config.excludesCurrentProcessAudio = true  // 排除当前应用音频，避免回授
                    config.sampleRate = 48000  // 统一使用48000Hz采样率
                    config.channelCount = 2    // 立体声
                    
                    // 视频配置（需要视频流来驱动音频捕获）
                    config.width = 320
                    config.height = 240
                    config.minimumFrameInterval = CMTime(value: 1, timescale: 1) // 1fps，最小帧率
                    config.showsCursor = false
                    
                    self.logger.info("SCStreamConfiguration设置完成 - 音频: \(config.capturesAudio), 尺寸: \(config.width)x\(config.height), 采样率: \(config.sampleRate)")
                    
                    // 创建流
                    do {
                        self.logger.info("正在创建SCStream...")
                        let stream = SCStream(filter: filter, configuration: config, delegate: self)
                        self.logger.info("SCStream创建成功")
                        
                        // 检查delegate设置
                        self.logger.info("SCStream delegate已设置")
                        
                        // 添加音频输出
                        self.logger.info("正在添加音频输出...")
                        let audioOutput = SystemAudioStreamOutput(audioFile: self.audioFile, onLevel: self.onLevel)
                        do {
                            try stream.addStreamOutput(audioOutput, type: .audio, sampleHandlerQueue: DispatchQueue.global(qos: .userInitiated))
                            self.logger.info("✅ 音频输出添加成功")
                        } catch {
                            self.logger.error("❌ 音频输出添加失败: \(error.localizedDescription)")
                            throw error
                        }
                        
                        // 添加视频输出（最小化处理，仅用于驱动音频流）
                        self.logger.info("正在添加视频输出...")
                        let videoOutput = MinimalVideoStreamOutput()
                        do {
                            try stream.addStreamOutput(videoOutput, type: .screen, sampleHandlerQueue: DispatchQueue.global(qos: .utility))
                            self.logger.info("✅ 视频输出添加成功")
                        } catch {
                            self.logger.error("❌ 视频输出添加失败: \(error.localizedDescription)")
                            throw error
                        }
                        
                        // 添加调试：检查stream的输出类型
                        self.logger.info("Stream输出类型检查: 已添加音频和视频输出处理器")
                        
                        // 添加调试：检查stream的状态
                        self.logger.info("Stream配置 - 音频捕获: \(config.capturesAudio), 采样率: \(config.sampleRate)")
                        
                        self.screenCaptureStream = stream
                        self.logger.info("screenCaptureStream已设置")
                        
                        // 开始捕获
                        self.logger.info("准备开始捕获，stream对象: \(stream)")
                        do {
                            try await stream.startCapture()
                            self.logger.info("系统音频录制启动成功")
                            
                            // 启动后检查状态
                            self.logger.info("启动后Stream状态检查完成")
                            
                            // 添加延迟检查，看看是否有数据流
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                self.logger.info("2秒后检查：Stream对象: \(stream)")
                                self.logger.info("2秒后检查：Stream配置: \(config)")
                                
                                // 尝试播放测试音频来验证音频捕获
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
                                
                                // 检查是否是权限问题
                                if error.localizedDescription.contains("permission") || 
                                   error.localizedDescription.contains("权限") ||
                                   error.localizedDescription.contains("denied") {
                                    self.onStatus?("需要屏幕录制权限，请点击权限设置按钮")
                                    return
                                }
                                
                                // 如果是其他错误，尝试重试
                                self.retrySystemAudioCapture()
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
    
    /// 检查屏幕录制权限
    private func checkScreenRecordingPermission(completion: @escaping (Bool) -> Void) {
        // 尝试获取可共享内容来检查权限
        Task {
            do {
                let _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                // 能获取到内容说明权限正常
                completion(true)
            } catch {
                // 检查是否是权限错误
                if error.localizedDescription.contains("permission") || 
                   error.localizedDescription.contains("权限") ||
                   error.localizedDescription.contains("denied") {
                    completion(false)
                } else {
                    // 其他错误，可能权限是有的
                    completion(true)
                }
            }
        }
    }
    
    /// 重试系统音频录制
    private func retrySystemAudioCapture() {
        retryCount += 1
        
        guard retryCount <= 2 else {
            logger.error("系统音频录制重试次数已达上限")
            onStatus?("系统音频录制启动失败，请检查权限设置")
            return
        }
        
        logger.info("系统音频录制重试，第\(retryCount)次尝试")
        
        onStatus?("正在重试系统音频录制...")
        
        // 延迟1秒后重试
        Task { @MainActor in
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1秒
            self.startSystemAudioCapture()
        }
    }
    
    private func createAudioRecording(from url: URL) {
        guard let fileSize = fileManager.getFileSize(at: url) else {
            logger.error("获取录音文件大小失败")
            return
        }
        
        // 获取音频文件信息
        guard let audioInfo = audioUtils.getAudioFileInfo(at: url) else {
            logger.error("获取音频文件信息失败")
            return
        }
        
        let recording = AudioRecording(
            fileURL: url,
            duration: audioInfo.duration,
            fileSize: fileSize,
            format: currentFormat.rawValue,
            recordingMode: recordingMode.rawValue,
            sampleRate: audioInfo.sampleRate,
            channels: Int(audioInfo.channels)
        )
        
        logger.info("音频录音已创建: \(recording.fileName), 时长: \(recording.formattedDuration), 大小: \(recording.formattedFileSize)")
        onRecordingComplete?(recording)
    }
    
}


// MARK: - SCStreamDelegate
extension AudioRecorderController: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in
            self.logger.error("系统音频流停止，错误: \(error.localizedDescription)")
            self.onStatus?("系统音频录制停止: \(error.localizedDescription)")
        }
    }
}

// MARK: - MinimalVideoStreamOutput
class MinimalVideoStreamOutput: NSObject, SCStreamOutput {
    private let logger = Logger.shared
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        // 最小化处理，仅用于驱动音频流
        if type == .screen {
            // 不处理视频数据，仅记录接收
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
        
        // 在主线程上启动定时器检测音频数据接收
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
        
        guard type == .audio else { 
            logger.info("忽略非音频数据，类型: \(type)")
            return 
        }
        
        // 标记已接收到音频数据
        audioDataReceived = true
        
        // 添加详细的音频数据调试信息
        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        let duration = CMTimeGetSeconds(CMSampleBufferGetDuration(sampleBuffer))
        logger.info("🎵 音频样本缓冲区 - 帧数: \(frameCount), 时长: \(duration)秒")
        
        logger.info("🎵 处理音频样本缓冲区，帧数: \(CMSampleBufferGetNumSamples(sampleBuffer))")
        
        // 处理音频样本缓冲区
        guard let audioFile = audioFile else { 
            logger.error("audioFile为nil")
            return 
        }
        
        // 将CMSampleBuffer转换为AVAudioPCMBuffer
        if let audioBuffer = convertToAudioBuffer(from: sampleBuffer) {
            do {
                try audioFile.write(from: audioBuffer)
                
                // 计算电平
                let level = calculateRMSLevel(from: audioBuffer)
                
                // 添加调试信息
                if level > 0.01 { // 只在有显著电平时打印
                    logger.info("系统音频录制电平: \(String(format: "%.3f", level)), 帧数: \(audioBuffer.frameLength)")
                }
                
                // 实时更新电平显示
                DispatchQueue.main.async {
                    self.onLevel?(level)
                }
                
            } catch {
                logger.error("写入系统音频失败: \(error.localizedDescription)")
            }
        } else {
            // 即使转换失败，也要尝试计算原始音频数据的电平
            let level = calculateLevelFromSampleBuffer(sampleBuffer)
            Task { @MainActor in
                self.onLevel?(level)
            }
        }
    }
    
    private func convertToAudioBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else { 
            logger.error("无法获取音频格式描述")
            return nil 
        }
        
        // 创建AVAudioFormat
        let format = AVAudioFormat(cmAudioFormatDescription: formatDescription)
        
        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frameCount > 0 else {
            logger.error("音频帧数为0")
            return nil
        }
        
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else { 
            logger.error("无法创建AVAudioPCMBuffer")
            return nil 
        }
        
        buffer.frameLength = AVAudioFrameCount(frameCount)
        
        // 复制音频数据
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            logger.error("无法获取音频数据缓冲区")
            return nil
        }
        
        var dataPointer: UnsafeMutablePointer<Int8>?
        var length: Int = 0
        
        let status = CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)
        
        guard status == noErr, let dataPtr = dataPointer else {
            logger.error("无法获取音频数据指针")
            return nil
        }
        
        // 根据音频格式复制数据
        if format.isInterleaved {
            // 交错格式
            if let channelData = buffer.int16ChannelData?[0] {
                let samples = UnsafeRawPointer(dataPtr).assumingMemoryBound(to: Int16.self)
                for i in 0..<Int(frameCount) {
                    channelData[i] = samples[i]
                }
            }
        } else {
            // 非交错格式
            if let channelData = buffer.floatChannelData?[0] {
                let samples = UnsafeRawPointer(dataPtr).assumingMemoryBound(to: Float.self)
                for i in 0..<Int(frameCount) {
                    channelData[i] = samples[i]
                }
            }
        }
        
        return buffer
    }
    
    private func calculateRMSLevel(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0.0 }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return 0.0 }
        
        // 计算RMS (Root Mean Square) 电平
        var sum: Float = 0.0
        for i in 0..<frameCount {
            let sample = channelData[i]
            sum += sample * sample
        }
        
        let rms = sqrt(sum / Float(frameCount))
        
        // 转换为0-1范围的电平值，并应用对数缩放
        let level = min(1.0, rms * 20.0) // 放大20倍以便更好地显示
        return level
    }
    
    /// 直接从CMSampleBuffer计算音频电平
    private func calculateLevelFromSampleBuffer(_ sampleBuffer: CMSampleBuffer) -> Float {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return 0.0 }
        
        var dataPointer: UnsafeMutablePointer<Int8>?
        var length: Int = 0
        
        let status = CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)
        
        guard status == noErr, let dataPtr = dataPointer, length > 0 else { return 0.0 }
        
        // 假设是16位PCM数据
        let sampleCount = length / 2
        let samples = UnsafeRawPointer(dataPtr).assumingMemoryBound(to: Int16.self)
        
        var sum: Float = 0.0
        for i in 0..<sampleCount {
            let sample = Float(samples[i]) / Float(Int16.max)
            sum += sample * sample
        }
        
        let rms = sqrt(sum / Float(sampleCount))
        return min(1.0, rms * 20.0)
    }
}

// MARK: - AVAudioPlayerDelegate
extension AudioRecorderController: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.logger.info("播放完成: \(flag)")
            self.levelMonitor.stopMonitoring()
            self.onStatus?(flag ? "播放完成" : "播放失败")
        }
    }
}
