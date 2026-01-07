# AudioRecord SDK 测试日志管理

## 📝 日志功能概述

修改后的测试脚本现在会自动将所有测试输出保存到日志文件中，方便后续查看和分析。

## 📁 日志文件位置

- **日志目录**: `test_logs/`
- **文件命名**: `sdk_test_YYYYMMDD_HHMMSS.log`
- **示例**: `sdk_test_20251028_181619.log`

## 🚀 使用方法

### 1. 运行测试并生成日志

```bash
# 运行基础测试
./scripts/test_sdk.sh

# 运行包含实际录制的测试
echo "y" | ./scripts/test_sdk.sh
```

测试运行时会：
- ✅ 在控制台显示实时输出
- ✅ 同时保存到日志文件
- ✅ 显示日志文件位置和大小

### 2. 查看测试日志

#### 方法一：使用日志管理脚本（推荐）

```bash
./scripts/view_test_logs.sh
```

提供以下功能：
- 📄 查看最新的测试日志
- 📋 列出所有测试日志
- 🔍 查看指定的测试日志
- 🗑️ 删除旧的测试日志
- 📊 查看日志统计信息

#### 方法二：直接查看日志文件

```bash
# 查看最新日志
cat test_logs/$(ls -t test_logs/sdk_test_*.log | head -1)

# 查看所有日志文件
ls -la test_logs/

# 查看指定日志
cat test_logs/sdk_test_20251028_181619.log
```

## 📊 日志内容结构

每个日志文件包含：

```
AudioRecord SDK 测试日志
测试时间: Mon Oct 28 18:16:19 CST 2025
测试环境: Darwin MacBook-Pro.local 24.3.0 Darwin Kernel Version 24.3.0
Swift 版本: swift-driver version: 1.115 Apple Swift version 6.0.2
================================

🚀 AudioRecord SDK 测试程序启动
✅ 日志目录创建成功: /Users/voidzhang/Documents/AudioRecordings/Logs
🧪 开始 AudioRecord SDK 测试...
==================================================

📋 测试 SDK 信息...
=== AudioRecordSDK v1.0.0 ===
... (详细测试输出) ...

================================
测试结束时间: Mon Oct 28 18:16:22 CST 2025
日志文件位置: /path/to/test_logs/sdk_test_20251028_181619.log
```

## 🛠️ 日志管理功能

### 查看日志统计

```bash
./scripts/view_test_logs.sh
# 选择选项 5) 查看日志统计信息
```

显示信息：
- 📁 日志目录位置
- 📊 总文件数和总大小
- 🆕 最新和最旧的日志文件
- 📋 最近5个测试日志列表

### 清理旧日志

```bash
./scripts/view_test_logs.sh
# 选择选项 4) 删除旧的测试日志
```

功能：
- 🔢 可指定保留的日志数量（默认5个）
- 🗑️ 自动删除较旧的日志文件
- ✅ 显示删除统计信息

## 📋 日志文件示例

### 成功测试的日志片段

```
🧪 开始 AudioRecord SDK 测试...
==================================================

📋 测试 SDK 信息...
✅ SDK 信息测试通过

🔧 测试约束创建...
✅ 约束创建测试通过

⚠️ 测试错误处理...
✅ 错误处理测试通过

🔐 测试权限检查...
  当前麦克风权限状态: 3
  ✅ 麦克风权限已授权
✅ 权限检查测试通过

📊 测试总结:
==================================================
总测试数: 7
通过: 7 ✅
失败: 0 ❌
跳过: 0 ⚠️

🎉 所有测试通过！SDK 工作正常。
```

### 实际录制测试的日志片段

```
🎬 开始实际录制测试 (时长: 3.0 秒)...
  🎤 测试麦克风录制...
[2025-10-28 18:04:45.731] ℹ️ [INFO] [MicrophoneRecorder.swift:32] startRecording(): 开始录制，模式: microphone, 格式: M4A
[2025-10-28 18:04:45.931] ℹ️ [INFO] [MicrophoneRecorder.swift:115] logAvailableAudioInputDevices(): 发现音频输入设备数量: 2
  ✅ 录制完成:
    - 文件名: 麦克风_20251028-180445.wav
    - 时长: 00:03
    - 大小: 599 KB
    - 模式: 麦克风
✅ 实际录制测试完成
```

## 💡 使用建议

### 1. 定期清理日志
- 建议保留最近5-10个测试日志
- 定期运行清理功能避免占用过多磁盘空间

### 2. 问题排查
- 测试失败时，查看完整日志文件
- 关注错误信息和堆栈跟踪
- 对比成功和失败的日志差异

### 3. 性能监控
- 观察测试执行时间变化
- 监控内存和CPU使用情况
- 记录音频文件生成的统计信息

### 4. 自动化集成
```bash
# 在 CI/CD 中使用
./scripts/test_sdk.sh > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "✅ SDK 测试通过"
else
    echo "❌ SDK 测试失败，查看日志:"
    cat test_logs/$(ls -t test_logs/sdk_test_*.log | head -1)
fi
```

## 🔧 自定义配置

### 修改日志保存位置

编辑 `scripts/test_sdk.sh`：

```bash
# 修改这一行来改变日志目录
TEST_LOG_DIR="$ROOT_DIR/custom_log_dir"
```

### 修改日志文件命名

```bash
# 修改这一行来改变文件名格式
TEST_LOG_FILE="$TEST_LOG_DIR/custom_test_$TIMESTAMP.log"
```

## 📈 日志分析

### 提取测试结果

```bash
# 提取所有测试的通过率
grep -h "通过:" test_logs/sdk_test_*.log

# 查找失败的测试
grep -h "❌" test_logs/sdk_test_*.log

# 统计录制文件信息
grep -h "录制完成:" test_logs/sdk_test_*.log
```

### 性能趋势分析

```bash
# 提取测试执行时间
grep -h "测试时间:" test_logs/sdk_test_*.log
grep -h "测试结束时间:" test_logs/sdk_test_*.log

# 提取文件大小信息
grep -h "大小:" test_logs/sdk_test_*.log
```

---

通过这套完整的日志管理系统，你可以更好地跟踪 AudioRecord SDK 的测试历史，快速定位问题，并监控性能变化。

