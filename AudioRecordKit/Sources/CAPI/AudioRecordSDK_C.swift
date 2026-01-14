/**
 * AudioRecordSDK C API 实现
 * 
 * 使用 @_cdecl 导出 Swift 函数为 C 函数，供 Chromium/Electron 等调用。
 * 
 * 线程安全说明：
 * - 所有 API 调用在主线程执行
 * - 回调在主线程触发
 * - 内部使用 DispatchQueue 保护共享状态
 */

import Foundation
import AppKit

// MARK: - SDK 版本
private let SDK_VERSION = "1.0.0"

// MARK: - 全局状态管理

/// SDK 实例包装器
@available(macOS 14.4, *)
final class AudioRecordInstance {
    // 回调存储
    var levelCallback: (Float, UnsafeMutableRawPointer?) -> Void = { _, _ in }
    var levelUserData: UnsafeMutableRawPointer?
    var stateCallback: (Int32, UnsafeMutableRawPointer?) -> Void = { _, _ in }
    var stateUserData: UnsafeMutableRawPointer?
    var completeCallback: (String, Int64, UnsafeMutableRawPointer?) -> Void = { _, _, _ in }
    var completeUserData: UnsafeMutableRawPointer?
    var errorCallback: (Int32, String, UnsafeMutableRawPointer?) -> Void = { _, _, _ in }
    var errorUserData: UnsafeMutableRawPointer?
    
    // 配置
    var outputDirectory: String?
    var audioFormat: AudioFormat = .m4a
    var sampleRate: Int32 = 48000
    
    // 状态
    var isRecording = false
    var recordingStartTime: Date?
    
    init() {
        // 在主线程设置回调
        Task { @MainActor in
            self.setupCallbacks()
        }
    }
    
    @MainActor
    private func setupCallbacks() {
        let api = AudioRecordAPI.shared
        
        api.onLevel = { [weak self] level in
            guard let self = self else { return }
            self.levelCallback(level, self.levelUserData)
        }
        
        api.onStatus = { [weak self] status in
            guard let self = self else { return }
            // 简单的状态映射
            var stateValue: Int32 = 0
            if status.contains("录制中") || status.contains("Recording") {
                stateValue = 2
                self.isRecording = true
            } else if status.contains("准备") || status.contains("Preparing") {
                stateValue = 1
            } else if status.contains("停止") || status.contains("Stopping") {
                stateValue = 3
                self.isRecording = false
            } else {
                stateValue = 0
                self.isRecording = false
            }
            self.stateCallback(stateValue, self.stateUserData)
        }
        
        api.onRecordingComplete = { [weak self] recording in
            guard let self = self else { return }
            self.isRecording = false
            let path = recording.fileURL.path
            let durationMs = Int64(recording.duration * 1000)
            self.completeCallback(path, durationMs, self.completeUserData)
        }
    }
    
    /// 获取当前录制时长（毫秒）
    var currentDurationMs: Int64 {
        guard let startTime = recordingStartTime, isRecording else { return 0 }
        return Int64(Date().timeIntervalSince(startTime) * 1000)
    }
}

/// 全局实例存储（使用 Any 避免 @available 问题）
private var instances = [UnsafeMutableRawPointer: Any]()
private let instanceLock = NSLock()

// MARK: - 生命周期管理

@_cdecl("AudioRecord_Create")
public func AudioRecord_Create() -> UnsafeMutableRawPointer? {
    guard #available(macOS 14.4, *) else {
        // macOS 14.4 以下版本不支持
        return nil
    }
    
    let instance = AudioRecordInstance()
    let pointer = Unmanaged.passRetained(instance).toOpaque()
    
    instanceLock.lock()
    instances[pointer] = instance
    instanceLock.unlock()
    
    return pointer
}

@_cdecl("AudioRecord_Destroy")
public func AudioRecord_Destroy(_ handle: UnsafeMutableRawPointer?) {
    guard let handle = handle else { return }
    guard #available(macOS 14.4, *) else { return }
    
    instanceLock.lock()
    if let _ = instances.removeValue(forKey: handle) {
        // 释放引用
        let _ = Unmanaged<AudioRecordInstance>.fromOpaque(handle).takeRetainedValue()
        // 停止录制
        Task { @MainActor in
            AudioRecordAPI.shared.stopRecording()
        }
    }
    instanceLock.unlock()
}

@_cdecl("AudioRecord_GetVersion")
public func AudioRecord_GetVersion() -> UnsafePointer<CChar>? {
    return (SDK_VERSION as NSString).utf8String
}

// MARK: - 辅助函数

@available(macOS 14.4, *)
private func getInstance(_ handle: UnsafeMutableRawPointer?) -> AudioRecordInstance? {
    guard let handle = handle else { return nil }
    instanceLock.lock()
    let instance = instances[handle] as? AudioRecordInstance
    instanceLock.unlock()
    return instance
}

// MARK: - 录制控制

@_cdecl("AudioRecord_Start")
public func AudioRecord_Start(_ handle: UnsafeMutableRawPointer?, _ mode: Int32) -> Int32 {
    guard #available(macOS 14.4, *) else {
        return -8 // SystemVersionTooLow
    }
    guard let instance = getInstance(handle) else {
        return -1 // InvalidHandle
    }
    
    // 检查是否已在录制
    if instance.isRecording {
        return -3 // AlreadyRecording
    }
    
    // 根据模式设置是否包含系统音频
    let includeSystemAudio: Bool
    switch mode {
    case 0: includeSystemAudio = false  // 纯麦克风
    case 1, 2, 3: includeSystemAudio = true  // 系统音频/进程/混音
    default: return -7 // UnsupportedMode
    }
    
    // 创建约束
    let constraints = AudioConstraints(
        echoCancellation: false,
        noiseSuppression: false,
        includeSystemAudio: includeSystemAudio
    )
    
    // 异步启动录制
    Task { @MainActor in
        do {
            let api = AudioRecordAPI.shared
            let stream = try await api.getUserMedia(constraints: constraints)
            try api.startRecording(stream: stream)
            instance.recordingStartTime = Date()
        } catch {
            instance.errorCallback(-99, error.localizedDescription, instance.errorUserData)
        }
    }
    
    return 0 // None
}

@_cdecl("AudioRecord_StartWithProcess")
public func AudioRecord_StartWithProcess(_ handle: UnsafeMutableRawPointer?, _ pid: Int32) -> Int32 {
    guard #available(macOS 14.4, *) else {
        return -8 // SystemVersionTooLow
    }
    guard let instance = getInstance(handle) else {
        return -1 // InvalidHandle
    }
    
    if instance.isRecording {
        return -3 // AlreadyRecording
    }
    
    // 进程录制需要系统音频权限
    // 注意：当前 AudioRecordAPI 不支持指定进程，这里暂时使用系统音频
    // TODO: 扩展 AudioConstraints 支持 targetProcessID
    let constraints = AudioConstraints(
        echoCancellation: false,
        noiseSuppression: false,
        includeSystemAudio: true
    )
    _ = pid  // 暂未使用，预留扩展
    
    Task { @MainActor in
        do {
            let api = AudioRecordAPI.shared
            let stream = try await api.getUserMedia(constraints: constraints)
            try api.startRecording(stream: stream)
            instance.recordingStartTime = Date()
        } catch {
            instance.errorCallback(-99, error.localizedDescription, instance.errorUserData)
        }
    }
    
    return 0
}

@_cdecl("AudioRecord_Stop")
public func AudioRecord_Stop(_ handle: UnsafeMutableRawPointer?) -> Int32 {
    guard #available(macOS 14.4, *) else { return -8 }
    guard let instance = getInstance(handle) else { return -1 }
    
    if !instance.isRecording {
        return -4 // NotRecording
    }
    
    Task { @MainActor in
        AudioRecordAPI.shared.stopRecording()
    }
    instance.recordingStartTime = nil
    return 0
}

@_cdecl("AudioRecord_Pause")
public func AudioRecord_Pause(_ handle: UnsafeMutableRawPointer?) -> Int32 {
    guard #available(macOS 14.4, *) else { return -8 }
    guard getInstance(handle) != nil else { return -1 }
    return -7 // UnsupportedMode - 暂停功能暂未实现
}

@_cdecl("AudioRecord_Resume")
public func AudioRecord_Resume(_ handle: UnsafeMutableRawPointer?) -> Int32 {
    guard #available(macOS 14.4, *) else { return -8 }
    guard getInstance(handle) != nil else { return -1 }
    return -7 // UnsupportedMode - 恢复功能暂未实现
}

@_cdecl("AudioRecord_IsRecording")
public func AudioRecord_IsRecording(_ handle: UnsafeMutableRawPointer?) -> Bool {
    guard #available(macOS 14.4, *) else { return false }
    guard let instance = getInstance(handle) else { return false }
    return instance.isRecording
}

@_cdecl("AudioRecord_GetState")
public func AudioRecord_GetState(_ handle: UnsafeMutableRawPointer?) -> Int32 {
    guard #available(macOS 14.4, *) else { return 0 }
    guard let instance = getInstance(handle) else { return 0 }
    
    // 简化状态：录制中返回 2，否则返回 0
    return instance.isRecording ? 2 : 0
}

@_cdecl("AudioRecord_GetDuration")
public func AudioRecord_GetDuration(_ handle: UnsafeMutableRawPointer?) -> Int64 {
    guard #available(macOS 14.4, *) else { return 0 }
    guard let instance = getInstance(handle) else { return 0 }
    return instance.currentDurationMs
}

// MARK: - 配置

@_cdecl("AudioRecord_SetFormat")
public func AudioRecord_SetFormat(_ handle: UnsafeMutableRawPointer?, _ format: Int32) -> Int32 {
    guard #available(macOS 14.4, *) else { return -8 }
    guard let instance = getInstance(handle) else { return -1 }
    
    switch format {
    case 0: instance.audioFormat = .m4a
    case 1: instance.audioFormat = .wav
    case 2: instance.audioFormat = .m4a  // CAF 暂不支持，使用 M4A
    default: return -7
    }
    
    return 0
}

@_cdecl("AudioRecord_SetSampleRate")
public func AudioRecord_SetSampleRate(_ handle: UnsafeMutableRawPointer?, _ sampleRate: Int32) -> Int32 {
    guard #available(macOS 14.4, *) else { return -8 }
    guard let instance = getInstance(handle) else { return -1 }
    
    instance.sampleRate = sampleRate
    return 0
}

@_cdecl("AudioRecord_SetOutputDirectory")
public func AudioRecord_SetOutputDirectory(_ handle: UnsafeMutableRawPointer?, _ path: UnsafePointer<CChar>?) -> Int32 {
    guard #available(macOS 14.4, *) else { return -8 }
    guard let instance = getInstance(handle), let path = path else { return -1 }
    
    instance.outputDirectory = String(cString: path)
    return 0
}

// MARK: - 回调设置

public typealias CLevelCallback = @convention(c) (Float, UnsafeMutableRawPointer?) -> Void
public typealias CStateCallback = @convention(c) (Int32, UnsafeMutableRawPointer?) -> Void
public typealias CCompleteCallback = @convention(c) (UnsafePointer<CChar>?, Int64, UnsafeMutableRawPointer?) -> Void
public typealias CErrorCallback = @convention(c) (Int32, UnsafePointer<CChar>?, UnsafeMutableRawPointer?) -> Void

@_cdecl("AudioRecord_SetLevelCallback")
public func AudioRecord_SetLevelCallback(
    _ handle: UnsafeMutableRawPointer?,
    _ callback: CLevelCallback?,
    _ userData: UnsafeMutableRawPointer?
) {
    guard #available(macOS 14.4, *) else { return }
    guard let instance = getInstance(handle) else { return }
    
    if let callback = callback {
        instance.levelCallback = { level, data in callback(level, data) }
        instance.levelUserData = userData
    } else {
        instance.levelCallback = { _, _ in }
        instance.levelUserData = nil
    }
}

@_cdecl("AudioRecord_SetStateCallback")
public func AudioRecord_SetStateCallback(
    _ handle: UnsafeMutableRawPointer?,
    _ callback: CStateCallback?,
    _ userData: UnsafeMutableRawPointer?
) {
    guard #available(macOS 14.4, *) else { return }
    guard let instance = getInstance(handle) else { return }
    
    if let callback = callback {
        instance.stateCallback = { state, data in callback(state, data) }
        instance.stateUserData = userData
    } else {
        instance.stateCallback = { _, _ in }
        instance.stateUserData = nil
    }
}

@_cdecl("AudioRecord_SetCompleteCallback")
public func AudioRecord_SetCompleteCallback(
    _ handle: UnsafeMutableRawPointer?,
    _ callback: CCompleteCallback?,
    _ userData: UnsafeMutableRawPointer?
) {
    guard #available(macOS 14.4, *) else { return }
    guard let instance = getInstance(handle) else { return }
    
    if let callback = callback {
        instance.completeCallback = { path, duration, data in
            path.withCString { cPath in callback(cPath, duration, data) }
        }
        instance.completeUserData = userData
    } else {
        instance.completeCallback = { _, _, _ in }
        instance.completeUserData = nil
    }
}

@_cdecl("AudioRecord_SetErrorCallback")
public func AudioRecord_SetErrorCallback(
    _ handle: UnsafeMutableRawPointer?,
    _ callback: CErrorCallback?,
    _ userData: UnsafeMutableRawPointer?
) {
    guard #available(macOS 14.4, *) else { return }
    guard let instance = getInstance(handle) else { return }
    
    if let callback = callback {
        instance.errorCallback = { code, message, data in
            message.withCString { cMsg in callback(code, cMsg, data) }
        }
        instance.errorUserData = userData
    } else {
        instance.errorCallback = { _, _, _ in }
        instance.errorUserData = nil
    }
}

// MARK: - 权限管理

@_cdecl("AudioRecord_GetMicrophonePermission")
public func AudioRecord_GetMicrophonePermission() -> Int32 {
    let status = PermissionManager.shared.getMicrophonePermissionStatus()
    switch status {
    case .notDetermined: return 0
    case .granted: return 1
    case .denied: return 2
    case .restricted: return 3
    }
}

public typealias CPermissionCallback = @convention(c) (Int32, UnsafeMutableRawPointer?) -> Void

@_cdecl("AudioRecord_RequestMicrophonePermission")
public func AudioRecord_RequestMicrophonePermission(
    _ callback: CPermissionCallback?,
    _ userData: UnsafeMutableRawPointer?
) {
    Task { @MainActor in
        let granted = await PermissionManager.shared.requestMicrophonePermissionAsync()
        let status: Int32 = granted ? 1 : 2
        callback?(status, userData)
    }
}

@_cdecl("AudioRecord_GetScreenCapturePermission")
public func AudioRecord_GetScreenCapturePermission() -> Int32 {
    // ScreenCaptureKit 权限检查比较复杂，这里简化处理
    // 实际使用时系统会自动弹窗
    return 0 // NotDetermined
}

// MARK: - 进程枚举

/// 进程列表句柄（内部存储）
private var processListStorage = [OpaquePointer: [AudioProcessInfo]]()
private let processListLock = NSLock()
private let processEnumerator = AudioProcessEnumerator()

/// 获取可录制音频的进程数量
@_cdecl("AudioRecord_GetAudioProcessCount")
public func AudioRecord_GetAudioProcessCount() -> Int32 {
    let processes = processEnumerator.getAvailableAudioProcesses()
    return Int32(processes.count)
}

/// 获取进程列表句柄
@_cdecl("AudioRecord_GetAudioProcesses")
public func AudioRecord_GetAudioProcesses() -> OpaquePointer? {
    let processes = processEnumerator.getAvailableAudioProcesses()
    
    // 创建一个唯一的句柄
    let handle = OpaquePointer(bitPattern: Int.random(in: 1..<Int.max))!
    
    processListLock.lock()
    processListStorage[handle] = processes
    processListLock.unlock()
    
    return handle
}

/// 获取进程列表中的进程数量
@_cdecl("AudioRecord_GetProcessListCount")
public func AudioRecord_GetProcessListCount(_ handle: OpaquePointer?) -> Int32 {
    guard let handle = handle else { return 0 }
    
    processListLock.lock()
    let count = processListStorage[handle]?.count ?? 0
    processListLock.unlock()
    
    return Int32(count)
}

/// 获取指定索引的进程 PID
@_cdecl("AudioRecord_GetProcessPID")
public func AudioRecord_GetProcessPID(_ handle: OpaquePointer?, _ index: Int32) -> Int32 {
    guard let handle = handle else { return -1 }
    
    processListLock.lock()
    let processes = processListStorage[handle]
    processListLock.unlock()
    
    guard let processes = processes, index >= 0 && index < processes.count else { return -1 }
    return processes[Int(index)].pid
}

/// 获取指定索引的进程名称
@_cdecl("AudioRecord_GetProcessName")
public func AudioRecord_GetProcessName(_ handle: OpaquePointer?, _ index: Int32) -> UnsafePointer<CChar>? {
    guard let handle = handle else { return nil }
    
    processListLock.lock()
    let processes = processListStorage[handle]
    processListLock.unlock()
    
    guard let processes = processes, index >= 0 && index < processes.count else { return nil }
    return (processes[Int(index)].name as NSString).utf8String
}

/// 获取指定索引的进程 Bundle ID
@_cdecl("AudioRecord_GetProcessBundleID")
public func AudioRecord_GetProcessBundleID(_ handle: OpaquePointer?, _ index: Int32) -> UnsafePointer<CChar>? {
    guard let handle = handle else { return nil }
    
    processListLock.lock()
    let processes = processListStorage[handle]
    processListLock.unlock()
    
    guard let processes = processes, index >= 0 && index < processes.count else { return nil }
    return ((processes[Int(index)].bundleID ?? "") as NSString).utf8String
}

/// 释放进程列表
@_cdecl("AudioRecord_FreeProcessList")
public func AudioRecord_FreeProcessList(_ handle: OpaquePointer?) {
    guard let handle = handle else { return }
    
    processListLock.lock()
    processListStorage.removeValue(forKey: handle)
    processListLock.unlock()
}

// MARK: - 工具函数

@_cdecl("AudioRecord_GetErrorDescription")
public func AudioRecord_GetErrorDescription(_ error: Int32) -> UnsafePointer<CChar>? {
    let description: String
    switch error {
    case 0: description = "No error"
    case -1: description = "Invalid handle"
    case -2: description = "Permission denied"
    case -3: description = "Already recording"
    case -4: description = "Not recording"
    case -5: description = "Device error"
    case -6: description = "File error"
    case -7: description = "Unsupported mode"
    case -8: description = "System version too low"
    default: description = "Unknown error"
    }
    return (description as NSString).utf8String
}

@_cdecl("AudioRecord_IsModeSupported")
public func AudioRecord_IsModeSupported(_ mode: Int32) -> Bool {
    switch mode {
    case 0: // Microphone
        return true
    case 1, 2, 3: // SystemAudio, SpecificProcess, Mixed
        // 需要 macOS 14.4+ 的 Process Tap
        if #available(macOS 14.4, *) {
            return true
        } else {
            return false
        }
    default:
        return false
    }
}

