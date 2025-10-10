import Foundation
import CoreAudio
import AudioToolbox

// MARK: - SwiftProcessTapManager
/// 使用Swift CoreAudio API的Process Tap管理器
@available(macOS 14.4, *)
class SwiftProcessTapManager {
    
    // MARK: - Properties
    private let logger = Logger.shared
    private var tapID: AudioObjectID = kAudioObjectUnknown
    private var aggregateDeviceID: AudioObjectID = kAudioObjectUnknown
    private var originalOutputDeviceID: AudioDeviceID = kAudioObjectUnknown
    private var tapUUID: UUID?
    
    // MARK: - Public Methods
    
    /// 创建Process Tap（使用Swift API）
    func createProcessTap(for processObjectIDs: [AudioObjectID]) -> Bool {
        logger.info("🔧 SwiftProcessTapManager: 尝试使用Swift CoreAudio API")
        logger.info("🎯 目标进程对象ID列表: \(processObjectIDs)")
        
        do {
            // 1. 创建并配置 Tap 描述
            let tapDescription = CATapDescription()
            tapDescription.name = "Swift System Audio Tap"
            
            if processObjectIDs.isEmpty {
                // 系统混音录制 - 不指定特定进程
                logger.info("🎯 创建系统混音Tap")
                
                // 尝试使用 stereoGlobalTapButExcludeProcesses API（类似Audio Capture Pro）
                logger.info("🔧 尝试使用 stereoGlobalTapButExcludeProcesses API（全局Tap，排除本进程）")
                let globalDesc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
                globalDesc.uuid = UUID()
                globalDesc.muteBehavior = .unmuted
                
                logger.info("📝 全局Tap描述: UUID=\(globalDesc.uuid.uuidString), 静音行为=unmuted")
                
                var globalTapID = AudioObjectID(kAudioObjectUnknown)
                let globalStatus = AudioHardwareCreateProcessTap(globalDesc, &globalTapID)
                if globalStatus == noErr && globalTapID != kAudioObjectUnknown {
                    logger.info("✅ 全局Tap创建成功（类似Audio Capture Pro的方案）")
                    self.tapID = globalTapID
                    self.tapUUID = globalDesc.uuid
                    return true
                } else {
                    logger.warning("⚠️ 全局Tap创建失败: OSStatus=\(globalStatus)，回退到系统混音方案")
                }
                
                // 回退到系统混音录制
                tapDescription.processes = []
            } else {
                // 特定进程录制
                logger.info("🎯 为进程列表创建Tap: \(processObjectIDs)")
                tapDescription.processes = processObjectIDs.map { UInt32($0) }
            }
            
            tapDescription.isPrivate = false
            tapDescription.muteBehavior = .unmuted // 不影响原音频输出
            tapDescription.isMixdown = true
            tapDescription.isMono = false
            
            logger.info("📝 Tap描述: 名称=\(tapDescription.name), 进程数=\(tapDescription.processes.count), 私有=\(tapDescription.isPrivate), 混音=\(tapDescription.isMixdown)")
            
            // 2. 创建 Process Tap
            var tapID = AudioObjectID(kAudioObjectUnknown)
            let status = AudioHardwareCreateProcessTap(tapDescription, &tapID)
            guard status == noErr else {
                logger.error("❌ SwiftProcessTapManager: Process Tap创建失败: OSStatus=\(status)")
                throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: nil)
            }
            self.tapID = tapID
            self.tapUUID = tapDescription.uuid
            
            logger.info("✅ SwiftProcessTapManager: Process Tap创建成功! TapID=\(tapID)")
            return true
            
        } catch {
            logger.error("❌ SwiftProcessTapManager: Process Tap创建失败: \(error)")
            logger.info("🎯 将回退到C API实现")
            return false
        }
    }
    
    /// 创建聚合设备并绑定Tap
    func createAggregateDeviceBindingTap() -> Bool {
        logger.info("🔗 SwiftProcessTapManager: 开始创建聚合设备")
        
        do {
            // 3. 创建聚合设备（确保系统可见）
            let aggregateDeviceDescription: [String: Any] = [
                kAudioAggregateDeviceNameKey: "Swift System Recorder Aggregate Device",
                kAudioAggregateDeviceUIDKey: UUID().uuidString,
                kAudioAggregateDeviceIsPrivateKey: false, // 非私有设备，系统可见
                kAudioAggregateDeviceMainSubDeviceKey: "", // 空的主设备
                kAudioAggregateDeviceIsStackedKey: false // 不堆叠
            ]
            
            var aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
            let aggStatus = AudioHardwareCreateAggregateDevice(aggregateDeviceDescription as CFDictionary, &aggregateDeviceID)
            guard aggStatus == noErr else {
                logger.error("❌ SwiftProcessTapManager: 聚合设备创建失败: OSStatus=\(aggStatus)")
                cleanup()
                throw NSError(domain: NSOSStatusErrorDomain, code: Int(aggStatus), userInfo: nil)
            }
            self.aggregateDeviceID = aggregateDeviceID
            
            logger.info("✅ SwiftProcessTapManager: 聚合设备创建成功! DeviceID=\(aggregateDeviceID)")
            
            // 验证聚合设备是否在系统中可见
            logger.info("🔍 SwiftProcessTapManager: 验证聚合设备是否在系统中可见...")
            var propertyAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceNameCFString,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var deviceName: CFString?
            var propertySize = UInt32(MemoryLayout<CFString>.size)
            let nameStatus = withUnsafeMutablePointer(to: &deviceName) { namePtr in
                AudioObjectGetPropertyData(aggregateDeviceID, &propertyAddress, 0, nil, &propertySize, namePtr)
            }
            
            if nameStatus == noErr, let deviceName = deviceName {
                logger.info("✅ SwiftProcessTapManager: 聚合设备名称: \(deviceName)")
            } else {
                logger.warning("⚠️ SwiftProcessTapManager: 无法获取聚合设备名称，可能未正确注册: \(nameStatus)")
            }
            
            // 4. 使用生成的UUID作为Tap UID（跳过UID获取，直接使用描述中的UUID）
            logger.info("🔗 SwiftProcessTapManager: 使用生成的UUID作为Tap UID")
            guard let tapUUID = self.tapUUID else {
                logger.error("❌ SwiftProcessTapManager: Tap UUID未设置")
                cleanup()
                throw NSError(domain: NSOSStatusErrorDomain, code: -1, userInfo: [NSLocalizedDescriptionKey: "Tap UUID未设置"])
            }
            let tapUID = tapUUID.uuidString as CFString
            logger.info("✅ SwiftProcessTapManager: 使用Tap UID: \(tapUID)")
            
            var tapListPropertyAddress = AudioObjectPropertyAddress(
                mSelector: kAudioAggregateDevicePropertyTapList,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            let tapList: CFArray = [tapUID] as CFArray
            var tapListRef = Unmanaged.passUnretained(tapList).toOpaque()
            let setStatus = AudioObjectSetPropertyData(aggregateDeviceID, &tapListPropertyAddress, 0, nil, UInt32(MemoryLayout<UnsafeRawPointer>.size), &tapListRef)
            guard setStatus == noErr else {
                logger.error("❌ SwiftProcessTapManager: 设置TapList失败: OSStatus=\(setStatus)")
                cleanup()
                throw NSError(domain: NSOSStatusErrorDomain, code: Int(setStatus), userInfo: nil)
            }
            
            logger.info("✅ SwiftProcessTapManager: Tap已添加到聚合设备TapList")
            
            // 5. 保存原始输出设备并切换到聚合设备
            logger.info("🔧 SwiftProcessTapManager: 保存原始输出设备并切换到聚合设备")
            
            // 先获取原始输出设备
            var defaultOutputProperty = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var outputPropertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
            let getStatus = AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &defaultOutputProperty,
                0,
                nil,
                &outputPropertySize,
                &originalOutputDeviceID
            )
            
            if getStatus == noErr {
                logger.info("✅ SwiftProcessTapManager: 已保存原始输出设备ID: \(originalOutputDeviceID)")
            }
            
            // 切换到聚合设备
            let switchStatus = AudioObjectSetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &defaultOutputProperty,
                0,
                nil,
                UInt32(MemoryLayout<AudioDeviceID>.size),
                &aggregateDeviceID
            )
            
            if switchStatus == noErr {
                logger.info("✅ SwiftProcessTapManager: 系统输出设备已自动切换到聚合设备")
                
                // 验证切换是否真的成功
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    var currentOutputDeviceID: AudioDeviceID = kAudioObjectUnknown
                    var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
                    let verifyStatus = AudioObjectGetPropertyData(
                        AudioObjectID(kAudioObjectSystemObject),
                        &defaultOutputProperty,
                        0,
                        nil,
                        &propertySize,
                        &currentOutputDeviceID
                    )
                    
                    if verifyStatus == noErr {
                        if currentOutputDeviceID == aggregateDeviceID {
                            self.logger.info("✅ SwiftProcessTapManager: 验证成功，当前输出设备确实是聚合设备")
                        } else {
                            self.logger.warning("⚠️ SwiftProcessTapManager: 验证失败，当前输出设备ID=\(currentOutputDeviceID)，期望的聚合设备ID=\(aggregateDeviceID)")
                            self.logger.warning("⚠️ 请手动在'系统设置 > 声音 > 输出'中选择 'Swift System Recorder Aggregate Device'")
                        }
                    } else {
                        self.logger.error("❌ SwiftProcessTapManager: 验证当前输出设备失败: \(verifyStatus)")
                    }
                }
            } else {
                logger.error("❌ SwiftProcessTapManager: 自动切换失败: OSStatus=\(switchStatus)")
                logger.warning("⚠️ 请手动在'系统设置 > 声音 > 输出'中选择 'Swift System Recorder Aggregate Device'")
            }
            
            return true
            
        } catch {
            logger.error("❌ SwiftProcessTapManager: 聚合设备创建失败: \(error)")
            cleanup()
            return false
        }
    }
    
    /// 设置IO回调并启动设备
    func setupIOProcAndStart(callback: @escaping AudioDeviceIOProc, clientData: UnsafeMutableRawPointer) -> Bool {
        logger.info("🔧 SwiftProcessTapManager: 设置IO回调并启动设备")
        
        guard aggregateDeviceID != kAudioObjectUnknown else {
            logger.error("❌ SwiftProcessTapManager: 聚合设备无效")
            return false
        }
        
        // 使用传统的IO回调设置方法
        var procID: AudioDeviceIOProcID?
        let createStatus = AudioDeviceCreateIOProcID(aggregateDeviceID, callback, clientData, &procID)
        guard createStatus == noErr, let procID = procID else {
            logger.error("❌ SwiftProcessTapManager: 创建IO回调失败: OSStatus=\(createStatus)")
            return false
        }
        
        let startStatus = AudioDeviceStart(aggregateDeviceID, procID)
        guard startStatus == noErr else {
            logger.error("❌ SwiftProcessTapManager: 启动设备失败: OSStatus=\(startStatus)")
            return false
        }
        
        logger.info("✅ SwiftProcessTapManager: IO回调已安装并启动")
        return true
    }
    
    /// 停止并销毁所有资源
    func stopAndDestroy() {
        logger.info("🛑 SwiftProcessTapManager: 开始停止与清理")
        cleanup()
    }
    
    /// 清理资源
    private func cleanup() {
        // 恢复原始输出设备
        if originalOutputDeviceID != kAudioObjectUnknown {
            logger.info("🔧 SwiftProcessTapManager: 恢复原始输出设备")
            var defaultOutputProperty = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            let restoreStatus = AudioObjectSetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &defaultOutputProperty,
                0,
                nil,
                UInt32(MemoryLayout<AudioDeviceID>.size),
                &originalOutputDeviceID
            )
            if restoreStatus == noErr {
                logger.info("✅ SwiftProcessTapManager: 原始输出设备已恢复")
            } else {
                logger.warning("⚠️ SwiftProcessTapManager: 恢复原始输出设备失败: \(restoreStatus)")
            }
            originalOutputDeviceID = kAudioObjectUnknown
        }
        
        // 销毁聚合设备
        if aggregateDeviceID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = kAudioObjectUnknown
        }
        
        // 销毁Process Tap
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
        }
        
        logger.info("✅ SwiftProcessTapManager: 资源已清理")
    }
    
    /// 获取Process Tap的UID
    var tapUID: CFString? {
        guard tapID != kAudioObjectUnknown else { return nil }
        
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: AudioUtils.kAudioTapPropertyUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var tapUID: CFString? = nil
        var propertySize = UInt32(MemoryLayout<CFString>.size)
        let uidStatus = withUnsafeMutablePointer(to: &tapUID) { tapUIDPtr in
            AudioObjectGetPropertyData(tapID, &propertyAddress, 0, nil, &propertySize, tapUIDPtr)
        }
        return uidStatus == noErr ? tapUID : nil
    }
    
    /// 获取聚合设备ID
    var aggregateDeviceIDValue: AudioDeviceID {
        return aggregateDeviceID
    }
}
