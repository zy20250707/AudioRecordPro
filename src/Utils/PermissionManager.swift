import Foundation
import AppKit
import ScreenCaptureKit
import AVFoundation

/// 权限管理器
class PermissionManager {
    static let shared = PermissionManager()
    
    private let logger = Logger.shared
    private var permissionCheckTimer: Timer?
    
    private init() {}
    
    /// 权限状态枚举
    enum PermissionStatus {
        case granted
        case denied
        case notDetermined
        case restricted
    }
    
    /// 权限类型
    enum PermissionType {
        case microphone
        case screenRecording
    }
    
    /// 检查所有权限状态
    func checkAllPermissions() -> (microphone: PermissionStatus, screenRecording: PermissionStatus) {
        let microphoneStatus = checkMicrophonePermission()
        let screenRecordingStatus = checkScreenRecordingPermission()
        
        logger.info("权限检查结果 - 麦克风: \(microphoneStatus), 屏幕录制: \(screenRecordingStatus)")
        
        return (microphoneStatus, screenRecordingStatus)
    }
    
    /// 检查麦克风权限
    private func checkMicrophonePermission() -> PermissionStatus {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        
        switch status {
        case .authorized:
            return .granted
        case .denied:
            return .denied
        case .notDetermined:
            return .notDetermined
        case .restricted:
            return .restricted
        @unknown default:
            return .notDetermined
        }
    }
    
    /// 检查屏幕录制权限（静默检查，不触发系统对话框）
    private func checkScreenRecordingPermission() -> PermissionStatus {
        // 使用最近一次异步检测的缓存或保守返回 .notDetermined
        return lastScreenRecordingStatus ?? .notDetermined
    }

    // 缓存最近一次的屏幕录制权限结果，避免阻塞主线程
    private var lastScreenRecordingStatus: PermissionStatus?
    // 最近一次已回调给外部的屏幕录制权限状态（用于去抖变更通知，避免并发捕获局部变量）
    private var lastEmittedScreenStatus: PermissionStatus?
    
    /// 请求麦克风权限
    func requestMicrophonePermission(completion: @escaping (PermissionStatus) -> Void) {
        let currentStatus = checkMicrophonePermission()
        
        switch currentStatus {
        case .granted:
            completion(.granted)
        case .denied, .restricted:
            completion(currentStatus)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    completion(granted ? .granted : .denied)
                }
            }
        }
    }
    
    /// 请求屏幕录制权限
    func requestScreenRecordingPermission(completion: @escaping (PermissionStatus) -> Void) {
        // 直接尝试获取内容来检查权限并可能触发系统对话框
        Task {
            do {
                // 添加延迟，给系统时间准备
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
                
                let _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                DispatchQueue.main.async {
                    completion(.granted)
                }
            } catch {
                DispatchQueue.main.async {
                    if error.localizedDescription.contains("permission") || 
                       error.localizedDescription.contains("权限") ||
                       error.localizedDescription.contains("denied") ||
                       error.localizedDescription.contains("not authorized") {
                        completion(.denied)
                    } else {
                        completion(.notDetermined)
                    }
                }
            }
        }
    }
    
    /// 真正的屏幕录制权限检查（只在需要时调用）
    func checkScreenRecordingPermissionAsync() async -> PermissionStatus {
        do {
            let _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            await MainActor.run { self.lastScreenRecordingStatus = .granted }
            return .granted
        } catch {
            let denied = error.localizedDescription.contains("permission") ||
                        error.localizedDescription.contains("权限") ||
                        error.localizedDescription.contains("denied") ||
                        error.localizedDescription.contains("not authorized")
            let status: PermissionStatus = denied ? .denied : .notDetermined
            await MainActor.run { self.lastScreenRecordingStatus = status }
            return status
        }
    }
    
    /// 开始权限监控（定期检查权限状态变化）
    func startPermissionMonitoring(interval: TimeInterval = 5.0, onStatusChange: @escaping (PermissionType, PermissionStatus) -> Void) {
        stopPermissionMonitoring()
        
        var lastMicrophoneStatus = checkMicrophonePermission()
        
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            let currentMicrophoneStatus = self.checkMicrophonePermission()
            // 异步检查屏幕录制权限，避免阻塞主线程
            Task { [weak self] in
                guard let self = self else { return }
                let currentScreenRecordingStatus = await self.checkScreenRecordingPermissionAsync()
                await MainActor.run {
                    let previous = self.lastEmittedScreenStatus ?? .notDetermined
                    if currentScreenRecordingStatus != previous {
                        self.lastEmittedScreenStatus = currentScreenRecordingStatus
                        onStatusChange(.screenRecording, currentScreenRecordingStatus)
                    }
                }
            }
            
            // 检查麦克风权限变化
            if currentMicrophoneStatus != lastMicrophoneStatus {
                lastMicrophoneStatus = currentMicrophoneStatus
                onStatusChange(.microphone, currentMicrophoneStatus)
            }
        }
    }
    
    /// 停止权限监控
    func stopPermissionMonitoring() {
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = nil
    }
    
    /// 打开系统偏好设置
    func openSystemPreferences() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }
    
    /// 获取权限状态描述
    func getPermissionStatusDescription(_ status: PermissionStatus) -> String {
        switch status {
        case .granted:
            return "已授权"
        case .denied:
            return "已拒绝"
        case .notDetermined:
            return "未确定"
        case .restricted:
            return "受限制"
        }
    }
    
    /// 获取权限设置指导信息
    func getPermissionGuide(for type: PermissionType) -> String {
        switch type {
        case .microphone:
            return """
            麦克风权限设置：
            1. 打开 系统偏好设置 > 安全性与隐私 > 隐私
            2. 选择左侧的"麦克风"
            3. 勾选"音频录制工具"应用
            """
        case .screenRecording:
            return """
            屏幕录制权限设置：
            1. 打开 系统偏好设置 > 安全性与隐私 > 隐私
            2. 选择左侧的"屏幕录制"
            3. 勾选"音频录制工具"应用
            4. 重启应用程序以生效
            """
        }
    }
}
