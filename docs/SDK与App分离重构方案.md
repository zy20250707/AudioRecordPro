# SDK 与 App 分离重构方案

## 一、重构目标

将现有工程拆分为两个独立部分：

| 部分 | 名称 | 用途 |
|------|------|------|
| **SDK** | `AudioRecordKit` | 核心音频录制能力，可独立打包供外部调用 |
| **App** | `AudioRecordApp` | 桌面应用，依赖 SDK 提供 UI 交互 |

---

## 二、当前目录结构

```
audio_record_mac/
├── src/
│   ├── main.swift
│   ├── AudioRecordSDK/          # SDK API（部分）
│   ├── Controllers/             # UI 控制器
│   ├── Views/                   # UI 视图
│   ├── Recorder/                # 核心录制器
│   ├── ProcessTapRecorder/      # CoreAudio 实现
│   ├── Models/                  # 数据模型
│   └── Utils/                   # 工具类
├── assets/
├── docs/
├── scripts/
├── build.sh
├── Info.plist
└── AudioRecordMac.entitlements
```

---

## 三、目标目录结构

```
audio_record_mac/
│
├── AudioRecordKit/                    # 📦 SDK（可独立打包）
│   ├── Sources/
│   │   ├── Core/                      # 核心实现（internal）
│   │   │   ├── Protocols/
│   │   │   ├── Recorders/
│   │   │   ├── ProcessTap/
│   │   │   └── Models/
│   │   ├── API/                       # Swift API（public）
│   │   ├── CAPI/                      # C API 导出（public）
│   │   └── Utils/                     # 内部工具（internal）
│   ├── Package.swift
│   └── README.md
│
├── AudioRecordApp/                    # 🖥️ 桌面应用
│   ├── Sources/
│   │   ├── App/
│   │   ├── Controllers/
│   │   └── Views/
│   ├── Resources/
│   └── build.sh
│
├── Examples/                          # 示例代码
├── scripts/                           # 构建脚本
├── docs/                              # 文档
└── build/                             # 构建产物
```

---

## 四、文件归属划分

### 4.1 SDK 部分（AudioRecordKit）

| 当前路径 | 目标路径 | 说明 |
|----------|----------|------|
| `src/Recorder/AudioRecorderProtocol.swift` | `Core/Protocols/` | 录制器协议 |
| `src/Recorder/MicrophoneRecorder.swift` | `Core/Recorders/` | 麦克风录制 |
| `src/Recorder/MixedAudioRecorder.swift` | `Core/Recorders/` | 混音录制 |
| `src/Recorder/ScreenCaptureAudioRecorder.swift` | `Core/Recorders/` | 屏幕捕获录制 |
| `src/ProcessTapRecorder/*.swift` | `Core/ProcessTap/` | CoreAudio 实现 |
| `src/Models/AudioRecording.swift` | `Core/Models/` | 录音数据模型 |
| `src/AudioRecordSDK/AudioRecordAPI.swift` | `API/` | Swift API |
| `src/AudioRecordSDK/AudioConstraints.swift` | `API/` | 约束定义 |
| `src/AudioRecordSDK/MediaStream.swift` | `API/` | 媒体流 |
| `src/AudioRecordSDK/MediaStreamTrack.swift` | `API/` | 媒体轨道 |
| `src/AudioRecordSDK/AudioRecordError.swift` | `API/` | 错误定义 |
| `src/Utils/Logger.swift` | `Utils/` | 日志工具 |
| `src/Utils/PermissionManager.swift` | `Utils/` | 权限管理 |
| `src/Utils/FileManagerUtils.swift` | `Utils/` | 文件工具 |
| `src/Utils/AudioUtils.swift` | `Utils/` | 音频工具 |
| `src/Utils/LevelMonitor.swift` | `Utils/` | 电平监控 |

### 4.2 App 部分（AudioRecordApp）

| 当前路径 | 目标路径 | 说明 |
|----------|----------|------|
| `src/main.swift` | `App/` | 应用入口 |
| `src/Controllers/AppDelegate.swift` | `App/` | 应用代理 |
| `src/Controllers/MainViewController.swift` | `Controllers/` | 主控制器 |
| `src/Controllers/AudioRecorderController.swift` | `Controllers/` | 录制控制器 |
| `src/Views/*.swift` | `Views/` | 所有视图文件 |
| `assets/*` | `Resources/Assets/` | 资源文件 |
| `Info.plist` | `Resources/` | 应用配置 |
| `AudioRecordMac.entitlements` | `Resources/` | 权限声明 |

---

## 五、需要解决的问题清单

### 问题 1: 访问控制调整
- **现状**: 大部分类/方法没有显式访问控制
- **目标**: SDK 内部使用 `internal`，公开 API 使用 `public`
- **影响文件**: 所有 SDK 文件

### 问题 2: @MainActor 依赖
- **现状**: `AudioRecorderProtocol` 等核心协议标记为 `@MainActor`
- **目标**: 核心层不绑定主线程，通过回调在主线程通知
- **影响文件**: `AudioRecorderProtocol.swift`, `BaseAudioRecorder`, 各录制器

### 问题 3: 工厂模式引入
- **现状**: `AudioRecorderController` 直接创建具体录制器类
- **目标**: 通过 `RecorderFactory` 创建，便于测试和扩展
- **影响文件**: `AudioRecorderController.swift`

### 问题 4: 共享类型处理
- **现状**: `AudioUtils.RecordingMode`, `AudioProcessInfo` 等被 UI 和 Core 共用
- **目标**: 定义在 SDK 公开 API 中，App 通过 SDK 引用
- **影响文件**: `AudioUtils.swift`, 各视图文件

### 问题 5: 构建系统更新
- **现状**: 单一 `build.sh` 构建整个应用
- **目标**: 分离 SDK 构建和 App 构建
- **新增文件**: `build_sdk.sh`, `build_app.sh`, `Package.swift`

### 问题 6: C API 层实现
- **现状**: 无 C API
- **目标**: 提供完整 C API 供 Chromium/Electron 调用
- **新增文件**: `AudioRecordSDK.h`, `AudioRecordSDK_C.swift`

### 问题 7: 测试迁移
- **现状**: 测试代码在 `src/AudioRecordSDK/Tests/`
- **目标**: SDK 测试在 `AudioRecordKit/Tests/`，App 测试在 `AudioRecordApp/Tests/`

---

## 六、实施计划

### 阶段 1: 准备工作（不改变现有功能）
1. [ ] 创建新目录结构
2. [ ] 梳理文件依赖关系
3. [ ] 确定公开 API 边界

### 阶段 2: SDK 抽离
4. [ ] 移动核心实现到 `AudioRecordKit/Sources/Core/`
5. [ ] 移动 API 层到 `AudioRecordKit/Sources/API/`
6. [ ] 移动工具类到 `AudioRecordKit/Sources/Utils/`
7. [ ] 调整访问控制（public/internal）
8. [ ] 移除 `@MainActor` 依赖

### 阶段 3: App 重组
9. [ ] 移动 App 代码到 `AudioRecordApp/`
10. [ ] 更新 import 路径
11. [ ] App 依赖 SDK 模块

### 阶段 4: 构建系统
12. [ ] 创建 `Package.swift`
13. [ ] 更新构建脚本
14. [ ] 验证 SDK 独立编译
15. [ ] 验证 App 编译

### 阶段 5: C API 层
16. [ ] 创建 C 头文件
17. [ ] 实现 `@_cdecl` 导出
18. [ ] 测试 C API 调用

### 阶段 6: 验证与文档
19. [ ] 端到端测试
20. [ ] 更新文档
21. [ ] 示例代码

---

## 七、风险评估

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| 循环依赖 | 编译失败 | 提前梳理依赖图，分层设计 |
| 访问控制遗漏 | SDK 内部实现暴露 | 逐文件审查，CI 检查 |
| 构建脚本复杂度 | 维护困难 | 使用 Swift Package Manager |
| 向后兼容 | 现有功能回归 | 保持原有测试，增量修改 |

---

## 八、下一步行动

请确认以下问题后开始实施：

1. **问题 1**: 是否同意目标目录结构？
2. **问题 2**: SDK 最低支持的 macOS 版本？（当前 13.0，Process Tap 需要 14.4）
3. **问题 3**: 是否需要支持 Intel (x86_64) 架构？
4. **问题 4**: SDK 打包格式优先级？（Framework / XCFramework / Swift Package）
5. **问题 5**: 先从哪个阶段开始？

---

## 九、参考文档

- [SDK架构设计.md](./SDK架构设计.md)
- [项目能力分析.md](./项目能力分析.md)
- [MVP音频API设计.md](./MVP音频API设计.md)


