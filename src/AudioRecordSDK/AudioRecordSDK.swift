import Foundation

/// AudioRecord SDK - 统一导出文件
/// 提供简洁的音频录制 API，支持麦克风录制和混音录制

// MARK: - 核心 API
@available(macOS 14.4, *)
public typealias AudioAPI = AudioRecordAPI

// MARK: - 数据类型
public typealias AudioStream = MediaStream
public typealias AudioTrack = MediaStreamTrack
public typealias AudioError = AudioRecordError

// MARK: - 便捷方法

/// 创建麦克风录制约束
@available(macOS 14.4, *)
public func createMicrophoneConstraints(
    echoCancellation: Bool = true,
    noiseSuppression: Bool = true
) -> AudioConstraints {
    return AudioConstraints(
        echoCancellation: echoCancellation,
        noiseSuppression: noiseSuppression,
        includeSystemAudio: false
    )
}

/// 创建混音录制约束
@available(macOS 14.4, *)
public func createMixedAudioConstraints(
    echoCancellation: Bool = true,
    noiseSuppression: Bool = true
) -> AudioConstraints {
    return AudioConstraints(
        echoCancellation: echoCancellation,
        noiseSuppression: noiseSuppression,
        includeSystemAudio: true
    )
}

// MARK: - SDK 信息
public struct AudioRecordSDKInfo {
    public static let version = "1.0.0"
    public static let name = "AudioRecordSDK"
    public static let description = "macOS 音频录制 SDK，支持麦克风和系统音频混音录制"
    
    public static func printInfo() {
        print("=== \(name) v\(version) ===")
        print(description)
        print("支持功能:")
        print("- 麦克风录制")
        print("- 系统音频录制")
        print("- 混音录制 (麦克风 + 系统音频)")
        print("- 回声消除和噪音抑制")
        print("========================")
    }
}
