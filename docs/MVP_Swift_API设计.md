配置 VSCode/Cursor - 自动打开预览# MVP Swift API 设计

## 🎯 设计目标

基于现有工程，抽离出一套简洁的 Swift API，实现 MVP 功能：
1. 麦克风录制
2. 麦克风 + 系统音频混音录制

## 📊 现有工程分析

### 现有架构
```
AudioRecorderController (控制器)
    ├── MicrophoneRecorder (麦克风录制器)
    ├── MixedAudioRecorder (混音录制器)
    └── CoreAudioProcessTapRecorder (系统音频录制器)
```

### 现有接口
- `AudioRecorderProtocol` - 录制器协议
- `BaseAudioRecorder` - 基础录制器类
- `AudioRecorderController` - 多音源控制器

## 🚀 MVP API 设计

### 1. 核心 API 类

```swift
/// 音频录制 API
@MainActor
public class AudioRecordAPI {
    
    // MARK: - 单例
    public static let shared = AudioRecordAPI()
    private init() {}
    
    // MARK: - 私有属性
    private var currentRecorder: AudioRecorderProtocol?
    private let logger = Logger.shared
    
    // MARK: - 公开属性
    public var isRecording: Bool {
        return currentRecorder?.isRunning ?? false
    }
    
    // MARK: - 回调
    public var onLevel: ((Float) -> Void)?
    public var onStatus: ((String) -> Void)?
    public var onRecordingComplete: ((AudioRecording) -> Void)?
    
    // MARK: - 核心 API
    
    /// 获取媒体流
    /// - Parameter constraints: 音频约束
    /// - Returns: 媒体流对象
    public func getUserMedia(constraints: AudioConstraints) async throws -> MediaStream {
        
        // 检查权限
        try await checkPermissions(for: constraints)
        
        // 创建对应的录制器
        let recorder = try createRecorder(for: constraints)
        
        // 创建媒体流
        let stream = MediaStream(recorder: recorder, constraints: constraints)
        
        return stream
    }
    
    /// 开始录制
    /// - Parameter stream: 媒体流
    public func startRecording(stream: MediaStream) throws {
        guard !isRecording else {
            throw MVPAudioError.alreadyRecording
        }
        
        currentRecorder = stream.recorder
        setupRecorderCallbacks()
        currentRecorder?.startRecording()
    }
    
    /// 停止录制
    public func stopRecording() {
        currentRecorder?.stopRecording()
        currentRecorder = nil
    }
    
    // MARK: - 私有方法
    
    private func checkPermissions(for constraints: AudioConstraints) async throws {
        // 检查麦克风权限
        let micPermission = await AVAudioSession.sharedInstance().requestRecordPermission()
        guard micPermission else {
            throw AudioRecordError.microphonePermissionDenied
        }
        
        // 如果需要系统音频，检查相关权限
        if constraints.includeSystemAudio {
            // 这里可以添加系统音频权限检查
            logger.info("需要系统音频权限")
        }
    }
    
    private func createRecorder(for constraints: AudioConstraints) throws -> AudioRecorderProtocol {
        if constraints.includeSystemAudio {
            // 创建混音录制器
            let recorder = MixedAudioRecorder(mode: .systemMixdown)
            return recorder
        } else {
            // 创建麦克风录制器
            let recorder = MicrophoneRecorder(mode: .microphone)
            return recorder
        }
    }
    
    private func setupRecorderCallbacks() {
        currentRecorder?.onLevel = { [weak self] level in
            self?.onLevel?(level)
        }
        
        currentRecorder?.onStatus = { [weak self] status in
            self?.onStatus?(status)
        }
        
        currentRecorder?.onRecordingComplete = { [weak self] recording in
            self?.onRecordingComplete?(recording)
        }
    }
}
```

### 2. 约束参数类

```swift
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
```

### 3. 媒体流类

```swift
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
```

### 4. 媒体轨道类

```swift
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
```

### 5. 错误类型

```swift
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
```

## 📝 使用示例

### 1. 基础麦克风录制

```swift
import Foundation

class AudioRecordingManager {
    private let audioAPI = AudioRecordAPI.shared
    private var currentStream: MediaStream?
    
    func startMicrophoneRecording() async {
        do {
            // 1. 创建约束
            let constraints = AudioConstraints(
                echoCancellation: true,
                noiseSuppression: true,
                includeSystemAudio: false
            )
            
            // 2. 获取媒体流
            let stream = try await audioAPI.getUserMedia(constraints: constraints)
            currentStream = stream
            
            // 3. 设置回调
            audioAPI.onLevel = { level in
                print("音频电平: \(level)")
            }
            
            audioAPI.onStatus = { status in
                print("状态: \(status)")
            }
            
            audioAPI.onRecordingComplete = { recording in
                print("录制完成: \(recording.fileName)")
            }
            
            // 4. 开始录制
            try audioAPI.startRecording(stream: stream)
            
            print("麦克风录制已开始")
            
        } catch {
            print("录制失败: \(error.localizedDescription)")
        }
    }
    
    func stopRecording() {
        audioAPI.stopRecording()
        currentStream = nil
        print("录制已停止")
    }
}
```

### 2. 混音录制

```swift
class MixedAudioRecordingManager {
    private let audioAPI = AudioRecordAPI.shared
    
    func startMixedRecording() async {
        do {
            // 1. 创建混音约束
            let constraints = AudioConstraints(
                echoCancellation: true,
                noiseSuppression: true,
                includeSystemAudio: true  // 启用系统音频
            )
            
            // 2. 获取媒体流
            let stream = try await audioAPI.getUserMedia(constraints: constraints)
            
            // 3. 检查录制模式
            print("录制模式: \(stream.recordingMode)") // "mixed"
            print("轨道数: \(stream.getAudioTracks().count)") // 1
            
            // 4. 开始录制
            try audioAPI.startRecording(stream: stream)
            
            print("混音录制已开始 (麦克风 + 系统音频)")
            
        } catch {
            print("混音录制失败: \(error.localizedDescription)")
        }
    }
}
```

### 3. 完整的录制应用

```swift
@MainActor
class MVPRecordingApp: ObservableObject {
    @Published var isRecording = false
    @Published var audioLevel: Float = 0.0
    @Published var status = "准备就绪"
    
    private let audioAPI = AudioRecordAPI.shared
    private var currentStream: MediaStream?
    
    init() {
        setupCallbacks()
    }
    
    private func setupCallbacks() {
        audioAPI.onLevel = { [weak self] level in
            Task { @MainActor in
                self?.audioLevel = level
            }
        }
        
        audioAPI.onStatus = { [weak self] status in
            Task { @MainActor in
                self?.status = status
            }
        }
        
        audioAPI.onRecordingComplete = { [weak self] recording in
            Task { @MainActor in
                self?.isRecording = false
                self?.status = "录制完成: \(recording.fileName)"
            }
        }
    }
    
    func startMicrophoneRecording() async {
        await startRecording(includeSystemAudio: false)
    }
    
    func startMixedRecording() async {
        await startRecording(includeSystemAudio: true)
    }
    
    private func startRecording(includeSystemAudio: Bool) async {
        do {
            let constraints = AudioConstraints(
                includeSystemAudio: includeSystemAudio
            )
            
            let stream = try await audioAPI.getUserMedia(constraints: constraints)
            currentStream = stream
            
            try audioAPI.startRecording(stream: stream)
            
            isRecording = true
            status = includeSystemAudio ? "混音录制中..." : "麦克风录制中..."
            
        } catch {
            status = "录制失败: \(error.localizedDescription)"
        }
    }
    
    func stopRecording() {
        audioAPI.stopRecording()
        currentStream = nil
        isRecording = false
        status = "录制已停止"
    }
}
```

## 🔧 集成到现有工程

### 1. 文件结构
```
src/
├── AudioRecord/
│   ├── AudioRecordAPI.swift        // 核心 API
│   ├── AudioConstraints.swift      // 约束参数
│   ├── MediaStream.swift           // 媒体流
│   ├── MediaStreamTrack.swift      // 媒体轨道
│   └── AudioRecordError.swift      // 错误定义
├── Recorder/                       // 现有录制器 (复用)
│   ├── MicrophoneRecorder.swift
│   ├── MixedAudioRecorder.swift
│   └── BaseAudioRecorder.swift
└── Utils/                          // 现有工具类 (复用)
    ├── Logger.swift
    └── FileManagerUtils.swift
```

### 2. 依赖关系
```
AudioRecordAPI
    ├── 依赖 → MicrophoneRecorder (现有)
    ├── 依赖 → MixedAudioRecorder (现有)
    ├── 依赖 → Logger (现有)
    └── 依赖 → FileManagerUtils (现有)
```

## 🎯 API 优势

1. **简洁易用**：只有一个主要类 `AudioRecordAPI`
2. **复用现有代码**：直接使用现有的录制器
3. **类型安全**：使用 Swift 强类型系统
4. **异步支持**：使用 async/await
5. **错误处理**：明确的错误类型
6. **扩展友好**：为未来功能预留接口

这个纯音频录制 API 让你可以用最少的新代码，将现有的录制功能包装成简洁易用的接口！🚀

