# 音频录制 API - MVP 版本设计

## 🎯 MVP 需求分析

### 核心功能
1. **麦克风录制** - 纯麦克风音频
2. **混音录制** - 麦克风 + 系统音频混合

### 扩展预留
- 进程音频录制
- 纯系统音频录制

## 🏗️ MVP API 设计

### 1. 简化的约束参数

```javascript
// MVP 版本的约束参数
const AudioConstraints = {
  // 基础参数
  deviceId: 'default',           // 麦克风设备ID
  sampleRate: 48000,             // 固定48kHz
  channelCount: 2,               // 固定立体声
  
  // 音频处理（简化）
  echoCancellation: true,        // 回声消除
  noiseSuppression: true,        // 噪音抑制
  
  // MVP 扩展参数
  includeSystemAudio: false,     // 是否包含系统音频（核心扩展）
  microphoneVolume: 1.0,         // 麦克风音量 (0.0-1.0)
  systemAudioVolume: 1.0         // 系统音频音量 (0.0-1.0)
};
```

### 2. 简化的 MediaStream

```javascript
// MVP 版本的 MediaStream
class AudioMediaStream {
  constructor() {
    this.id = generateUUID();
    this.tracks = [];
    this.recordingMode = 'inactive';
  }
  
  // 基础属性
  get active() {
    return this.tracks.some(track => track.readyState === 'live');
  }
  
  // 简化的轨道管理
  getAudioTracks() {
    return this.tracks.filter(track => track.kind === 'audio');
  }
  
  addTrack(track) {
    this.tracks.push(track);
    this._updateRecordingMode();
  }
  
  removeTrack(track) {
    this.tracks = this.tracks.filter(t => t.id !== track.id);
    this._updateRecordingMode();
  }
  
  // MVP 核心：录制模式判断
  _updateRecordingMode() {
    const micTracks = this.tracks.filter(t => t.trackType === 'microphone');
    const systemTracks = this.tracks.filter(t => t.trackType === 'systemAudio');
    
    if (micTracks.length > 0 && systemTracks.length > 0) {
      this.recordingMode = 'mixed';
    } else if (micTracks.length > 0) {
      this.recordingMode = 'microphone';
    } else if (systemTracks.length > 0) {
      this.recordingMode = 'systemAudio';  // 预留
    } else {
      this.recordingMode = 'inactive';
    }
  }
}
```

### 3. 简化的轨道设计

```javascript
// MVP 版本的音频轨道
class AudioMediaStreamTrack {
  constructor(type, source) {
    this.id = generateUUID();
    this.kind = 'audio';
    this.trackType = type;        // 'microphone' | 'systemAudio'
    this.source = source;
    this.enabled = true;
    this.readyState = 'live';
    this.volume = 1.0;
  }
  
  // 基础控制
  stop() {
    this.readyState = 'ended';
  }
  
  setVolume(volume) {
    this.volume = Math.max(0.0, Math.min(1.0, volume));
  }
}
```

## 🚀 MVP 使用接口

### 1. 纯麦克风录制

```javascript
// 模式1：纯麦克风录制（与标准 Web API 完全一致）
const stream = await navigator.mediaDevices.getUserMedia({
  audio: {
    echoCancellation: true,
    noiseSuppression: true,
    deviceId: 'default'
  }
});

console.log('录制模式:', stream.recordingMode); // 'microphone'
console.log('轨道数量:', stream.getAudioTracks().length); // 1

// 开始录制
const mediaRecorder = new MediaRecorder(stream);
mediaRecorder.start();
```

### 2. 混音录制

```javascript
// 模式2：麦克风 + 系统音频混音（MVP 扩展）
const stream = await navigator.mediaDevices.getUserMedia({
  audio: {
    echoCancellation: true,
    noiseSuppression: true,
    includeSystemAudio: true,        // MVP 核心扩展参数
    microphoneVolume: 0.8,           // 麦克风音量
    systemAudioVolume: 1.0           // 系统音频音量
  }
});

console.log('录制模式:', stream.recordingMode); // 'mixed'
console.log('轨道数量:', stream.getAudioTracks().length); // 2

// 可以独立控制各轨道
const tracks = stream.getAudioTracks();
const micTrack = tracks.find(t => t.trackType === 'microphone');
const sysTrack = tracks.find(t => t.trackType === 'systemAudio');

micTrack.setVolume(0.8);  // 调整麦克风音量
sysTrack.setVolume(1.0);  // 调整系统音频音量
```

## 🔧 MVP 实现架构

### 1. 桥接层实现

```swift
// MVP 版本的桥接层
class MVPAudioBridge {
    
    static func getUserMedia(constraints: AudioConstraints) async throws -> AudioMediaStream {
        let stream = AudioMediaStream()
        
        // 总是添加麦克风轨道
        let micTrack = try await createMicrophoneTrack(constraints)
        stream.addTrack(micTrack)
        
        // 如果需要系统音频，添加系统音频轨道
        if constraints.includeSystemAudio {
            let systemTrack = try await createSystemAudioTrack(constraints)
            stream.addTrack(systemTrack)
        }
        
        return stream
    }
    
    private static func createMicrophoneTrack(_ constraints: AudioConstraints) async throws -> AudioMediaStreamTrack {
        // 使用现有的 MicrophoneRecorder
        let track = AudioMediaStreamTrack(type: .microphone, source: constraints.deviceId)
        track.setVolume(constraints.microphoneVolume)
        return track
    }
    
    private static func createSystemAudioTrack(_ constraints: AudioConstraints) async throws -> AudioMediaStreamTrack {
        // 使用现有的 MixedAudioRecorder 或 CoreAudioProcessTapRecorder
        let track = AudioMediaStreamTrack(type: .systemAudio, source: .systemMixdown)
        track.setVolume(constraints.systemAudioVolume)
        return track
    }
}
```

### 2. 录制器集成

```swift
// MVP 版本的录制器选择
class MVPAudioRecorder {
    
    func startRecording(stream: AudioMediaStream) async throws {
        switch stream.recordingMode {
        case .microphone:
            // 使用现有的 MicrophoneRecorder
            try await startMicrophoneRecording(stream)
            
        case .mixed:
            // 使用现有的 MixedAudioRecorder
            try await startMixedRecording(stream)
            
        default:
            throw AudioRecorderError.unsupportedMode
        }
    }
    
    private func startMicrophoneRecording(_ stream: AudioMediaStream) async throws {
        let recorder = MicrophoneRecorder(mode: .microphone)
        try await recorder.startRecording()
    }
    
    private func startMixedRecording(_ stream: AudioMediaStream) async throws {
        let recorder = MixedAudioRecorder(mode: .mixed)
        
        // 配置麦克风
        let micTrack = stream.getAudioTracks().first { $0.trackType == .microphone }
        recorder.setMicrophoneVolume(micTrack?.volume ?? 1.0)
        
        // 配置系统音频
        let sysTrack = stream.getAudioTracks().first { $0.trackType == .systemAudio }
        recorder.setSystemAudioVolume(sysTrack?.volume ?? 1.0)
        
        try await recorder.startRecording()
    }
}
```

## 📋 MVP 功能对照表

| 功能 | MVP 版本 | 完整版本 | 说明 |
|------|---------|---------|------|
| 麦克风录制 | ✅ | ✅ | 核心功能 |
| 混音录制 | ✅ | ✅ | 核心功能 |
| 进程录制 | ❌ | ✅ | 后期扩展 |
| 纯系统音频 | ❌ | ✅ | 后期扩展 |
| 多设备支持 | ❌ | ✅ | 后期扩展 |
| 动态轨道管理 | 简化 | ✅ | MVP 只支持创建时确定 |
| 设备枚举 | ❌ | ✅ | 后期扩展 |
| 权限管理 | 简化 | ✅ | 基础权限检查 |

## 🎯 MVP 使用示例

### 完整的录制流程

```javascript
// MVP 录制示例
class MVPAudioRecorder {
  constructor() {
    this.mediaRecorder = null;
    this.recordedChunks = [];
  }
  
  // 纯麦克风录制
  async startMicrophoneRecording() {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        audio: {
          echoCancellation: true,
          noiseSuppression: true
        }
      });
      
      this.startRecording(stream, 'microphone');
    } catch (error) {
      console.error('麦克风录制失败:', error);
    }
  }
  
  // 混音录制
  async startMixedRecording(micVolume = 0.8, systemVolume = 1.0) {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        audio: {
          echoCancellation: true,
          noiseSuppression: true,
          includeSystemAudio: true,      // MVP 核心扩展
          microphoneVolume: micVolume,
          systemAudioVolume: systemVolume
        }
      });
      
      this.startRecording(stream, 'mixed');
    } catch (error) {
      console.error('混音录制失败:', error);
    }
  }
  
  // 通用录制逻辑
  startRecording(stream, mode) {
    this.mediaRecorder = new MediaRecorder(stream);
    this.recordedChunks = [];
    
    this.mediaRecorder.ondataavailable = event => {
      if (event.data.size > 0) {
        this.recordedChunks.push(event.data);
      }
    };
    
    this.mediaRecorder.onstop = () => {
      const blob = new Blob(this.recordedChunks, { 
        type: mode === 'mixed' ? 'audio/wav' : 'audio/webm' 
      });
      this.onRecordingComplete(blob, mode);
    };
    
    this.mediaRecorder.start();
    console.log(`开始${mode}录制`);
  }
  
  stopRecording() {
    if (this.mediaRecorder && this.mediaRecorder.state === 'recording') {
      this.mediaRecorder.stop();
    }
  }
  
  onRecordingComplete(blob, mode) {
    const url = URL.createObjectURL(blob);
    console.log(`${mode}录制完成:`, url);
    
    // 播放或保存录制结果
    const audio = new Audio(url);
    audio.play();
  }
}

// 使用示例
const recorder = new MVPAudioRecorder();

// 纯麦克风录制
await recorder.startMicrophoneRecording();

// 混音录制（麦克风80%音量 + 系统音频100%音量）
await recorder.startMixedRecording(0.8, 1.0);
```

## 🔮 扩展路径

### 阶段1：MVP（当前）
- ✅ 麦克风录制
- ✅ 混音录制（麦克风 + 系统音频）

### 阶段2：进程扩展
```javascript
// 未来扩展：进程录制
const stream = await navigator.mediaDevices.getUserMedia({
  audio: {
    includeSystemAudio: true,
    targetProcess: 'QQMusic',        // 新增：指定进程
    microphoneVolume: 0.8,
    systemAudioVolume: 1.0
  }
});
```

### 阶段3：完整功能
```javascript
// 未来扩展：完整功能
const stream = await navigator.mediaDevices.getUserMedia({
  audio: {
    includeSystemAudio: true,
    targetProcesses: ['QQMusic', 'Safari'],  // 多进程支持
    deviceId: 'specific-microphone',         // 设备选择
    microphoneVolume: 0.8,
    systemAudioVolume: 1.0
  }
});
```

## 🎉 MVP 优势

1. **简单易用**：只有两种模式，学习成本低
2. **Web 兼容**：与标准 Web API 高度兼容
3. **渐进增强**：为未来扩展预留接口
4. **快速实现**：复用现有录制器代码
5. **用户友好**：满足核心录制需求

这个 MVP 设计既满足了你的核心需求，又为未来扩展留下了清晰的路径！🚀

