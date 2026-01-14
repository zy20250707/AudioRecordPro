import Foundation
import AVFoundation
import CoreAudio
import AudioToolbox

/// 融合录音器 - 同时录制系统音频和麦克风，并混合到一个文件
/// 使用 CoreAudio Process Tap (系统音频) + AVAudioEngine (麦克风)
@available(macOS 14.4, *)
@MainActor
class MixedAudioRecorder: BaseAudioRecorder {
    
    // MARK: - Properties
    
    // 系统音频录制组件 (Process Tap)
    private var processTapManager: ProcessTapManager?
    private var aggregateDeviceManager: AggregateDeviceManager?
    private var systemAudioCallback: AudioCallbackHandler?
    
    // 麦克风录制组件 (AVAudioEngine)
    private let micEngine = AVAudioEngine()
    private var micTapCallCount = 0  // 麦克风Tap回调计数器
    
    // 音频格式
    private var commonFormat: AudioStreamBasicDescription?
    private var targetSampleRate: Double = 48000.0  // 采样率（动态检测）
    
    // 混音缓冲区 - 使用环形缓冲区存储麦克风数据
    private var micRingBuffer: [Float] = []
    private var maxRingBufferSize = 192000  // 2秒的缓冲区（48000 * 2声道 * 2秒），会根据实际采样率调整
    private var micWritePosition = 0
    private var micReadPosition = 0
    private let bufferLock = NSLock()
    
    // 文件管理
    private var audioToolboxFileManager: AudioToolboxFileManager?
    
    // 目标进程
    private var targetPID: pid_t?
    private let processEnumerator = AudioProcessEnumerator()
    
    // MARK: - Initialization
    
    override init(mode: RecordingMode) {
        super.init(mode: mode)
        logger.info("🎙️ 融合录音器初始化")
    }
    
    deinit {
        // cleanup 会在 stopRecording 中调用
    }
    
    // MARK: - Public Methods
    
    /// 设置目标进程PID（可选，不设置则录制系统混音）
    func setTargetPID(_ pid: pid_t?) {
        targetPID = pid
        if let pid = pid {
            logger.info("🎯 设置目标进程PID: \(pid)")
        } else {
            logger.info("🎯 使用系统混音模式")
        }
    }
    
    // MARK: - Recording Implementation
    
    override func startRecording() {
        guard !isRunning else {
            logger.warning("录制已在进行中")
            return
        }
        
        logger.info("🚀 开始融合录音 (系统音频 + 麦克风)")
        
        // 使用 Task 而不是 Task.detached，保持 MainActor 上下文
        Task { @MainActor in
            do {
                // 1. 设置统一的音频格式
                try setupCommonAudioFormat()
                
                // 2. 创建输出文件
                try createOutputFile()
                
                // 3. 启动麦克风录制 (AVAudioEngine) - 在主线程
                try startMicrophoneCapture()
                logger.info("✅ 麦克风引擎已启动，准备启动系统音频捕获...")
                
                // 4. 启动系统音频录制 (Process Tap)
                try await startSystemAudioCapture()
                
                isRunning = true
                onStatus?("正在录制 (系统音频 + 麦克风混音)...")
                logger.info("✅ 融合录音启动成功")
                
            } catch {
                let errorMsg = "融合录音启动失败: \(error.localizedDescription)"
                logger.error(errorMsg)
                onStatus?(errorMsg)
                cleanup()
            }
        }
    }
    
    override func stopRecording() {
        logger.info("🛑 停止融合录音")
        
        // 停止麦克风录制
        stopMicrophoneCapture()
        
        // 停止系统音频录制
        stopSystemAudioCapture()
        
        // 关闭文件
        audioToolboxFileManager?.closeFile()
        audioToolboxFileManager = nil
        
        // 清理资源
        cleanup()
        
        super.stopRecording()
    }
    
    // MARK: - Private Methods - Setup
    
    private func setupCommonAudioFormat() throws {
        // 动态检测当前音频设备的采样率
        let detectedSampleRate = AudioUtils.getCurrentAudioDeviceSampleRate()
        targetSampleRate = detectedSampleRate
        
        // 使用检测到的采样率创建音频格式
        commonFormat = AudioStreamBasicDescription(
            mSampleRate: targetSampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 8,     // 2 channels * 4 bytes (Float32)
            mFramesPerPacket: 1,
            mBytesPerFrame: 8,
            mChannelsPerFrame: 2,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        
        logger.info("📊 音频格式设置: \(targetSampleRate)Hz（动态检测）, 32-bit Float, 立体声")
    }
    
    private func createOutputFile() throws {
        guard let format = commonFormat else {
            throw NSError(domain: "MixedAudioRecorder", code: -1, 
                         userInfo: [NSLocalizedDescriptionKey: "音频格式未设置"])
        }
        
        // 生成文件名：mixed_system+mic_timestamp.wav
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
            .replacingOccurrences(of: ":", with: "-")
        let appName = getTargetAppName() ?? "system"
        let fileName = "mixed_\(appName)+mic_\(timestamp).wav"
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let recordingsPath = documentsPath.appendingPathComponent("AudioRecordings")
        try FileManager.default.createDirectory(at: recordingsPath, withIntermediateDirectories: true)
        
        let fileURL = recordingsPath.appendingPathComponent(fileName)
        outputURL = fileURL
        
        // 创建 AudioToolbox 文件管理器
        audioToolboxFileManager = AudioToolboxFileManager(audioFormat: format)
        try audioToolboxFileManager?.createAudioFile(at: fileURL)
        
        logger.info("📁 创建输出文件: \(fileName)")
    }
    
    // MARK: - System Audio Capture (Process Tap)
    
    private func startSystemAudioCapture() async throws {
        logger.info("🔊 启动系统音频捕获 (Process Tap)...")
        
        // 解析目标进程对象ID
        let processObjectIDs = try await resolveProcessObjectIDs()
        
        // 创建 Process Tap
        processTapManager = ProcessTapManager()
        guard let tapManager = processTapManager,
              tapManager.createProcessTap(for: processObjectIDs) else {
            throw NSError(domain: "MixedAudioRecorder", code: -2,
                         userInfo: [NSLocalizedDescriptionKey: "创建 Process Tap 失败"])
        }
        
        // 读取 Tap 格式
        guard tapManager.readTapStreamFormat() else {
            throw NSError(domain: "MixedAudioRecorder", code: -3,
                         userInfo: [NSLocalizedDescriptionKey: "读取 Tap 格式失败"])
        }
        
        // 创建聚合设备
        aggregateDeviceManager = AggregateDeviceManager()
        guard let aggManager = aggregateDeviceManager,
              let tapUUID = tapManager.uuid,
              aggManager.createAggregateDeviceBindingTap(tapUUID: tapUUID) else {
            throw NSError(domain: "MixedAudioRecorder", code: -4,
                         userInfo: [NSLocalizedDescriptionKey: "创建聚合设备失败"])
        }
        
        // 创建音频回调处理器
        systemAudioCallback = AudioCallbackHandler()
        
        // 设置电平回调（重要！否则没有电平显示）
        systemAudioCallback?.setLevelCallback { [weak self] level in
            // 注意：这里的电平是系统音频的电平，混音后的电平在 updateLevel 中计算
            // 但为了有显示，先使用系统音频的电平
            DispatchQueue.main.async {
                self?.onLevel?(level)
            }
        }
        
        // 设置自定义回调，将系统音频数据写入缓冲区
        systemAudioCallback?.setCustomCallback { [weak self] bufferList, frameCount in
            self?.handleSystemAudioData(bufferList: bufferList, frameCount: frameCount)
        }
        
        // 启动 IO 回调
        let (callback, clientData) = systemAudioCallback!.createAudioCallback()
        guard aggManager.setupIOProcAndStart(callback: callback, clientData: clientData) else {
            throw NSError(domain: "MixedAudioRecorder", code: -5,
                         userInfo: [NSLocalizedDescriptionKey: "启动 IO 回调失败"])
        }
        
        logger.info("✅ 系统音频捕获已启动")
    }
    
    private func stopSystemAudioCapture() {
        aggregateDeviceManager?.stopAndDestroy()
        aggregateDeviceManager = nil
        
        processTapManager?.destroyProcessTap()
        processTapManager = nil
        
        systemAudioCallback = nil
        
        logger.info("✅ 系统音频捕获已停止")
    }
    
    // MARK: - Microphone Capture (AVAudioEngine)
    
    private func startMicrophoneCapture() throws {
        let startTime = Date()
        logger.info("🎤 启动麦克风捕获...")
        
        // 获取麦克风输入节点
        let inputNode = micEngine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        logger.info("⏱️ 获取麦克风格式完成，耗时: \(String(format: "%.2f", Date().timeIntervalSince(startTime)))秒")
        logger.info("🎤 麦克风格式: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount)声道")
        
        // 直接连接到主混音器
        micEngine.connect(inputNode, to: micEngine.mainMixerNode, format: inputFormat)
        
        // 关闭输出音量，避免回音（用户不需要听到自己的声音）
        micEngine.mainMixerNode.outputVolume = 0.0
        logger.info("⏱️ 连接麦克风到主混音器完成，已静音输出，耗时: \(String(format: "%.2f", Date().timeIntervalSince(startTime)))秒")
        
        // 关键：在inputNode上安装tap获取数据
        let bufferSize: AVAudioFrameCount = 4096
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, time in
            guard let self = self else { return }
            self.micTapCallCount += 1
            if self.micTapCallCount <= 5 || self.micTapCallCount % 100 == 0 {
                self.logger.info("🎤 麦克风Tap回调[\(self.micTapCallCount)]: frameLength=\(buffer.frameLength), channels=\(buffer.format.channelCount)")
            }
            self.handleMicrophoneData(buffer: buffer)
        }
        logger.info("⏱️ 在inputNode上安装数据Tap完成，耗时: \(String(format: "%.2f", Date().timeIntervalSince(startTime)))秒")
        
        // 关键：在mainMixerNode上安装空tap，让引擎持续运行！
        // 使用 mainMixerNode 的输出格式（而不是 inputFormat）
        let mainFormat = micEngine.mainMixerNode.outputFormat(forBus: 0)
        micEngine.mainMixerNode.removeTap(onBus: 0)  // 先移除旧tap
        micEngine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: mainFormat) { _, _ in
            // 空tap，只是为了让引擎持续运行
        }
        logger.info("⏱️ 在mainMixerNode上安装驱动Tap完成")
        
        // 准备引擎（重要！）
        micEngine.prepare()
        logger.info("⏱️ 引擎准备完成")
        
        // 启动引擎 - 这是最耗时的操作
        logger.info("⏱️ 准备启动AVAudioEngine...")
        try micEngine.start()
        logger.info("⏱️ AVAudioEngine启动完成，耗时: \(String(format: "%.2f", Date().timeIntervalSince(startTime)))秒")
        
        logger.info("✅ 麦克风捕获已启动，总耗时: \(String(format: "%.2f", Date().timeIntervalSince(startTime)))秒")
    }
    
    private func stopMicrophoneCapture() {
        if micEngine.isRunning {
            micEngine.inputNode.removeTap(onBus: 0)  // 移除数据tap
            micEngine.mainMixerNode.removeTap(onBus: 0)  // 移除驱动tap
            micEngine.stop()
            logger.info("✅ 麦克风捕获已停止")
        }
    }
    
    // MARK: - Audio Data Handling & Mixing
    
    /// 处理系统音频数据
    private func handleSystemAudioData(bufferList: UnsafePointer<AudioBufferList>, frameCount: UInt32) {
        // 调试日志
        struct CallCounter {
            static var count = 0
        }
        CallCounter.count += 1
        if CallCounter.count <= 5 {
            logger.info("🔊 handleSystemAudioData 被调用[\(CallCounter.count)]: frameCount=\(frameCount)")
        }
        
        guard frameCount > 0 else { return }
        
        let ablPointer = UnsafePointer<AudioBufferList>(bufferList)
        let buffer = ablPointer.pointee.mBuffers
        
        guard let data = buffer.mData else { 
            logger.warning("⚠️ 系统音频数据为空")
            return 
        }
        
        // 将系统音频数据转换为 Float 数组
        let floatData = data.assumingMemoryBound(to: Float.self)
        let sampleCount = Int(frameCount * 2)  // 立体声
        let systemData = Array(UnsafeBufferPointer(start: floatData, count: sampleCount))
        
        // 直接混音并写入
        mixAndWriteAudio(systemData: systemData, frameCount: frameCount)
    }
    
    /// 处理麦克风数据 - 写入环形缓冲区
    private func handleMicrophoneData(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { 
            logger.warning("⚠️ 麦克风数据为空，无法处理")
            return 
        }
        
        let frameCount = buffer.frameLength
        let channelCount = Int(buffer.format.channelCount)
        
        guard frameCount > 0 else {
            logger.warning("⚠️ 麦克风帧数为0")
            return
        }
        
        bufferLock.lock()
        defer { bufferLock.unlock() }
        
        // 确保缓冲区已初始化（根据实际采样率调整大小）
        if micRingBuffer.isEmpty {
            // 根据实际采样率计算缓冲区大小：2秒的数据
            maxRingBufferSize = Int(targetSampleRate) * 2 * 2  // 采样率 * 2声道 * 2秒
            micRingBuffer = [Float](repeating: 0, count: maxRingBufferSize)
            logger.info("🎤 环形缓冲区已初始化，大小: \(maxRingBufferSize)（基于\(targetSampleRate)Hz采样率）")
        }
        
        // 将麦克风数据写入环形缓冲区
        for frame in 0..<Int(frameCount) {
            for channel in 0..<2 {  // 总是写入立体声
                let sample: Float
                if channelCount == 1 {
                    // 单声道：两个声道使用相同数据
                    sample = channelData[0][frame]
                } else {
                    // 立体声：使用对应声道
                    sample = channelData[min(channel, channelCount - 1)][frame]
                }
                
                micRingBuffer[micWritePosition] = sample
                micWritePosition = (micWritePosition + 1) % maxRingBufferSize
            }
        }
        
        let samplesWritten = Int(frameCount) * 2  // 立体声
        let available = (micWritePosition - micReadPosition + maxRingBufferSize) % maxRingBufferSize
        
        // 每100次回调记录一次状态
        struct CallCounter {
            static var count = 0
        }
        CallCounter.count += 1
        if CallCounter.count % 100 == 1 {
            logger.debug("🎤 写入麦克风数据: 帧数=\(frameCount), 样本=\(samplesWritten), 缓冲区可用=\(available)")
        }
    }
    
    /// 混音并写入文件
    private func mixAndWriteAudio(systemData: [Float], frameCount: UInt32) {
        let sampleCount = systemData.count
        guard sampleCount > 0 else { 
            logger.warning("⚠️ 系统音频样本数为0")
            return 
        }
        
        // 调试日志
        struct MixCallCounter {
            static var count = 0
        }
        MixCallCounter.count += 1
        if MixCallCounter.count <= 5 {
            logger.info("🎵 mixAndWriteAudio 被调用[\(MixCallCounter.count)]: sampleCount=\(sampleCount)")
        }
        
        // 从环形缓冲区读取麦克风数据
        var micData = [Float](repeating: 0, count: sampleCount)
        
        bufferLock.lock()
        
        // 初始化环形缓冲区（如果需要）
        if micRingBuffer.isEmpty {
            micRingBuffer = [Float](repeating: 0, count: maxRingBufferSize)
        }
        
        // 检查可用数据量
        let availableSamples = (micWritePosition - micReadPosition + maxRingBufferSize) % maxRingBufferSize
        
        if availableSamples >= sampleCount {
            // 有足够的麦克风数据，读取
            for i in 0..<sampleCount {
                micData[i] = micRingBuffer[micReadPosition]
                micReadPosition = (micReadPosition + 1) % maxRingBufferSize
            }
        } else {
            // 麦克风数据不足，用静音填充
            logger.debug("⚠️ 麦克风数据不足: 需要\(sampleCount), 可用\(availableSamples)")
            // micData 已经初始化为0（静音）
            
            // 读取可用的数据
            for i in 0..<min(sampleCount, availableSamples) {
                micData[i] = micRingBuffer[micReadPosition]
                micReadPosition = (micReadPosition + 1) % maxRingBufferSize
            }
        }
        
        bufferLock.unlock()
        
        // 混音
        var mixedData = [Float](repeating: 0, count: sampleCount)
        for i in 0..<sampleCount {
            // 混音算法：60% 系统音频 + 40% 麦克风
            mixedData[i] = systemData[i] * 0.6 + micData[i] * 0.4
            
            // 防止削波（clipping）
            mixedData[i] = max(-1.0, min(1.0, mixedData[i]))
        }
        
        // 写入文件
        writeToFile(mixedData: mixedData, frameCount: frameCount)
    }
    
    /// 写入混音数据到文件
    private func writeToFile(mixedData: [Float], frameCount: UInt32) {
        guard let fileManager = audioToolboxFileManager else { return }
        
        // 创建 AudioBufferList
        var mixedData = mixedData
        let dataSize = mixedData.count * MemoryLayout<Float>.size
        
        mixedData.withUnsafeMutableBytes { rawBufferPointer in
            guard let baseAddress = rawBufferPointer.baseAddress else { return }
            
            let bufferList = AudioBufferList(
                mNumberBuffers: 1,
                mBuffers: AudioBuffer(
                    mNumberChannels: 2,
                    mDataByteSize: UInt32(dataSize),
                    mData: baseAddress
                )
            )
            
            do {
                try fileManager.writeAudioData(bufferList, frameCount: frameCount)
            } catch {
                logger.error("写入音频数据失败: \(error.localizedDescription)")
            }
        }
        
        // 更新电平显示（在闭包外，避免重叠访问）
        updateLevel(from: mixedData)
    }
    
    /// 计算并更新电平
    private func updateLevel(from samples: [Float]) {
        guard !samples.isEmpty else { return }
        
        // 计算 RMS
        let sumOfSquares = samples.reduce(0) { $0 + $1 * $1 }
        let rms = sqrt(sumOfSquares / Float(samples.count))
        let normalizedLevel = min(1.0, rms * 3.0)  // 提高灵敏度
        
        DispatchQueue.main.async {
            self.onLevel?(normalizedLevel)
        }
    }
    
    // MARK: - Helper Methods
    
    private func getTargetAppName() -> String? {
        guard let pid = targetPID else { return nil }
        
        let processes = processEnumerator.getAvailableAudioProcesses()
        return processes.first(where: { $0.pid == pid })?.name
    }
    
    private func resolveProcessObjectIDs() async throws -> [AudioObjectID] {
        var processObjectIDs: [AudioObjectID] = []
        
        if let pid = targetPID {
            // 使用指定的PID
            logger.info("🎯 使用指定PID: \(pid)")
            if let objectID = processEnumerator.findProcessObjectID(by: pid) {
                processObjectIDs.append(objectID)
            } else {
                throw NSError(domain: "MixedAudioRecorder", code: -6,
                             userInfo: [NSLocalizedDescriptionKey: "未找到目标进程"])
            }
        } else {
            // 使用系统混音
            logger.info("🎯 使用系统混音模式")
            if let systemPID = processEnumerator.resolveDefaultSystemMixPID(),
               let objectID = processEnumerator.findProcessObjectID(by: systemPID) {
                processObjectIDs.append(objectID)
            }
        }
        
        return processObjectIDs
    }
    
    private func cleanup() {
        bufferLock.lock()
        micRingBuffer.removeAll()
        micWritePosition = 0
        micReadPosition = 0
        bufferLock.unlock()
    }
}

