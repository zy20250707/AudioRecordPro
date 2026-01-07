# MVP 版本 - 完全兼容标准 MediaDevices API

## 🎯 设计原则

### 100% 兼容标准 Web API
- 标准麦克风录制：与原生 `navigator.mediaDevices.getUserMedia()` 完全一致
- 扩展功能：通过额外参数实现系统音频混音
- 渐进增强：现有 Web 代码无需修改即可使用

## 📋 MVP 功能对照

| 阶段 | 功能 | API 扩展 | 兼容性 |
|------|------|---------|--------|
| MVP | 麦克风录制 | 无扩展 | 100% 标准兼容 |
| MVP | 混音录制 | `includeSystemAudio: true` | 向后兼容 |

## 🚀 MVP API 设计

### 1. 标准麦克风录制（100% 兼容）

```javascript
// 完全标准的 Web API 调用 - 无任何修改
const stream = await navigator.mediaDevices.getUserMedia({
  audio: true
});

// 或者带参数的标准调用
const stream = await navigator.mediaDevices.getUserMedia({
  audio: {
    echoCancellation: true,
    noiseSuppression: true,
    autoGainControl: true,
    sampleRate: 48000,
    channelCount: 2,
    deviceId: 'default'
  }
});

// 返回标准的 MediaStream 对象
console.log('流ID:', stream.id);
console.log('是否活跃:', stream.active);
console.log('音频轨道数:', stream.getAudioTracks().length); // 1

// 标准的 MediaRecorder 使用
const mediaRecorder = new MediaRecorder(stream);
mediaRecorder.start();
```

### 2. 混音录制（MVP 扩展）

```javascript
// MVP 扩展：添加 includeSystemAudio 参数
const stream = await navigator.mediaDevices.getUserMedia({
  audio: {
    // 标准参数（完全兼容）
    echoCancellation: true,
    noiseSuppression: true,
    autoGainControl: true,
    sampleRate: 48000,
    channelCount: 2,
    deviceId: 'default',
    
    // MVP 扩展参数
    includeSystemAudio: true,        // 启用系统音频混音
    microphoneVolume: 0.8,           // 麦克风音量（可选）
    systemAudioVolume: 1.0           // 系统音频音量（可选）
  }
});

// 返回的仍然是标准 MediaStream，但内部包含混音逻辑
console.log('流ID:', stream.id);
console.log('是否活跃:', stream.active);
console.log('音频轨道数:', stream.getAudioTracks().length); // 1（混音后的单轨道）

// 使用标准 MediaRecorder（无需修改）
const mediaRecorder = new MediaRecorder(stream);
mediaRecorder.start();
```

## 🏗️ MVP 实现架构

### 1. 兼容层设计

```swift
// MVP 桥接层 - 完全兼容标准 API
class MVPMediaDevices {
    
    static func getUserMedia(constraints: MediaStreamConstraints) async throws -> MediaStream {
        // 检查是否有系统音频扩展参数
        if let audioConstraints = constraints.audio,
           audioConstraints.includeSystemAudio == true {
            // 混音模式：返回混音后的单轨道流
            return try await createMixedAudioStream(constraints: audioConstraints)
        } else {
            // 标准模式：返回纯麦克风流
            return try await createStandardMicrophoneStream(constraints: constraints)
        }
    }
    
    // 标准麦克风流（100% 兼容）
    private static func createStandardMicrophoneStream(constraints: MediaStreamConstraints) async throws -> MediaStream {
        let stream = MediaStream()
        
        // 使用现有的 MicrophoneRecorder
        let micTrack = try await createMicrophoneTrack(constraints.audio)
        stream.addTrack(micTrack)
        
        return stream
    }
    
    // 混音流（MVP 扩展）
    private static func createMixedAudioStream(constraints: AudioConstraints) async throws -> MediaStream {
        let stream = MediaStream()
        
        // 创建混音轨道（内部包含麦克风+系统音频）
        let mixedTrack = try await createMixedAudioTrack(constraints)
        stream.addTrack(mixedTrack)
        
        return stream
    }
}
```

### 2. 轨道实现

```swift
// MVP 版本的轨道设计
class MVPMediaStreamTrack: MediaStreamTrack {
    private let recordingMode: RecordingMode
    private var recorder: AudioRecorderProtocol?
    
    enum RecordingMode {
        case microphone          // 标准麦克风
        case mixedAudio         // 混音（麦克风+系统音频）
    }
    
    init(mode: RecordingMode, constraints: AudioConstraints) {
        self.recordingMode = mode
        super.init(kind: "audio")
        
        // 根据模式选择录制器
        switch mode {
        case .microphone:
            self.recorder = MicrophoneRecorder(mode: .microphone)
        case .mixedAudio:
            self.recorder = MixedAudioRecorder(mode: .mixed)
            configureMixedRecorder(constraints)
        }
    }
    
    private func configureMixedRecorder(_ constraints: AudioConstraints) {
        guard let mixedRecorder = recorder as? MixedAudioRecorder else { return }
        
        // 配置混音参数
        mixedRecorder.setMicrophoneVolume(constraints.microphoneVolume ?? 1.0)
        mixedRecorder.setSystemAudioVolume(constraints.systemAudioVolume ?? 1.0)
    }
}
```

### 3. 约束参数扩展

```swift
// 扩展标准约束，保持向后兼容
struct AudioConstraints {
    // 标准 Web API 参数（完全兼容）
    var deviceId: String?
    var sampleRate: Int?
    var channelCount: Int?
    var echoCancellation: Bool?
    var noiseSuppression: Bool?
    var autoGainControl: Bool?
    
    // MVP 扩展参数
    var includeSystemAudio: Bool?      // 是否包含系统音频
    var microphoneVolume: Float?       // 麦克风音量 (0.0-1.0)
    var systemAudioVolume: Float?      // 系统音频音量 (0.0-1.0)
}

// 媒体流约束
struct MediaStreamConstraints {
    var audio: AudioConstraints?
    var video: VideoConstraints? = nil  // MVP 不支持视频
}
```

## 📝 使用示例对比

### 标准 Web 代码（无需修改）

```javascript
// 现有的标准 Web 代码可以直接使用
class StandardAudioRecorder {
  async startRecording() {
    try {
      // 标准 API 调用
      const stream = await navigator.mediaDevices.getUserMedia({
        audio: {
          echoCancellation: true,
          noiseSuppression: true,
          sampleRate: 48000
        }
      });
      
      // 标准 MediaRecorder 使用
      this.mediaRecorder = new MediaRecorder(stream);
      this.mediaRecorder.start();
      
      console.log('标准麦克风录制开始');
    } catch (error) {
      console.error('录制失败:', error);
    }
  }
}

// 使用方式完全不变
const recorder = new StandardAudioRecorder();
await recorder.startRecording();
```

### MVP 扩展功能

```javascript
// MVP 扩展：只需添加一个参数
class MVPAudioRecorder {
  async startMicrophoneRecording() {
    // 标准麦克风录制（与上面完全一致）
    const stream = await navigator.mediaDevices.getUserMedia({
      audio: {
        echoCancellation: true,
        noiseSuppression: true
      }
    });
    
    this.startRecording(stream, 'microphone');
  }
  
  async startMixedRecording() {
    // MVP 混音录制（只添加一个参数）
    const stream = await navigator.mediaDevices.getUserMedia({
      audio: {
        echoCancellation: true,
        noiseSuppression: true,
        includeSystemAudio: true,      // 唯一的扩展参数
        microphoneVolume: 0.8,         // 可选
        systemAudioVolume: 1.0         // 可选
      }
    });
    
    this.startRecording(stream, 'mixed');
  }
  
  startRecording(stream, mode) {
    // 使用标准 MediaRecorder（无需修改）
    this.mediaRecorder = new MediaRecorder(stream);
    this.recordedChunks = [];
    
    this.mediaRecorder.ondataavailable = event => {
      if (event.data.size > 0) {
        this.recordedChunks.push(event.data);
      }
    };
    
    this.mediaRecorder.onstop = () => {
      const blob = new Blob(this.recordedChunks, { 
        type: 'audio/wav' 
      });
      this.onRecordingComplete(blob, mode);
    };
    
    this.mediaRecorder.start();
    console.log(`${mode} 录制开始`);
  }
  
  onRecordingComplete(blob, mode) {
    const url = URL.createObjectURL(blob);
    console.log(`${mode} 录制完成:`, url);
    
    // 播放录制结果
    const audio = new Audio(url);
    audio.play();
  }
}
```

## 🔄 渐进式使用

### 阶段1：现有代码直接使用
```javascript
// 现有 Web 应用无需任何修改
const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
const mediaRecorder = new MediaRecorder(stream);
```

### 阶段2：启用混音功能
```javascript
// 只需添加一个参数即可获得混音能力
const stream = await navigator.mediaDevices.getUserMedia({ 
  audio: { 
    includeSystemAudio: true 
  } 
});
```

### 阶段3：精细控制
```javascript
// 进一步控制混音参数
const stream = await navigator.mediaDevices.getUserMedia({ 
  audio: { 
    includeSystemAudio: true,
    microphoneVolume: 0.8,
    systemAudioVolume: 1.0
  } 
});
```

## 📊 兼容性保证

### 标准 API 兼容性
| 标准参数 | MVP 支持 | 说明 |
|---------|---------|------|
| `audio: true` | ✅ | 完全兼容 |
| `deviceId` | ✅ | 完全兼容 |
| `sampleRate` | ✅ | 完全兼容 |
| `channelCount` | ✅ | 完全兼容 |
| `echoCancellation` | ✅ | 完全兼容 |
| `noiseSuppression` | ✅ | 完全兼容 |
| `autoGainControl` | ✅ | 完全兼容 |

### 返回对象兼容性
| 标准方法/属性 | MVP 支持 | 说明 |
|-------------|---------|------|
| `stream.id` | ✅ | 完全兼容 |
| `stream.active` | ✅ | 完全兼容 |
| `stream.getAudioTracks()` | ✅ | 完全兼容 |
| `stream.getTracks()` | ✅ | 完全兼容 |
| `track.kind` | ✅ | 完全兼容 |
| `track.enabled` | ✅ | 完全兼容 |
| `track.stop()` | ✅ | 完全兼容 |

## 🎯 MVP 实现优先级

### 第一优先级：标准兼容
1. 实现标准 `getUserMedia({ audio: true })`
2. 支持所有标准音频约束参数
3. 返回标准 MediaStream 对象
4. 确保现有 Web 代码零修改运行

### 第二优先级：混音扩展
1. 添加 `includeSystemAudio` 参数
2. 实现混音录制逻辑
3. 保持 API 调用方式不变
4. 添加音量控制参数

### 第三优先级：错误处理
1. 标准错误类型支持
2. 权限管理
3. 设备不可用处理

## 🚀 实现建议

1. **先实现标准模式**：确保 100% 兼容现有 Web API
2. **再添加混音模式**：通过参数扩展实现
3. **保持单一轨道**：MVP 阶段返回单个混音轨道，简化实现
4. **复用现有录制器**：直接使用 `MicrophoneRecorder` 和 `MixedAudioRecorder`

这样设计的 MVP 版本既保证了完全的标准兼容性，又提供了你需要的混音功能！🎵

