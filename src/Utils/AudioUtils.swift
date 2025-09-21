import Foundation
import AVFoundation
import Accelerate
import ScreenCaptureKit

/// 音频工具类
class AudioUtils {
    static let shared = AudioUtils()
    
    private let logger = Logger.shared
    
    private init() {}
    
    /// 音频格式枚举
    enum AudioFormat: String, CaseIterable {
        case m4a = "M4A"
        case wav = "WAV"
        
        var fileExtension: String {
            return rawValue.lowercased()
        }
        
        var settings: [String: Any] {
            switch self {
            case .m4a:
                return [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 48000,
                    AVNumberOfChannelsKey: 2,
                    AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
                ]
            case .wav:
                return [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: 48000,
                    AVNumberOfChannelsKey: 2,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: false
                ]
            }
        }
        
        var displayName: String {
            return rawValue
        }
    }
    
    /// 录音模式枚举
    enum RecordingMode: String, CaseIterable {
        case microphone = "microphone"
        case specificProcess = "specificProcess"
        case systemMixdown = "systemMixdown"
        
        var displayName: String {
            switch self {
            case .microphone:
                return "麦克风"
            case .specificProcess:
                return "特定进程"
            case .systemMixdown:
                return "系统混音"
            }
        }
        
        var buttonTitle: String {
            switch self {
            case .microphone:
                return "开始录制麦克风"
            case .specificProcess:
                return "开始录制选中进程"
            case .systemMixdown:
                return "开始录制系统混音"
            }
        }
    }
    
    /// 计算音频电平（RMS）
    static func calculateAudioLevel(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0.0 }
        
        let frameCount = Int(buffer.frameLength)
        var sum: Float = 0.0
        
        // 使用 vDSP 计算 RMS
        vDSP_measqv(channelData, 1, &sum, vDSP_Length(frameCount))
        let rms = sqrtf(sum)
        
        // 转换为 dB
        let db = 20 * log10f(max(rms, 1e-6))
        
        // 归一化到 0-1 范围（假设 -60dB 到 0dB）
        let normalized = max(0, min(1, (db + 60) / 60))
        
        return normalized
    }
    
    /// 验证音频文件
    func validateAudioFile(at url: URL) -> Bool {
        do {
            let audioFile = try AVAudioFile(forReading: url)
            let duration = Double(audioFile.length) / audioFile.fileFormat.sampleRate
            logger.info("音频文件验证通过: \(url.lastPathComponent), 时长: \(String(format: "%.2f", duration))秒")
            return duration > 0
        } catch {
            logger.error("音频文件验证失败 \(url.lastPathComponent): \(error.localizedDescription)")
            return false
        }
    }
    
    /// 获取音频文件信息
    func getAudioFileInfo(at url: URL) -> AudioFileInfo? {
        do {
            let audioFile = try AVAudioFile(forReading: url)
            let duration = Double(audioFile.length) / audioFile.fileFormat.sampleRate
            let sampleRate = audioFile.fileFormat.sampleRate
            let channels = audioFile.fileFormat.channelCount
            
            return AudioFileInfo(
                url: url,
                duration: duration,
                sampleRate: sampleRate,
                channels: channels,
                format: audioFile.fileFormat.commonFormat
            )
        } catch {
            logger.error("获取音频文件信息失败 \(url.lastPathComponent): \(error.localizedDescription)")
            return nil
        }
    }
    
    /// 检查音频权限
    func checkAudioPermissions() -> (microphone: Bool, screenRecording: Bool) {
        // 在macOS上，我们通过尝试创建AVAudioEngine来检查麦克风权限
        let microphonePermission = checkMicrophonePermission()
        let screenRecordingPermission = checkScreenRecordingPermission()
        
        logger.info("音频权限 - 麦克风: \(microphonePermission), 屏幕录制: \(screenRecordingPermission)")
        
        return (microphonePermission, screenRecordingPermission)
    }
    
    /// 检查屏幕录制权限
    private func checkScreenRecordingPermission() -> Bool {
        // 通过尝试获取可共享内容来检查屏幕录制权限
        var hasPermission = false
        let semaphore = DispatchSemaphore(value: 0)
        
        Task {
            do {
                let _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                hasPermission = true
            } catch {
                // 检查是否是权限错误
                if error.localizedDescription.contains("permission") || 
                   error.localizedDescription.contains("权限") ||
                   error.localizedDescription.contains("denied") ||
                   error.localizedDescription.contains("not authorized") {
                    hasPermission = false
                } else {
                    // 其他错误，可能权限是有的
                    hasPermission = true
                }
            }
            semaphore.signal()
        }
        
        semaphore.wait()
        return hasPermission
    }
    
    /// 请求屏幕录制权限（通过尝试获取内容来触发系统权限对话框）
    func requestScreenRecordingPermission(completion: @escaping (Bool) -> Void) {
        Task {
            do {
                let _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                DispatchQueue.main.async {
                    completion(true)
                }
            } catch {
                DispatchQueue.main.async {
                    completion(false)
                }
            }
        }
    }
    
    /// 获取详细的权限状态信息
    func getDetailedPermissionStatus() -> (microphone: Bool, screenRecording: Bool, systemVersion: String) {
        let microphonePermission = checkMicrophonePermission()
        let screenRecordingPermission = checkScreenRecordingPermission()
        let systemVersion = ProcessInfo.processInfo.operatingSystemVersionString
        
        return (microphonePermission, screenRecordingPermission, systemVersion)
    }
    
    /// 检查麦克风权限（macOS方式）
    private func checkMicrophonePermission() -> Bool {
        // 在macOS上，我们通过检查系统权限状态来验证麦克风权限
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            return true
        case .notDetermined, .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
    
    /// 请求麦克风权限
    func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        
        switch status {
        case .authorized:
            DispatchQueue.main.async {
                completion(true)
            }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        case .denied, .restricted:
            DispatchQueue.main.async {
                completion(false)
            }
        @unknown default:
            DispatchQueue.main.async {
                completion(false)
            }
        }
    }
}

/// 音频文件信息结构
struct AudioFileInfo {
    let url: URL
    let duration: Double
    let sampleRate: Double
    let channels: AVAudioChannelCount
    let format: AVAudioCommonFormat
    
    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    var formattedSampleRate: String {
        return String(format: "%.0f Hz", sampleRate)
    }
    
    var formattedChannels: String {
        return channels == 1 ? "单声道" : "立体声"
    }
}
