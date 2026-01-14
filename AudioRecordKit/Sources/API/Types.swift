import Foundation
import AppKit
import AVFoundation

// MARK: - 公开类型定义
// 这些类型被 SDK 和 App 共同使用，需要公开

/// 录制模式
public enum RecordingMode: String, Sendable {
    case microphone = "microphone"          // 纯麦克风
    case specificProcess = "specificProcess" // 特定进程
    case systemMixdown = "systemMixdown"     // 系统混音
}

/// 音频格式
public enum AudioFormat: String, Sendable {
    case m4a = "m4a"
    case wav = "wav"
    
    public var fileExtension: String {
        return rawValue
    }
    
    public var settings: [String: Any] {
        switch self {
        case .m4a:
            return [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48000.0,
                AVNumberOfChannelsKey: 2,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
        case .wav:
            return [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 48000.0,
                AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
        }
    }
}

/// 录制状态
public enum RecordingState: Sendable {
    case idle       // 空闲
    case preparing  // 准备中
    case recording  // 录制中
    case stopping   // 停止中
    case playing    // 播放中
    case error      // 错误
}

/// 音频进程信息
public struct AudioProcessInfo: Hashable, Sendable {
    public let pid: pid_t
    public let name: String
    public let bundleID: String
    public let path: String
    public let processObjectID: UInt32  // AudioObjectID
    
    public init(pid: pid_t, name: String, bundleID: String = "", path: String = "", processObjectID: UInt32 = 0) {
        self.pid = pid
        self.name = name
        self.bundleID = bundleID
        self.path = path
        self.processObjectID = processObjectID
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(pid)
        hasher.combine(name)
        hasher.combine(bundleID)
    }
    
    public static func == (lhs: AudioProcessInfo, rhs: AudioProcessInfo) -> Bool {
        return lhs.pid == rhs.pid && lhs.name == rhs.name && lhs.bundleID == rhs.bundleID
    }
}

/// 录制文件信息
public struct RecordedFileInfo: Identifiable, Sendable {
    public let id: UUID
    public let url: URL
    public let name: String
    public let date: Date
    public let duration: TimeInterval
    public let size: Int64
    
    public init(url: URL, name: String, date: Date, duration: TimeInterval, size: Int64) {
        self.id = UUID()
        self.url = url
        self.name = name
        self.date = date
        self.duration = duration
        self.size = size
    }
    
    public var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    public var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}

/// 轨道信息
public struct TrackInfo: Sendable {
    public let icon: String
    public let title: String
    public let isActive: Bool
    public let appIcon: NSImage?
    
    public init(icon: String, title: String, isActive: Bool, appIcon: NSImage? = nil) {
        self.icon = icon
        self.title = title
        self.isActive = isActive
        self.appIcon = appIcon
    }
}

