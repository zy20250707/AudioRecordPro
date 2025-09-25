import Foundation
import CoreAudio
import AudioToolbox

// MARK: - ProcessTapManager
/// Process Tap 管理器 - 负责创建和管理 CoreAudio Process Tap
@available(macOS 14.4, *)
class ProcessTapManager {
    
    // MARK: - Properties
    private let logger = Logger.shared
    private var processTapObjectID: AudioObjectID = 0
    var uuid: CFString?
    private var streamFormatASBD: AudioStreamBasicDescription?
    
    // MARK: - Public Methods
    
    /// 创建 Process Tap（支持多进程混音）
    func createProcessTap(for processObjectIDs: [AudioObjectID]) -> Bool {
        logger.info("🔧 ProcessTapManager: 开始创建Process Tap...")
        logger.info("🎯 目标进程对象ID列表: \(processObjectIDs)")
        
        // 动态符号声明
        typealias CreateTapFn = @convention(c) (CATapDescription, UnsafeMutablePointer<AudioObjectID>) -> OSStatus

        // dlsym 加载符号
        let handle = dlopen(nil, RTLD_NOW)
        defer { if handle != nil { dlclose(handle) } }
        guard let sym = dlsym(handle, "AudioHardwareCreateProcessTap") else {
            logger.error("❌ ProcessTapManager: 符号 AudioHardwareCreateProcessTap 不可用")
            logger.error("💡 提示: 这通常意味着macOS版本不支持或SDK未包含此符号")
            return false
        }
        let createTap = unsafeBitCast(sym, to: CreateTapFn.self)
        logger.info("✅ 成功加载 AudioHardwareCreateProcessTap 符号")

        // 构造 CATapDescription
        let uuid = UUID()
        logger.info("🔑 生成Tap UUID: \(uuid.uuidString)")
        
        var tapID: AudioObjectID = 0
        
        // 检查是否为空列表（系统混音）
        if processObjectIDs.isEmpty {
            logger.info("🎯 ProcessTapManager: 创建系统混音Tap")
            // 系统混音录制
            let systemDesc = CATapDescription(stereoMixdownOfProcesses: [])
            systemDesc.uuid = uuid
            systemDesc.muteBehavior = .unmuted
            
            logger.info("📝 系统混音Tap描述: UUID=\(uuid.uuidString), 静音行为=unmuted")
            
            let systemStatus = createTap(systemDesc, &tapID)
            if systemStatus != noErr || tapID == 0 {
                logger.error("❌ ProcessTapManager: 系统混音Tap创建失败: OSStatus=\(systemStatus)")
                return false
            } else {
                logger.info("✅ 系统混音Tap创建成功")
            }
            self.processTapObjectID = tapID
        } else {
            // 录制特定进程（支持多进程混音）
            logger.info("🎯 ProcessTapManager: 为进程列表创建Tap: \(processObjectIDs)")
            
            // 方法1: 尝试 stereoMixdownOfProcesses (支持多进程)
            logger.info("🔧 尝试方法1: stereoMixdownOfProcesses (多进程混音)")
            let desc = CATapDescription(stereoMixdownOfProcesses: processObjectIDs)
            desc.uuid = uuid
            desc.muteBehavior = .unmuted
            desc.isExclusive = false  // 参考audio-rec
            desc.isMixdown = true     // 参考audio-rec
            
            logger.info("📝 Tap描述: 进程列表=\(processObjectIDs), UUID=\(uuid.uuidString), 静音行为=unmuted, 独占=\(desc.isExclusive), 混音=\(desc.isMixdown)")
            
            let status = createTap(desc, &tapID)
            
            if status != noErr || tapID == 0 {
                logger.warning("⚠️ 多进程混音失败，尝试降级方案")
                
                // 降级方案1: 尝试单个进程
                if processObjectIDs.count > 1 {
                    logger.info("🔄 降级方案1: 尝试单个进程录制")
                    for processObjectID in processObjectIDs {
                        let singleDesc = CATapDescription(stereoMixdownOfProcesses: [processObjectID])
                        singleDesc.uuid = uuid
                        singleDesc.muteBehavior = .unmuted
                        singleDesc.isExclusive = false
                        singleDesc.isMixdown = true
                        
                        logger.info("📝 单进程Tap描述: 进程=\(processObjectID), UUID=\(uuid.uuidString)")
                        
                        let singleStatus = createTap(singleDesc, &tapID)
                        if singleStatus == noErr && tapID != 0 {
                            logger.info("✅ 降级方案1成功: 单进程录制 (PID=\(processObjectID))")
                            self.processTapObjectID = tapID
                            return true
                        }
                    }
                }
                
                // 降级方案2: 尝试系统混音
                logger.info("🔄 降级方案2: 尝试系统混音")
                let systemDesc = CATapDescription(stereoMixdownOfProcesses: [])
                systemDesc.uuid = uuid
                systemDesc.muteBehavior = .unmuted
                
                logger.info("📝 系统混音Tap描述: UUID=\(uuid.uuidString), 静音行为=unmuted")
                
                let systemStatus = createTap(systemDesc, &tapID)
                if systemStatus != noErr || tapID == 0 {
                    logger.error("❌ ProcessTapManager: 所有方法都失败")
                    logger.error("   多进程错误代码: OSStatus=\(status)")
                    logger.error("   系统混音错误代码: OSStatus=\(systemStatus)")
                    logger.error("   返回的Tap ID: \(tapID)")
                    return false
                } else {
                    logger.info("✅ 降级方案2成功: 使用系统混音")
                }
            } else {
                logger.info("✅ 多进程混音成功: 录制 \(processObjectIDs.count) 个进程")
            }
            
            self.processTapObjectID = tapID
        }
        
        logger.info("🎉 ProcessTapManager: Process Tap创建成功!")
        logger.info("   Tap ID: \(tapID)")
        logger.info("   生成的UUID: \(uuid.uuidString)")
        
        // 获取Process Tap的真实UID
        var tapUIDProperty = AudioObjectPropertyAddress(
            mSelector: AudioUtils.kAudioTapPropertyUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var tapUID: CFString?
        var dataSize = UInt32(MemoryLayout<CFString>.size)
        let uidStatus = withUnsafeMutablePointer(to: &tapUID) { tapUIDPtr in
            AudioObjectGetPropertyData(tapID, &tapUIDProperty, 0, nil, &dataSize, tapUIDPtr)
        }
        
        if uidStatus == noErr, let realTapUID = tapUID {
            self.uuid = realTapUID
            logger.info("✅ 获取到Tap真实UID: \(realTapUID)")
        } else {
            logger.error("❌ 无法获取Tap真实UID: \(uidStatus)")
            // 作为后备方案，使用生成的UUID
            self.uuid = uuid.uuidString as CFString
            logger.warning("⚠️ 使用生成的UUID作为后备: \(uuid.uuidString)")
        }
        
        // 尝试手动启动Process Tap
        if let startTapSymbol = dlsym(handle, "AudioHardwareStartProcessTap") {
            let startTap = unsafeBitCast(startTapSymbol, to: (@convention(c) (AudioObjectID, UnsafeMutablePointer<OSStatus>) -> OSStatus).self)
            var startStatus: OSStatus = 0
            startStatus = startTap(tapID, &startStatus)
            if startStatus == noErr {
                logger.info("✅ ProcessTapManager: Process Tap已手动启动")
            } else {
                logger.warning("⚠️ ProcessTapManager: Process Tap手动启动失败: \(startStatus)")
            }
        } else {
            logger.warning("⚠️ ProcessTapManager: AudioHardwareStartProcessTap 符号不可用")
        }
        
        // 尝试使用不同的启动方法
        logger.info("🔧 ProcessTapManager: 尝试使用AudioDeviceStart启动Process Tap")
        let deviceStartStatus = AudioDeviceStart(tapID, nil)
        if deviceStartStatus == noErr {
            logger.info("✅ ProcessTapManager: 使用AudioDeviceStart启动成功")
        } else {
            logger.warning("⚠️ ProcessTapManager: AudioDeviceStart启动失败: \(deviceStartStatus)")
        }
        
        // 检查Process Tap的属性状态
        logger.info("🔍 ProcessTapManager: 检查Process Tap属性状态...")
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunning,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var isRunning: UInt32 = 0
        var runningDataSize = UInt32(MemoryLayout<UInt32>.size)
        let runningStatus = AudioObjectGetPropertyData(tapID, &address, 0, nil, &runningDataSize, &isRunning)
        if runningStatus == noErr {
            logger.info("📊 ProcessTapManager: Tap运行状态: \(isRunning == 1 ? "运行中" : "未运行")")
        } else {
            logger.warning("⚠️ ProcessTapManager: 无法获取Tap运行状态: \(runningStatus)")
        }
        
        // 检查Process Tap是否在设备列表中
        var deviceListSize: UInt32 = 0
        var deviceListAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &deviceListAddress, 0, nil, &deviceListSize)
        let deviceCount = Int(deviceListSize) / MemoryLayout<AudioDeviceID>.size
        logger.info("📊 ProcessTapManager: 系统音频设备总数: \(deviceCount)")
        
        // 检查Tap是否在设备列表中
        var deviceList = Array<AudioDeviceID>(repeating: 0, count: deviceCount)
        let deviceListStatus = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &deviceListAddress, 0, nil, &deviceListSize, &deviceList)
        if deviceListStatus == noErr {
            let tapInList = deviceList.contains(tapID)
            logger.info("📊 ProcessTapManager: Tap是否在设备列表中: \(tapInList ? "是" : "否")")
        }
        
        // 尝试设置Process Tap为活跃状态
        var kAudioTapPropertyIsActive = AudioObjectPropertyAddress(
            mSelector: AudioUtils.kAudioTapPropertyIsActive,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var isActive: UInt32 = 1
        let activeStatus = AudioObjectSetPropertyData(
            tapID,
            &kAudioTapPropertyIsActive,
            0,
            nil,
            UInt32(MemoryLayout<UInt32>.size),
            &isActive
        )
        if activeStatus == noErr {
            logger.info("✅ ProcessTapManager: Process Tap已设置为活跃状态")
        } else {
            logger.warning("⚠️ ProcessTapManager: 设置Process Tap为活跃状态失败: \(activeStatus)")
        }
        
        return true
    }
    
    /// 读取 Tap 流格式
    func readTapStreamFormat() -> Bool {
        logger.info("📊 ProcessTapManager: 开始读取Tap流格式...")
        guard processTapObjectID != 0 else { 
            logger.error("❌ ProcessTapManager: Process Tap未创建，无法读取格式")
            return false 
        }
        
        logger.info("🔍 查询Tap属性: kAudioTapPropertyFormat")
        var address = AudioObjectPropertyAddress(
            mSelector: AudioUtils.kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var asbd = AudioStreamBasicDescription()
        var dataSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioObjectGetPropertyData(processTapObjectID, &address, 0, nil, &dataSize, &asbd)
        if status != noErr {
            logger.warning("⚠️ ProcessTapManager: 读取kAudioTapPropertyFormat失败，使用默认格式")
            logger.warning("   错误代码: OSStatus=\(status)")
            logger.warning("   Tap ID: \(processTapObjectID)")
            
            // 使用默认的音频格式
            asbd = AudioStreamBasicDescription(
                mSampleRate: 48000.0,
                mFormatID: kAudioFormatLinearPCM,
                mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
                mBytesPerPacket: 4,
                mFramesPerPacket: 1,
                mBytesPerFrame: 4,
                mChannelsPerFrame: 2,
                mBitsPerChannel: 16,
                mReserved: 0
            )
            logger.info("📊 使用默认音频格式: 48kHz, 16bit, 立体声")
        }
        
        self.streamFormatASBD = asbd
        logger.info("🎉 ProcessTapManager: Tap流格式读取成功!")
        logger.info("📊 音频格式详情:")
        logger.info("   采样率: \(asbd.mSampleRate) Hz")
        logger.info("   声道数: \(asbd.mChannelsPerFrame)")
        logger.info("   位深: \(asbd.mBitsPerChannel) bit")
        logger.info("   每帧字节数: \(asbd.mBytesPerFrame)")
        logger.info("   每包帧数: \(asbd.mFramesPerPacket)")
        logger.info("   格式ID: \(asbd.mFormatID)")
        logger.info("   格式标志: \(asbd.mFormatFlags)")
        
        return true
    }
    
    /// 销毁 Process Tap
    func destroyProcessTap() {
        logger.info("ProcessTapManager: 开始销毁 Process Tap")
        
        if processTapObjectID != 0 {
            typealias DestroyTapFn = @convention(c) (AudioObjectID) -> OSStatus
            let handle = dlopen(nil, RTLD_NOW)
            defer { if handle != nil { dlclose(handle) } }
            if let sym = dlsym(handle, "AudioHardwareDestroyProcessTap") {
                let destroyTap = unsafeBitCast(sym, to: DestroyTapFn.self)
                let status = destroyTap(processTapObjectID)
                if status != noErr {
                    logger.warning("ProcessTapManager: AudioHardwareDestroyProcessTap 失败: \(status)")
                } else {
                    logger.info("ProcessTapManager: Process Tap 已销毁")
                }
            }
            processTapObjectID = 0
        }
        
        self.uuid = nil
        streamFormatASBD = nil
    }
    
    // MARK: - Getters
    
    var tapObjectID: AudioObjectID {
        return processTapObjectID
    }
    
    var tapUUIDProperty: CFString? {
        return self.uuid
    }
    
    var streamFormat: AudioStreamBasicDescription? {
        return streamFormatASBD
    }
    
    var isCreated: Bool {
        return processTapObjectID != 0
    }
}
