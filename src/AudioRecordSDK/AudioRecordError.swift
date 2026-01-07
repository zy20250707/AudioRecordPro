import Foundation

/// 音频录制错误
public enum AudioRecordError: Error, LocalizedError {
    case microphonePermissionDenied
    case systemAudioPermissionDenied
    case deviceNotFound
    case alreadyRecording
    case notSupported(String)
    case unknown(Error)
    
    public var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "麦克风权限被拒绝"
        case .systemAudioPermissionDenied:
            return "系统音频权限被拒绝"
        case .deviceNotFound:
            return "音频设备未找到"
        case .alreadyRecording:
            return "录制已在进行中"
        case .notSupported(let feature):
            return "当前版本不支持: \(feature)"
        case .unknown(let error):
            return "未知错误: \(error.localizedDescription)"
        }
    }
}
