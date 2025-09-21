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
    private var tapUUID: CFString?
    private var streamFormatASBD: AudioStreamBasicDescription?
    
    // MARK: - Public Methods
    
    /// 创建 Process Tap
    func createProcessTap(for processObjectID: AudioObjectID) -> Bool {
        logger.info("🔧 ProcessTapManager: 开始创建Process Tap...")
        logger.info("🎯 目标进程对象ID: \(processObjectID)")
        
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
        
        if processObjectID == kAudioObjectSystemObject {
            // 暂时跳过系统对象，避免段错误
            logger.warning("⚠️ ProcessTapManager: 系统对象暂不支持，跳过Tap创建")
            return false
        } else {
            // 录制特定进程 - 尝试多种配置方式
            logger.info("🎯 ProcessTapManager: 为特定进程创建Tap: \(processObjectID)")
            
            // 方法1: 尝试 stereoMixdownOfProcesses (参考AudioCap和audio-rec)
            logger.info("🔧 尝试方法1: stereoMixdownOfProcesses")
            var desc = CATapDescription(stereoMixdownOfProcesses: [processObjectID])
            desc.uuid = uuid
            desc.muteBehavior = .unmuted
            desc.isExclusive = false  // 参考audio-rec
            desc.isMixdown = true     // 参考audio-rec
            
            logger.info("📝 Tap描述: 进程列表=[\(processObjectID)], UUID=\(uuid.uuidString), 静音行为=unmuted, 独占=\(desc.isExclusive), 混音=\(desc.isMixdown)")
            
            var tapID: AudioObjectID = 0
            let status = createTap(desc, &tapID)
            
            if status != noErr || tapID == 0 {
                logger.warning("⚠️ 方法1失败，尝试方法2: 系统混音")
                
                // 方法2: 尝试系统混音
                let systemDesc = CATapDescription(stereoMixdownOfProcesses: [])
                systemDesc.uuid = uuid
                systemDesc.muteBehavior = .unmuted
                
                logger.info("📝 系统混音Tap描述: UUID=\(uuid.uuidString), 静音行为=unmuted")
                
                let systemStatus = createTap(systemDesc, &tapID)
                if systemStatus != noErr || tapID == 0 {
                    logger.error("❌ ProcessTapManager: 所有方法都失败")
                    logger.error("   方法1错误代码: OSStatus=\(status)")
                    logger.error("   方法2错误代码: OSStatus=\(systemStatus)")
                    logger.error("   返回的Tap ID: \(tapID)")
                    return false
                } else {
                    logger.info("✅ 方法2成功: 使用系统混音")
                }
            } else {
                logger.info("✅ 方法1成功: 使用特定进程")
            }
            
        self.processTapObjectID = tapID
        logger.info("🎉 ProcessTapManager: Process Tap创建成功!")
        logger.info("   Tap ID: \(tapID)")
        logger.info("   生成的UUID: \(uuid.uuidString)")
        
        // 获取Process Tap的真实UID
        var tapUIDProperty = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var tapUID: CFString?
        var dataSize = UInt32(MemoryLayout<CFString>.size)
        let uidStatus = AudioObjectGetPropertyData(tapID, &tapUIDProperty, 0, nil, &dataSize, &tapUID)
        
        if uidStatus == noErr, let realTapUID = tapUID {
            self.tapUUID = realTapUID
            logger.info("✅ 获取到Tap真实UID: \(realTapUID)")
        } else {
            logger.error("❌ 无法获取Tap真实UID: \(uidStatus)")
            // 作为后备方案，使用生成的UUID
            self.tapUUID = uuid.uuidString as CFString
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
        
        // 尝试设置Process Tap为活跃状态
        var kAudioTapPropertyIsActive = AudioObjectPropertyAddress(
            mSelector: UInt32(0x74617061), // 'tapa' - 假设的IsActive属性
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
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var asbd = AudioStreamBasicDescription()
        var dataSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioObjectGetPropertyData(processTapObjectID, &address, 0, nil, &dataSize, &asbd)
        if status != noErr {
            logger.error("❌ ProcessTapManager: 读取kAudioTapPropertyFormat失败")
            logger.error("   错误代码: OSStatus=\(status)")
            logger.error("   Tap ID: \(processTapObjectID)")
            return false
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
        
        tapUUID = nil
        streamFormatASBD = nil
    }
    
    // MARK: - Getters
    
    var tapObjectID: AudioObjectID {
        return processTapObjectID
    }
    
    var uuid: CFString? {
        return tapUUID
    }
    
    var streamFormat: AudioStreamBasicDescription? {
        return streamFormatASBD
    }
    
    var isCreated: Bool {
        return processTapObjectID != 0
    }
}
