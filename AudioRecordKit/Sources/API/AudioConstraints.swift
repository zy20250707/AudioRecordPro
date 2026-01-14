import Foundation

/// 音频约束参数
public struct AudioConstraints {
    
    // MARK: - 基础参数 (固定值)
    public let sampleRate: Int = 48000        // 固定 48kHz
    public let channelCount: Int = 2          // 固定立体声
    
    // MARK: - 音频处理
    public var echoCancellation: Bool = true
    public var noiseSuppression: Bool = true
    
    // MARK: - 扩展功能
    public var includeSystemAudio: Bool = false
    
    // MARK: - 初始化
    public init(
        echoCancellation: Bool = true,
        noiseSuppression: Bool = true,
        includeSystemAudio: Bool = false
    ) {
        self.echoCancellation = echoCancellation
        self.noiseSuppression = noiseSuppression
        self.includeSystemAudio = includeSystemAudio
    }
}

/// 媒体流约束 (兼容 Web API 结构)
public struct MediaStreamConstraints {
    public var audio: AudioConstraints?
    
    public init(audio: AudioConstraints) {
        self.audio = audio
    }
}
