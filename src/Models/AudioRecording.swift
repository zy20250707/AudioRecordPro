import Foundation

/// 录音数据模型
struct AudioRecording: Codable, Identifiable {
    let id: UUID
    let fileName: String
    let fileURL: URL
    let duration: TimeInterval
    let fileSize: Int64
    let format: String
    let recordingMode: String
    let createdAt: Date
    let sampleRate: Double
    let channels: Int
    
    init(fileURL: URL, duration: TimeInterval, fileSize: Int64, format: String, recordingMode: String, sampleRate: Double, channels: Int) {
        self.id = UUID()
        self.fileName = fileURL.lastPathComponent
        self.fileURL = fileURL
        self.duration = duration
        self.fileSize = fileSize
        self.format = format
        self.recordingMode = recordingMode
        self.createdAt = Date()
        self.sampleRate = sampleRate
        self.channels = channels
    }
    
    /// 格式化的持续时间
    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    /// 格式化的文件大小
    var formattedFileSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }
    
    /// 格式化的创建时间
    var formattedCreatedAt: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }
    
    /// 录音模式显示名称
    var recordingModeDisplayName: String {
        switch recordingMode {
        case "microphone":
            return "麦克风"
        case "systemAudio":
            return "系统声音"
        default:
            return recordingMode
        }
    }
}

/// 录音设置模型
struct RecordingSettings {
    var format: AudioUtils.AudioFormat
    var mode: AudioUtils.RecordingMode
    var sampleRate: Double
    var channels: Int
    var quality: Int // 使用Int代替AVAudioQuality
    
    init() {
        self.format = .m4a
        self.mode = .microphone
        self.sampleRate = 48000
        self.channels = 2
        self.quality = 96 // AVAudioQuality.high.rawValue
    }
    
    /// 获取音频格式设置
    func getAudioFormatSettings() -> [String: Any] {
        return format.settings
    }
    
    /// 验证设置
    func validate() -> [String] {
        var errors: [String] = []
        
        if sampleRate <= 0 {
            errors.append("采样率必须大于0")
        }
        
        if channels <= 0 || channels > 8 {
            errors.append("声道数必须在1-8之间")
        }
        
        return errors
    }
}

/// 录音状态枚举
enum RecordingState {
    case idle
    case preparing
    case recording
    case stopping
    case playing
    case error(String)
    
    var displayName: String {
        switch self {
        case .idle:
            return "准备就绪"
        case .preparing:
            return "准备中..."
        case .recording:
            return "录制中..."
        case .stopping:
            return "停止中..."
        case .playing:
            return "播放中..."
        case .error(let message):
            return "错误: \(message)"
        }
    }
    
    var isRecording: Bool {
        if case .recording = self {
            return true
        }
        return false
    }
    
    var isPlaying: Bool {
        if case .playing = self {
            return true
        }
        return false
    }
    
    var isBusy: Bool {
        switch self {
        case .preparing, .recording, .stopping, .playing:
            return true
        default:
            return false
        }
    }
}

/// 应用配置模型
struct AppConfiguration {
    var windowWidth: Double
    var windowHeight: Double
    var autoPlayAfterRecording: Bool
    var showLevelMeter: Bool
    var logLevel: LogLevel
    var maxLogFileSize: Int64
    var logRetentionDays: Int
    
    init() {
        self.windowWidth = 750
        self.windowHeight = 480
        self.autoPlayAfterRecording = true
        self.showLevelMeter = true
        self.logLevel = .info
        self.maxLogFileSize = 10 * 1024 * 1024 // 10MB
        self.logRetentionDays = 7
    }
    
    /// 保存配置到文件
    func save() {
        let configURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("AudioRecordMac")
            .appendingPathComponent("config.json")
        
        do {
            try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            
            // 手动序列化配置
            let configDict: [String: Any] = [
                "windowWidth": windowWidth,
                "windowHeight": windowHeight,
                "autoPlayAfterRecording": autoPlayAfterRecording,
                "showLevelMeter": showLevelMeter,
                "logLevel": logLevel.rawValue,
                "maxLogFileSize": maxLogFileSize,
                "logRetentionDays": logRetentionDays
            ]
            
            let data = try JSONSerialization.data(withJSONObject: configDict, options: .prettyPrinted)
            try data.write(to: configURL)
        } catch {
            Logger.shared.error("保存应用配置失败: \(error.localizedDescription)")
        }
    }
    
    /// 从文件加载配置
    static func load() -> AppConfiguration {
        let configURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("AudioRecordMac")
            .appendingPathComponent("config.json")
        
        do {
            let data = try Data(contentsOf: configURL)
            let configDict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            
            var config = AppConfiguration()
            if let windowWidth = configDict?["windowWidth"] as? Double {
                config.windowWidth = windowWidth
            }
            if let windowHeight = configDict?["windowHeight"] as? Double {
                config.windowHeight = windowHeight
            }
            if let autoPlay = configDict?["autoPlayAfterRecording"] as? Bool {
                config.autoPlayAfterRecording = autoPlay
            }
            if let showMeter = configDict?["showLevelMeter"] as? Bool {
                config.showLevelMeter = showMeter
            }
            if let logLevelString = configDict?["logLevel"] as? String,
               let logLevel = LogLevel(rawValue: logLevelString) {
                config.logLevel = logLevel
            }
            if let maxSize = configDict?["maxLogFileSize"] as? Int64 {
                config.maxLogFileSize = maxSize
            }
            if let retentionDays = configDict?["logRetentionDays"] as? Int {
                config.logRetentionDays = retentionDays
            }
            
            return config
        } catch {
            Logger.shared.info("使用默认配置: \(error.localizedDescription)")
            return AppConfiguration()
        }
    }
}
