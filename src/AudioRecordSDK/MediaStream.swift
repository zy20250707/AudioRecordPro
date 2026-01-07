import Foundation

/// 音频媒体流
public class MediaStream {
    
    // MARK: - 属性
    public let id: String = UUID().uuidString
    internal let recorder: AudioRecorderProtocol
    private let constraints: AudioConstraints
    private var tracks: [MediaStreamTrack] = []
    
    // MARK: - 计算属性
    public var active: Bool {
        return tracks.contains { $0.readyState == .live }
    }
    
    public var recordingMode: String {
        return constraints.includeSystemAudio ? "mixed" : "microphone"
    }
    
    // MARK: - 初始化
    internal init(recorder: AudioRecorderProtocol, constraints: AudioConstraints) {
        self.recorder = recorder
        self.constraints = constraints
        
        // 创建轨道
        let track = MediaStreamTrack(
            type: constraints.includeSystemAudio ? .mixed : .microphone,
            constraints: constraints
        )
        tracks.append(track)
    }
    
    // MARK: - 公开方法
    
    /// 获取音频轨道
    public func getAudioTracks() -> [MediaStreamTrack] {
        return tracks // 所有轨道都是音频轨道
    }
    
    /// 获取所有轨道
    public func getTracks() -> [MediaStreamTrack] {
        return tracks
    }
    
    // MARK: - 不支持的方法 (抛出错误)
    
    public func addTrack(_ track: MediaStreamTrack) throws {
        throw AudioRecordError.notSupported("addTrack not supported in MVP")
    }
    
    public func removeTrack(_ track: MediaStreamTrack) throws {
        throw AudioRecordError.notSupported("removeTrack not supported in MVP")
    }
    
    public func clone() throws -> MediaStream {
        throw AudioRecordError.notSupported("clone not supported in MVP")
    }
}
