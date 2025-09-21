import Foundation
import Darwin
import AVFoundation
import CoreAudio
import AudioToolbox
import CoreMedia

/// 基于 CoreAudio Process Tap 的系统音频录制器（macOS 14.4+）- 重构版本
@available(macOS 14.4, *)
final class CoreAudioProcessTapRecorder: BaseAudioRecorder {
    
    // MARK: - Properties
    /// 目标进程 PID；为 nil 时表示"系统混音"目标
    private var targetPID: pid_t?
    
    // 组件管理器
    private let processEnumerator = AudioProcessEnumerator()
    private var processTapManager: ProcessTapManager?
    private var aggregateDeviceManager: AggregateDeviceManager?
    private let audioCallbackHandler = AudioCallbackHandler()
    
    // MARK: - Initialization
    override init(mode: AudioUtils.RecordingMode) {
        super.init(mode: mode)
    }
    
    /// 指定捕获目标进程 PID（可选）
    func setTargetPID(_ pid: pid_t?) {
        targetPID = pid  // 使用指定的进程PID进行录制
        if let pid = pid {
            logger.info("🎯 设置目标进程PID: \(pid)")
        } else {
            logger.info("🎯 未指定目标进程，将自动选择音频播放应用")
        }
    }
    
    // MARK: - Recording
    override func startRecording() {
        guard !isRunning else {
            logger.warning("录制已在进行中")
            return
        }
        
        // 对于CoreAudio Process Tap，我们需要先获取Tap格式，然后创建匹配的音频文件
        startCoreAudioRecordingWithTapFormat()
    }
    
    private func startCoreAudioRecordingWithTapFormat() {
        // 步骤1: 先创建Process Tap获取格式
        Task { @MainActor in
            do {
                // 解析进程对象
                let processObjectID = try await resolveProcessObjectID()
                
                // 创建Process Tap获取格式
                let testTapManager = ProcessTapManager()
                guard testTapManager.createProcessTap(for: processObjectID) else {
                    self.callOnStatus("创建Process Tap失败")
                    return
                }
                
                guard testTapManager.readTapStreamFormat() else {
                    self.callOnStatus("读取Tap格式失败")
                    testTapManager.destroyProcessTap()
                    return
                }
                
                // 使用Tap格式创建音频文件
                guard let tapFormat = testTapManager.streamFormat else {
                    self.callOnStatus("无法获取Tap格式")
                    testTapManager.destroyProcessTap()
                    return
                }
                
                // 销毁测试Tap
                testTapManager.destroyProcessTap()
                
                // 创建匹配Tap格式的音频文件
                self.createAudioFileWithTapFormat(tapFormat: tapFormat)
                
            } catch {
                self.callOnStatus("初始化失败: \(error.localizedDescription)")
                self.logger.error("初始化失败: \(error.localizedDescription)")
            }
        }
    }
    
    private func createAudioFileWithTapFormat(tapFormat: AudioStreamBasicDescription) {
        // 使用与Tap输入数据一致的格式创建音频文件
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,  // 使用标准PCM格式
            AVSampleRateKey: tapFormat.mSampleRate, // 使用Tap的采样率
            AVNumberOfChannelsKey: tapFormat.mChannelsPerFrame, // 使用Tap的声道数
            AVLinearPCMBitDepthKey: 32,            // 32位深度，与输入数据一致
            AVLinearPCMIsFloatKey: true,           // 使用浮点格式，与输入数据一致
            AVLinearPCMIsBigEndianKey: false,      // 小端序
            AVLinearPCMIsNonInterleaved: false     // 交错格式，确保兼容性
        ]
        
        logger.info("使用Tap格式创建音频文件: \(settings)")
        
        // 使用沙盒支持的文件创建方法
        createAudioFileWithSandboxSupportAndSettings(settings: settings) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let url):
                self.logger.info("音频文件创建成功: \(url.path)")
                // 继续录制流程
                self.continueRecordingProcess()
            case .failure(let error):
                self.onStatus?("创建文件失败: \(error.localizedDescription)")
                self.logger.error("创建文件失败: \(error.localizedDescription)")
            }
        }
    }
    
    private func continueRecordingProcess() {
        
        // 设置音频文件到回调处理器
        if let audioFile = audioFile {
            audioCallbackHandler.setAudioFile(audioFile)
        }
        
        // 设置电平回调
        audioCallbackHandler.setLevelCallback { [weak self] level in
            self?.callOnLevel(level)
        }
        
        // 仅尝试 CoreAudio Process Tap（macOS 14.4+），放到后台线程避免阻塞主线程
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            Task { @MainActor in
                let ok = await self.startCoreAudioProcessTapCapture()
                if ok {
                    self.levelMonitor.startMonitoring(source: .simulated)
                    self.isRunning = true
                    self.callOnStatus("已通过 CoreAudio Process Tap 开始录制")
                } else {
                    let msg = "CoreAudio Process Tap 初始化失败"
                    self.logger.error(msg)
                    self.callOnStatus(msg)
                }
            }
        }
    }
    
    override func stopRecording() {
        // 停止 CoreAudio 录制
        stopCoreAudioProcessTapCapture()
        
        super.stopRecording()
    }
    
    // MARK: - Public Methods
    
    /// 获取所有可用的音频进程列表
    func getAvailableAudioProcesses() -> [AudioProcessInfo] {
        return processEnumerator.getAvailableAudioProcesses()
    }
    
    /// 查找QQ音乐进程并设置为录制目标
    func findAndSetQQMusicTarget() -> Bool {
        logger.info("🎵 开始查找QQ音乐进程...")
        let processes = processEnumerator.getAvailableAudioProcesses()
        
        // 查找QQ音乐相关进程
        let qqMusicProcesses = processes.filter { process in
            let name = process.name.lowercased()
            let bundleID = process.bundleID.lowercased()
            return name.contains("qqmusic") || 
                   name.contains("qq音乐") || 
                   bundleID.contains("qqmusic") ||
                   bundleID.contains("com.tencent.qqmusic")
        }
        
        if qqMusicProcesses.isEmpty {
            logger.warning("⚠️ 未找到QQ音乐进程，请确保QQ音乐正在运行")
            logger.info("📋 当前可用的音频进程:")
            for (index, process) in processes.enumerated() {
                logger.info("   [\(index)] \(process.name) (PID: \(process.pid), Bundle: \(process.bundleID))")
            }
            return false
        }
        
        // 选择第一个找到的QQ音乐进程
        let qqMusicProcess = qqMusicProcesses.first!
        logger.info("✅ 找到QQ音乐进程:")
        logger.info("   名称: \(qqMusicProcess.name)")
        logger.info("   PID: \(qqMusicProcess.pid)")
        logger.info("   Bundle ID: \(qqMusicProcess.bundleID)")
        logger.info("   进程对象ID: \(qqMusicProcess.processObjectID)")
        
        // 设置为目标进程
        setTargetPID(qqMusicProcess.pid)
        logger.info("🎯 已设置QQ音乐为目标录制进程")
        
        return true
    }
    
    /// 专门针对QQ音乐的录制测试
    func testQQMusicRecording() async -> Bool {
        logger.info("🎵 开始QQ音乐专用录制测试...")
        
        // 首先查找QQ音乐进程
        guard findAndSetQQMusicTarget() else {
            logger.error("❌ QQ音乐录制测试失败: 未找到QQ音乐进程")
            return false
        }
        
        // 执行完整的录制流程测试
        guard await testRecordingPipeline() else {
            logger.error("❌ QQ音乐录制测试失败: 录制流程测试失败")
            return false
        }
        
        logger.info("🎉 QQ音乐录制测试全部通过！")
        logger.info("💡 建议: 现在可以开始实际录制QQ音乐的音频输出")
        
        return true
    }
    
    /// 测试录制流程（不实际开始录制）
    func testRecordingPipeline() async -> Bool {
        logger.info("🧪 开始测试录制流程...")
        
        do {
            // 测试步骤1: 解析进程对象
            logger.info("🔍 测试步骤1: 解析目标进程对象...")
            let processObjectID = try await resolveProcessObjectID()
            logger.info("✅ 步骤1测试通过: 进程对象ID=\(processObjectID)")
            
            // 测试步骤2: 创建Process Tap
            logger.info("🔧 测试步骤2: 创建Process Tap...")
            let testTapManager = ProcessTapManager()
            guard testTapManager.createProcessTap(for: processObjectID) else {
                logger.error("❌ 步骤2测试失败: 无法创建Process Tap")
                return false
            }
            logger.info("✅ 步骤2测试通过: Tap创建成功, ID=\(testTapManager.tapObjectID)")
            
            // 测试步骤3: 读取Tap格式
            logger.info("📊 测试步骤3: 读取Tap流格式...")
            guard testTapManager.readTapStreamFormat() else {
                logger.error("❌ 步骤3测试失败: 无法读取Tap格式")
                testTapManager.destroyProcessTap()
                return false
            }
            logger.info("✅ 步骤3测试通过: Tap格式读取成功")
            
            // 测试步骤4: 创建聚合设备
            logger.info("🔗 测试步骤4: 创建聚合设备...")
            let testAggManager = AggregateDeviceManager()
            guard let tapUUID = testTapManager.uuid,
                  testAggManager.createAggregateDeviceBindingTap(tapUUID: tapUUID) else {
                logger.error("❌ 步骤4测试失败: 无法创建聚合设备")
                testTapManager.destroyProcessTap()
                return false
            }
            logger.info("✅ 步骤4测试通过: 聚合设备创建成功, ID=\(testAggManager.deviceID)")
            
            // 测试步骤5: 创建回调函数
            logger.info("🎧 测试步骤5: 创建音频回调...")
            let (callback, clientData) = audioCallbackHandler.createAudioCallback()
            logger.info("✅ 步骤5测试通过: 音频回调创建成功")
            
            // 清理测试资源
            logger.info("🧹 清理测试资源...")
            testAggManager.stopAndDestroy()
            testTapManager.destroyProcessTap()
            
            logger.info("🎉 录制流程测试全部通过！")
            return true
            
        } catch {
            logger.error("❌ 录制流程测试失败: \(error.localizedDescription)")
            return false
        }
    }
    
    // MARK: - Private Methods
    
    @available(macOS 14.4, *)
    private func startCoreAudioProcessTapCapture() async -> Bool {
        logger.info("🎵 CoreAudioProcessTapRecorder: >>> 开始初始化系统音频录制")
        logger.info("🎵 目标进程PID: \(targetPID?.description ?? "系统混音")")
        let tStart = Date()
        
        do {
            // 步骤 1: 解析目标进程对象
            let t1 = Date()
            logger.info("🔍 步骤1: 开始解析目标进程对象...")
            let processObjectID = try await resolveProcessObjectID()
            logger.info("✅ 步骤1完成: 进程对象ID=\(processObjectID), 用时 \(String(format: "%.2fms", Date().timeIntervalSince(t1)*1000))")
            
            // 步骤 2: 创建 Process Tap
            let t2 = Date()
            logger.info("🔧 步骤2: 开始创建Process Tap...")
            processTapManager = ProcessTapManager()
            guard let tapManager = processTapManager,
                  tapManager.createProcessTap(for: processObjectID) else {
                let errorMsg = "❌ 步骤2失败: 创建Process Tap失败（可能SDK未提供符号或进程不可录制）"
                logger.error(errorMsg)
                callOnStatus(errorMsg)
                return false
            }
            logger.info("✅ 步骤2完成: Process Tap创建成功, Tap ID=\(tapManager.tapObjectID), 用时 \(String(format: "%.2fms", Date().timeIntervalSince(t2)*1000))")

            // 步骤 3: 读取 Tap 流格式
            let t3 = Date()
            logger.info("📊 步骤3: 开始读取Tap流格式...")
            guard tapManager.readTapStreamFormat() else {
                let errorMsg = "❌ 步骤3失败: 读取Tap格式失败（kAudioTapPropertyFormat不可用）"
                logger.error(errorMsg)
                callOnStatus(errorMsg)
                return false
            }
            if let format = tapManager.streamFormat {
                logger.info("✅ 步骤3完成: 音频格式 - 采样率=\(format.mSampleRate), 声道数=\(format.mChannelsPerFrame), 位深=\(format.mBitsPerChannel), 用时 \(String(format: "%.2fms", Date().timeIntervalSince(t3)*1000))")
            } else {
                logger.info("✅ 步骤3完成: Tap流格式读取成功, 用时 \(String(format: "%.2fms", Date().timeIntervalSince(t3)*1000))")
            }

            // 步骤 4: 创建聚合设备
            let t4 = Date()
            logger.info("🔗 步骤4: 开始创建聚合设备...")
            aggregateDeviceManager = AggregateDeviceManager()
            guard let aggManager = aggregateDeviceManager,
                  let tapUUID = tapManager.uuid else {
                let errorMsg = "❌ 步骤4失败: 无法获取Tap UUID"
                logger.error(errorMsg)
                callOnStatus(errorMsg)
                return false
            }
            
            logger.info("🔗 绑定Tap UUID: \(tapUUID)")
            guard aggManager.createAggregateDeviceBindingTap(tapUUID: tapUUID) else {
                let errorMsg = "❌ 步骤4失败: 创建/绑定聚合设备失败（新键或API不可用）"
                logger.error(errorMsg)
                callOnStatus(errorMsg)
                return false
            }
            logger.info("✅ 步骤4完成: 聚合设备创建成功, 设备ID=\(aggManager.deviceID), 用时 \(String(format: "%.2fms", Date().timeIntervalSince(t4)*1000))")

            // 步骤 5: 设置 IO 回调并启动
            let t5 = Date()
            logger.info("🎧 步骤5: 开始设置IO回调并启动设备...")
            let (callback, clientData) = audioCallbackHandler.createAudioCallback()
            guard aggManager.setupIOProcAndStart(callback: callback, clientData: clientData) else {
                let errorMsg = "❌ 步骤5失败: 安装IO回调或启动失败"
                logger.error(errorMsg)
                callOnStatus(errorMsg)
                return false
            }
            logger.info("✅ 步骤5完成: IO回调已安装并启动, 用时 \(String(format: "%.2fms", Date().timeIntervalSince(t5)*1000))")
            
            let totalTime = String(format: "%.2fms", Date().timeIntervalSince(tStart)*1000)
            logger.info("🎉 CoreAudioProcessTapRecorder: <<< 初始化完成! 总用时: \(totalTime)")
            logger.info("🎵 系统音频录制已成功启动，开始监听音频数据流...")

            return true
            
        } catch {
            let errorMsg = "❌ CoreAudioProcessTapRecorder初始化失败: \(error.localizedDescription)"
            logger.error(errorMsg)
            callOnStatus(errorMsg)
            return false
        }
    }
    
    @available(macOS 14.4, *)
    private func stopCoreAudioProcessTapCapture() {
        logger.info("CoreAudioProcessTapRecorder: 开始停止与清理")
        
        // 停止聚合设备
        aggregateDeviceManager?.stopAndDestroy()
        aggregateDeviceManager = nil
        
        // 销毁 Process Tap
        processTapManager?.destroyProcessTap()
        processTapManager = nil
        
        logger.info("CoreAudioProcessTapRecorder: 停止与清理完成")
    }
    
    @available(macOS 14.4, *)
    private func resolveProcessObjectID() async throws -> AudioObjectID {
        var pid: pid_t?
        
        if let specified = targetPID {
            pid = specified
            logger.info("🎯 使用指定的目标PID: \(specified)")
        } else {
            // 未指定 PID，使用系统混音
            logger.info("🔍 未指定PID，使用系统混音录制...")
            pid = processEnumerator.resolveDefaultSystemMixPID()
            if let systemPid = pid {
                logger.info("✅ 找到系统混音PID: \(systemPid)")
            } else {
                logger.info("⚠️ 未找到系统混音，使用当前应用程序PID: \(getpid())")
                pid = getpid()
            }
        }
        
        // 如果指定了PID，尝试查找对应的进程对象
        if let pid = pid {
            logger.info("🔍 开始查找PID=\(pid)对应的音频进程对象...")
            
            // 尝试通过进程枚举器查找进程对象 ID
            if let processObjectID = processEnumerator.findProcessObjectID(by: pid) {
                logger.info("✅ 成功找到进程对象ID: \(processObjectID) (PID: \(pid))")
                return processObjectID
            }
            
            logger.warning("⚠️ 未找到指定PID=\(pid)的音频进程，开始枚举所有可用进程...")
        }
        
        // 如果找不到特定进程，尝试选择一个可用的进程
        let availableProcesses = processEnumerator.getAvailableAudioProcesses()
        logger.info("📋 发现 \(availableProcesses.count) 个可用音频进程:")
        
        for (index, process) in availableProcesses.enumerated() {
            logger.info("   [\(index)] \(process.name) (PID: \(process.pid), Bundle: \(process.bundleID))")
        }
        
        // 如果没有指定PID，不允许自动选择，必须明确指定录制目标
        throw NSError(domain: "CoreAudioProcessTapRecorder", code: -1, userInfo: [NSLocalizedDescriptionKey: "未指定录制目标进程，请先选择要录制的进程"])
    }
    
    // MARK: - Static Audio Callback
    
    /// 静态音频回调函数（C 函数指针）
    static let audioCallback: AudioDeviceIOProc = { (inDevice, inNow, inInputData, inInputTime, inOutputData, inOutputTime, inClientData) -> OSStatus in
        // 这里需要实现音频数据处理逻辑
        // 暂时返回成功状态
        return noErr
    }
}
