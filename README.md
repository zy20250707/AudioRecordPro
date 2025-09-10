# AudioRecordMac - macOS 音频录制工具

一个基于 Swift 和 AppKit 开发的 macOS 音频录制应用程序，支持麦克风和系统声音录制。

## 核心系统 API

### 1. 音频录制 API

#### AVAudioEngine
- **用途**: 音频录制引擎核心
- **主要组件**:
  - `AVAudioEngine.inputNode`: 音频输入节点
  - `AVAudioMixerNode`: 音频混音器节点
  - `AVAudioPlayerNode`: 音频播放节点

#### AVAudioFile
- **用途**: 音频文件写入
- **支持格式**: M4A, MP3, WAV
- **参数**:
  ```swift
  // M4A 格式参数
  AVFormatIDKey: kAudioFormatMPEG4AAC
  AVSampleRateKey: 48000
  AVNumberOfChannelsKey: 2
  AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
  
  // MP3 格式参数
  AVFormatIDKey: kAudioFormatMPEGLayer3
  AVSampleRateKey: 48000
  AVNumberOfChannelsKey: 2
  AVEncoderBitRateKey: 128000
  
  // WAV 格式参数
  AVFormatIDKey: kAudioFormatLinearPCM
  AVSampleRateKey: 48000
  AVNumberOfChannelsKey: 2
  AVLinearPCMBitDepthKey: 16
  AVLinearPCMIsFloatKey: false
  ```

#### ScreenCaptureKit (系统声音录制)
- **用途**: 录制系统音频输出
- **主要组件**:
  - `SCStream`: 屏幕/音频捕获流
  - `SCContentFilter`: 内容过滤器
  - `SCStreamConfiguration`: 流配置
  - `SCStreamOutput`: 流输出处理

### 2. 音频播放 API

#### AVAudioPlayer
- **用途**: 音频文件播放
- **参数**:
  ```swift
  player.volume = 1.0  // 音量 (0.0 - 1.0)
  player.prepareToPlay()  // 预加载音频
  player.play()  // 开始播放
  player.stop()  // 停止播放
  ```

#### AVAudioPlayerDelegate
- **回调方法**:
  - `audioPlayerDidFinishPlaying(_:successfully:)`: 播放完成回调

### 3. 音频电平监控

#### AVAudioPCMBuffer
- **用途**: 音频缓冲区处理
- **电平计算**:
  ```swift
  // RMS (Root Mean Square) 电平计算
  let rms = sqrt(sum(sample²) / frameCount)
  let level = min(1.0, rms * 20.0)  // 放大20倍显示
  ```

#### Timer
- **用途**: 电平更新定时器
- **更新频率**: 100ms (0.1秒)

### 4. 用户界面 API

#### AppKit 组件
- **NSWindow**: 主窗口
- **NSView**: 自定义视图
- **NSButton**: 操作按钮
- **NSTextField**: 文本显示
- **NSPopUpButton**: 格式选择

#### Core Animation
- **CALayer**: 视图层
- **CAGradientLayer**: 渐变效果
- **CABasicAnimation**: 动画效果

### 5. 文件管理 API

#### FileManager
- **用途**: 文件操作
- **主要方法**:
  - `fileExists(at:)`: 检查文件存在
  - `attributesOfItem(atPath:)`: 获取文件属性
  - `createDirectory(at:withIntermediateDirectories:)`: 创建目录

#### UserDefaults
- **用途**: 用户设置存储
- **存储内容**:
  - 上次录制模式
  - 应用配置

## 录制参数配置

### 音频格式设置
```swift
// 默认格式: MP3
private var currentFormat: AudioUtils.AudioFormat = .mp3

// 采样率: 48kHz
AVSampleRateKey: 48000

// 声道数: 立体声 (2声道)
AVNumberOfChannelsKey: 2

// 缓冲区大小: 4096 帧
bufferSize: 4096
```

### 录制模式
- **麦克风录制**: 使用 `AVAudioEngine.inputNode`
- **系统声音录制**: 使用 `ScreenCaptureKit.SCStream`

## 播放参数配置

### 播放器设置
```swift
// 音量: 最大
player.volume = 1.0

// 播放模式: 单次播放
player.numberOfLoops = 0

// 播放速率: 正常
player.rate = 1.0
```

### 电平监控
```swift
// 更新间隔: 100ms
private let updateInterval: TimeInterval = 0.1

// 电平条数量: 50条
private var bars: [Float] = Array(repeating: 0.0, count: 50)
```

## 权限要求

### 麦克风权限
- **用途**: 录制麦克风输入
- **系统提示**: 首次使用时系统会请求权限

### 屏幕录制权限
- **用途**: 录制系统声音
- **系统提示**: 需要在系统偏好设置中手动授权

## 文件输出

### 默认保存位置
```
~/Documents/AudioRecordings/
```

### 文件命名格式
```
录音_YYYY-MM-DD_HH-mm-ss.mp3
```

## 技术架构

### 主要类结构
- `AppDelegate`: 应用程序生命周期管理
- `MainViewController`: 主视图控制器
- `AudioRecorderController`: 音频录制控制器
- `MainWindowView`: 主窗口视图
- `LevelMeterView`: 电平表视图
- `LevelMonitor`: 电平监控器
- `AudioUtils`: 音频工具类
- `FileManagerUtils`: 文件管理工具
- `Logger`: 日志记录器

### 设计模式
- **委托模式**: 视图与控制器通信
- **观察者模式**: 状态变化通知
- **单例模式**: 工具类实例管理
