import Foundation

/// 音频媒体轨道
public class MediaStreamTrack {
    
    // MARK: - 枚举
    public enum TrackType {
        case microphone
        case mixed
    }
    
    public enum ReadyState {
        case live
        case ended
    }
    
    // MARK: - 属性
    public let kind: String = "audio"
    public let id: String = UUID().uuidString
    public let label: String
    public var enabled: Bool = true
    public var readyState: ReadyState = .live
    
    private let trackType: TrackType
    private let constraints: AudioConstraints
    
    // MARK: - 初始化
    internal init(type: TrackType, constraints: AudioConstraints) {
        self.trackType = type
        self.constraints = constraints
        
        switch type {
        case .microphone:
            self.label = "Microphone Track"
        case .mixed:
            self.label = "Mixed Audio Track"
        }
    }
    
    // MARK: - 公开方法
    
    /// 停止轨道
    public func stop() {
        readyState = .ended
    }
    
    // MARK: - 不支持的方法 (抛出错误)
    
    public func applyConstraints(_ constraints: [String: Any]) throws {
        throw AudioRecordError.notSupported("applyConstraints not supported in MVP")
    }
    
    public func getSettings() throws -> [String: Any] {
        throw AudioRecordError.notSupported("getSettings not supported in MVP")
    }
    
    public func getConstraints() throws -> [String: Any] {
        throw AudioRecordError.notSupported("getConstraints not supported in MVP")
    }
}
