# MVP 极简版本 vs 标准 Web API 对比

## 🎯 MVP 极简设计目标

**只实现核心功能**：
1. 麦克风录制
2. 麦克风 + 系统音频混音录制

**不追求完全兼容**，而是用最少的代码实现核心需求。

## 📋 功能对比表

| 功能类别 | 标准 Web API | MVP 极简版本 | 差异说明 |
|---------|-------------|-------------|---------|
| **基础录制** | | | |
| 麦克风录制 | ✅ `getUserMedia({ audio: true })` | ✅ `getUserMedia({ audio: true })` | 完全一致 |
| 系统音频录制 | ❌ 不支持 | ✅ `getUserMedia({ audio: { includeSystemAudio: true } })` | MVP 扩展 |
| 混音录制 | ❌ 不支持 | ✅ 自动混音到单轨道 | MVP 核心功能 |
| **约束参数** | | | |
| `deviceId` | ✅ 支持设备选择 | ❌ 引擎自适应 | MVP 简化 |
| `sampleRate` | ✅ 支持多种采样率 | ❌ 引擎自适应 | MVP 简化 |
| `channelCount` | ✅ 支持 1-8 声道 | ❌ 固定立体声 | MVP 简化 |
| `echoCancellation` | ✅ 支持 | ✅ 支持 | 保留 |
| `noiseSuppression` | ✅ 支持 | ✅ 支持 | 保留 |
| `autoGainControl` | ✅ 支持 | ❌ 不支持 | MVP 简化 |
| `latency` | ✅ 支持 | ❌ 不支持 | MVP 简化 |
| `volume` | ✅ 支持 | ❌ 不支持 | MVP 简化 |
| **约束范围** | | | |
| `{ min, ideal, max }` | ✅ 支持范围约束 | ❌ 只支持固定值 | MVP 简化 |
| **MediaStream 对象** | | | |
| `stream.id` | ✅ 唯一标识符 | ✅ 唯一标识符 | 保留 |
| `stream.active` | ✅ 活跃状态 | ✅ 活跃状态 | 保留 |
| `stream.getAudioTracks()` | ✅ 获取音频轨道 | ✅ 获取音频轨道 | 保留 |
| `stream.getVideoTracks()` | ✅ 获取视频轨道 | ❌ 不支持视频 | MVP 简化 |
| `stream.getTracks()` | ✅ 获取所有轨道 | ✅ 获取所有轨道 | 保留 |
| `stream.addTrack()` | ✅ 动态添加轨道 | ❌ 不支持动态添加 | MVP 简化 |
| `stream.removeTrack()` | ✅ 动态移除轨道 | ❌ 不支持动态移除 | MVP 简化 |
| `stream.clone()` | ✅ 克隆流 | ❌ 不支持克隆 | MVP 简化 |
| **MediaStreamTrack 对象** | | | |
| `track.kind` | ✅ 轨道类型 | ✅ 轨道类型 | 保留 |
| `track.id` | ✅ 轨道ID | ✅ 轨道ID | 保留 |
| `track.label` | ✅ 设备标签 | ❌ 固定标签 | MVP 简化 |
| `track.enabled` | ✅ 启用/禁用 | ✅ 启用/禁用 | 保留 |
| `track.muted` | ✅ 静音状态 | ❌ 不支持 | MVP 简化 |
| `track.readyState` | ✅ 就绪状态 | ✅ 就绪状态 | 保留 |
| `track.stop()` | ✅ 停止轨道 | ✅ 停止轨道 | 保留 |
| `track.applyConstraints()` | ✅ 应用约束 | ❌ 不支持 | MVP 简化 |
| `track.getSettings()` | ✅ 获取设置 | ❌ 不支持 | MVP 简化 |
| `track.getConstraints()` | ✅ 获取约束 | ❌ 不支持 | MVP 简化 |
| **事件监听** | | | |
| `stream.onaddtrack` | ✅ 轨道添加事件 | ❌ 不支持 | MVP 简化 |
| `stream.onremovetrack` | ✅ 轨道移除事件 | ❌ 不支持 | MVP 简化 |
| `track.onended` | ✅ 轨道结束事件 | ✅ 轨道结束事件 | 保留 |
| `track.onmute` | ✅ 静音事件 | ❌ 不支持 | MVP 简化 |
| `track.onunmute` | ✅ 取消静音事件 | ❌ 不支持 | MVP 简化 |
| **设备管理** | | | |
| `enumerateDevices()` | ✅ 枚举设备 | ❌ 不支持 | MVP 简化 |
| `devicechange` 事件 | ✅ 设备变化监听 | ❌ 不支持 | MVP 简化 |
| **权限管理** | | | |
| `navigator.permissions.query()` | ✅ 权限查询 | ❌ 不支持 | MVP 简化 |
| 权限变化监听 | ✅ 支持 | ❌ 不支持 | MVP 简化 |
| **错误处理** | | | |
| `NotAllowedError` | ✅ 权限拒绝 | ✅ 权限拒绝 | 保留 |
| `NotFoundError` | ✅ 设备未找到 | ✅ 设备未找到 | 保留 |
| `NotSupportedError` | ✅ 不支持 | ✅ 不支持 | 保留 |
| `NotReadableError` | ✅ 设备占用 | ❌ 不支持 | MVP 简化 |
| `OverconstrainedError` | ✅ 约束冲突 | ❌ 不支持 | MVP 简化 |
| `SecurityError` | ✅ 安全错误 | ❌ 不支持 | MVP 简化 |

## 🚀 MVP 极简 API 设计

### 1. 简化的约束参数

```javascript
// MVP 只支持这些参数
const constraints = {
  audio: {
    // 基础参数（固定值）
    sampleRate: 48000,              // 固定 48kHz
    channelCount: 2,                // 固定立体声
    
    // 音频处理（简化）
    echoCancellation: true,         // 支持
    noiseSuppression: true,         // 支持
    
    // MVP 扩展
    includeSystemAudio: false       // 是否包含系统音频
  }
};
```

### 2. 简化的 MediaStream

```javascript
// MVP MediaStream（简化版）
class MVPMediaStream {
  constructor() {
    this.id = generateUUID();
    this.tracks = [];
  }
  
  // 保留的标准方法
  get active() { return this.tracks.some(t => t.readyState === 'live'); }
  getAudioTracks() { return this.tracks.filter(t => t.kind === 'audio'); }
  getTracks() { return this.tracks; }
  
  // 不支持的方法（抛出错误或返回空）
  getVideoTracks() { return []; }
  addTrack() { throw new Error('MVP: addTrack not supported'); }
  removeTrack() { throw new Error('MVP: removeTrack not supported'); }
  clone() { throw new Error('MVP: clone not supported'); }
}
```

### 3. 简化的 MediaStreamTrack

```javascript
// MVP MediaStreamTrack（简化版）
class MVPMediaStreamTrack {
  constructor() {
    this.kind = 'audio';
    this.id = generateUUID();
    this.label = 'MVP Audio Track';  // 固定标签
    this.enabled = true;
    this.readyState = 'live';
  }
  
  // 保留的方法
  stop() { this.readyState = 'ended'; }
  
  // 不支持的属性/方法
  get muted() { throw new Error('MVP: muted not supported'); }
  applyConstraints() { throw new Error('MVP: applyConstraints not supported'); }
  getSettings() { throw new Error('MVP: getSettings not supported'); }
  getConstraints() { throw new Error('MVP: getConstraints not supported'); }
}
```

## 📝 MVP 使用示例

### 标准麦克风录制

```javascript
// MVP 支持的标准调用
const stream = await navigator.mediaDevices.getUserMedia({
  audio: {
    echoCancellation: true,
    noiseSuppression: true
  }
});

// 这些标准操作都支持
console.log('流ID:', stream.id);
console.log('是否活跃:', stream.active);
console.log('音频轨道:', stream.getAudioTracks());

const mediaRecorder = new MediaRecorder(stream);
mediaRecorder.start();
```

### MVP 混音录制

```javascript
// MVP 扩展功能
const stream = await navigator.mediaDevices.getUserMedia({
  audio: {
    echoCancellation: true,
    noiseSuppression: true,
    includeSystemAudio: true    // MVP 扩展参数
  }
});

// 返回的是混音后的单轨道
console.log('轨道数:', stream.getAudioTracks().length); // 1
```

### 不支持的操作

```javascript
// 这些操作在 MVP 中会报错
try {
  stream.addTrack(someTrack);           // ❌ 报错
  stream.clone();                       // ❌ 报错
  track.applyConstraints({});           // ❌ 报错
  track.getSettings();                  // ❌ 报错
  navigator.mediaDevices.enumerateDevices(); // ❌ 报错
} catch (error) {
  console.log('MVP 不支持此功能:', error.message);
}
```

## 🎯 MVP 实现优先级

### 第一优先级（必须实现）
- ✅ `getUserMedia({ audio: true })`
- ✅ `getUserMedia({ audio: { includeSystemAudio: true } })`
- ✅ 基础 MediaStream 对象
- ✅ 基础 MediaStreamTrack 对象
- ✅ 基础错误处理

### 第二优先级（可选实现）
- ⚠️ 更多音频处理选项
- ⚠️ 更好的错误信息
- ⚠️ 基础设备枚举

### 不实现（明确排除）
- ❌ 动态轨道管理
- ❌ 约束范围参数
- ❌ 设备选择
- ❌ 权限查询 API
- ❌ 复杂事件监听
- ❌ 视频支持

## 📊 代码量对比估算

| 组件 | 标准 Web API | MVP 极简版本 | 减少比例 |
|------|-------------|-------------|---------|
| 约束处理 | ~500 行 | ~50 行 | 90% ↓ |
| MediaStream | ~300 行 | ~100 行 | 67% ↓ |
| MediaStreamTrack | ~400 行 | ~80 行 | 80% ↓ |
| 设备管理 | ~200 行 | ~0 行 | 100% ↓ |
| 权限管理 | ~150 行 | ~20 行 | 87% ↓ |
| 事件系统 | ~250 行 | ~30 行 | 88% ↓ |
| **总计** | **~1800 行** | **~280 行** | **85% ↓** |

## 🎉 MVP 优势

1. **开发速度快**：只需实现 15% 的代码量
2. **维护成本低**：功能简单，bug 少
3. **满足核心需求**：麦克风 + 混音录制
4. **清晰的边界**：明确什么支持，什么不支持
5. **快速验证**：可以快速验证技术方案和用户需求

这个 MVP 版本让你用最少的工作量实现核心功能，同时清楚地知道与标准 API 的差异！🚀

