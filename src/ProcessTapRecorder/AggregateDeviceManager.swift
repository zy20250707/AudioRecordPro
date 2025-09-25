import Foundation
import CoreAudio
import AudioToolbox

// MARK: - AggregateDeviceManager
/// 聚合设备管理器 - 负责创建和管理 CoreAudio 聚合设备
@available(macOS 14.4, *)
class AggregateDeviceManager {
    
    // MARK: - Properties
    private let logger = Logger.shared
    private var aggregateDeviceID: AudioDeviceID = 0
    private var ioProcID: AudioDeviceIOProcID?
    
    // MARK: - Public Methods
    
    /// 创建聚合设备并绑定 Tap
    func createAggregateDeviceBindingTap(tapUUID: CFString) -> Bool {
        logger.info("AggregateDeviceManager: 开始创建聚合设备")
        
        typealias CreateAggFn = @convention(c) (CFDictionary, UnsafeMutablePointer<AudioDeviceID>) -> OSStatus
        let handle = dlopen(nil, RTLD_NOW)
        defer { if handle != nil { dlclose(handle) } }
        guard let sym = dlsym(handle, "AudioHardwareCreateAggregateDevice") else {
            logger.warning("AggregateDeviceManager: 符号 AudioHardwareCreateAggregateDevice 不可用")
            return false
        }
        let createAgg = unsafeBitCast(sym, to: CreateAggFn.self)

        // 获取系统默认输出设备 UID
        guard let systemOutputID = readDefaultSystemOutputDeviceID(),
              let outputUID = readDeviceUID(for: systemOutputID) else {
            logger.error("AggregateDeviceManager: 无法获取系统默认输出设备 UID")
            return false
        }

        let aggregateUID = UUID().uuidString
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey as String: "Tap-\(tapUUID)",
            kAudioAggregateDeviceUIDKey as String: aggregateUID,
            kAudioAggregateDeviceMainSubDeviceKey as String: outputUID,
            kAudioAggregateDeviceIsPrivateKey as String: true,
            kAudioAggregateDeviceIsStackedKey as String: false,
            kAudioAggregateDeviceTapAutoStartKey as String: true,
            kAudioAggregateDeviceSubDeviceListKey as String: [
                [kAudioSubDeviceUIDKey as String: outputUID]
            ],
            kAudioAggregateDeviceTapListKey as String: [
                [
                    kAudioSubTapDriftCompensationKey as String: true,  // 参考audio-rec
                    kAudioSubTapUIDKey as String: tapUUID
                ]
            ]
        ]

        var aggID: AudioDeviceID = 0
        let status = createAgg(description as CFDictionary, &aggID)
        if status != noErr || aggID == 0 {
            logger.error("AggregateDeviceManager: 创建聚合设备失败: OSStatus=\(status)")
            return false
        }
        
        self.aggregateDeviceID = aggID
        logger.info("AggregateDeviceManager: 聚合设备创建成功 id=\(aggID)")
        
        // 验证聚合设备是否包含我们的Tap
        logger.info("🔍 AggregateDeviceManager: 验证聚合设备的TapList...")
        var tapListAddress = AudioObjectPropertyAddress(
            mSelector: kAudioAggregateDevicePropertyTapList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var tapListSize: UInt32 = 0
        let tapListSizeStatus = AudioObjectGetPropertyDataSize(aggID, &tapListAddress, 0, nil, &tapListSize)
        if tapListSizeStatus == noErr && tapListSize > 0 {
            logger.info("✅ AggregateDeviceManager: 聚合设备TapList大小: \(tapListSize) bytes")
        } else {
            logger.warning("⚠️ AggregateDeviceManager: 聚合设备TapList验证失败: \(tapListSizeStatus)")
        }
        
        // 尝试将系统输出设备切换到我们的聚合设备
        var defaultOutputProperty = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let switchStatus = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultOutputProperty,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &aggID
        )
        
        if switchStatus == noErr {
            logger.info("✅ AggregateDeviceManager: 系统输出设备已切换到聚合设备")
        } else {
            logger.warning("⚠️ AggregateDeviceManager: 切换系统输出设备失败: \(switchStatus)")
        }
        
        // 尝试激活聚合设备中的Process Tap
        logger.info("🔧 AggregateDeviceManager: 尝试激活聚合设备中的Process Tap")
        var tapAutoStart: UInt32 = 1
        var autoStartAddress = AudioObjectPropertyAddress(
            mSelector: AudioUtils.kAudioAggregateDevicePropertyTapAutoStart,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let autoStartStatus = AudioObjectSetPropertyData(
            aggID,
            &autoStartAddress,
            0,
            nil,
            UInt32(MemoryLayout<UInt32>.size),
            &tapAutoStart
        )
        
        if autoStartStatus == noErr {
            logger.info("✅ AggregateDeviceManager: Process Tap自动启动已启用")
        } else {
            logger.warning("⚠️ AggregateDeviceManager: Process Tap自动启动设置失败: \(autoStartStatus)")
        }
        
        return true
    }
    
    /// 设置 IO 回调并启动设备
    func setupIOProcAndStart(callback: AudioDeviceIOProc, clientData: UnsafeMutableRawPointer) -> Bool {
        logger.info("AggregateDeviceManager: 设置 IO 回调")
        
        guard aggregateDeviceID != 0 else {
            logger.warning("AggregateDeviceManager: 聚合设备无效，无法安装 IOProc")
            return false
        }
        
        // 直接使用传统 API，避免 Block-based API 的复杂性
        logger.info("AggregateDeviceManager: 使用传统 AudioDeviceCreateIOProcID API")
        return setupIOProcAndStartLegacy(callback: callback, clientData: clientData)
    }
    
    /// 停止并销毁聚合设备
    func stopAndDestroy() {
        logger.info("AggregateDeviceManager: 开始停止与清理")
        
        // 停止设备
        if let procID = ioProcID, aggregateDeviceID != 0 {
            let stopStatus = AudioDeviceStop(aggregateDeviceID, procID)
            if stopStatus != noErr {
                logger.warning("AggregateDeviceManager: AudioDeviceStop 失败: \(stopStatus)")
            }
            
            let destroyStatus = AudioDeviceDestroyIOProcID(aggregateDeviceID, procID)
            if destroyStatus != noErr {
                logger.warning("AggregateDeviceManager: AudioDeviceDestroyIOProcID 失败: \(destroyStatus)")
            }
            ioProcID = nil
        }
        
        // 销毁聚合设备
        if aggregateDeviceID != 0 {
            typealias DestroyAggFn = @convention(c) (AudioDeviceID) -> OSStatus
            let handle = dlopen(nil, RTLD_NOW)
            defer { if handle != nil { dlclose(handle) } }
            if let sym = dlsym(handle, "AudioHardwareDestroyAggregateDevice") {
                let destroyAgg = unsafeBitCast(sym, to: DestroyAggFn.self)
                let status = destroyAgg(aggregateDeviceID)
                if status != noErr {
                    logger.warning("AggregateDeviceManager: AudioHardwareDestroyAggregateDevice 失败: \(status)")
                } else {
                    logger.info("AggregateDeviceManager: 聚合设备已销毁")
                }
            }
            aggregateDeviceID = 0
        }
    }
    
    // MARK: - Getters
    
    var deviceID: AudioDeviceID {
        return aggregateDeviceID
    }
    
    var isCreated: Bool {
        return aggregateDeviceID != 0
    }
    
    // MARK: - Private Methods
    
    private func setupIOProcAndStartLegacy(callback: AudioDeviceIOProc, clientData: UnsafeMutableRawPointer) -> Bool {
        logger.info("AggregateDeviceManager: 尝试使用 Block-based API")
        
        // 尝试使用 Block-based API（类似 AudioCap）
        let queue = DispatchQueue(label: "AudioIO", qos: .userInitiated)
        
        let ioBlock: AudioDeviceIOBlock = { [weak self] inNow, inInputData, inInputTime, outOutputData, inOutputTime in
            guard let self = self else { return }
            
            // 直接调用全局回调函数，确保调试信息被正确记录
            let status = globalAudioCallback(
                inDevice: self.aggregateDeviceID,
                inNow: inNow,
                inInputData: inInputData,
                inInputTime: inInputTime,
                inOutputData: outOutputData,
                inOutputTime: inOutputTime,
                inClientData: clientData
            )
            
            if status != noErr {
                self.logger.error("AggregateDeviceManager: 全局回调函数返回错误: \(status)")
            }
        }
        
        var procID: AudioDeviceIOProcID?
        let statusCreate = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateDeviceID, queue, ioBlock)
        if statusCreate != noErr {
            logger.error("AggregateDeviceManager: AudioDeviceCreateIOProcIDWithBlock 失败: \(statusCreate)")
            return false
        }
        
        guard let procID = procID else {
            logger.error("AggregateDeviceManager: 无法创建 Block-based IOProcID")
            return false
        }
        
        self.ioProcID = procID
        let statusStart = AudioDeviceStart(aggregateDeviceID, procID)
        if statusStart != noErr {
            logger.error("AggregateDeviceManager: AudioDeviceStart 失败: \(statusStart)")
            return false
        }
        
        logger.info("AggregateDeviceManager: Block-based IO 回调已安装并启动")
        
        // 尝试强制激活聚合设备
        logger.info("🔧 AggregateDeviceManager: 聚合设备创建完成，等待系统自动激活")
        
        return true
    }
    
    private func readDefaultSystemOutputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioDeviceID = 0
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &deviceID)
        return status == noErr ? deviceID : nil
    }
    
    private func readDeviceUID(for deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var cfstr: CFString?
        var dataSize = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &cfstr) { ptr -> OSStatus in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, ptr)
        }
        return status == noErr ? cfstr as String? : nil
    }
}
