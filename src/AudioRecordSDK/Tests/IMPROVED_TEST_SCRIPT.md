# 改进的测试脚本功能

## 🎯 问题解决

### 原问题
- 测试脚本在等待用户输入时会卡住控制台
- 无法自动化运行测试
- 日志输出不够完整

### 解决方案
- ✅ 添加命令行参数控制测试行为
- ✅ 自动化输入处理，避免卡住
- ✅ 完整的日志记录和管理系统
- ✅ 交互式日志查看工具

## 🚀 新功能

### 1. 命令行参数支持

```bash
# 查看帮助
./scripts/test_sdk.sh --help

# 自动进行录制测试（不会卡住）
./scripts/test_sdk.sh --record

# 跳过录制测试（快速测试）
./scripts/test_sdk.sh --no-record

# 交互式询问（默认行为）
./scripts/test_sdk.sh
```

### 2. 完整的日志系统

#### 自动日志记录
- 📝 每次测试自动生成带时间戳的日志文件
- 📊 记录系统环境、Swift版本等信息
- 🔄 同时输出到控制台和日志文件
- 📈 包含测试开始和结束时间

#### 日志文件格式
```
test_logs/sdk_test_YYYYMMDD_HHMMSS.log
```

#### 日志内容结构
```
AudioRecord SDK 测试日志
测试时间: Tue Oct 28 18:19:43 CST 2025
测试环境: Darwin VOIDZHANG-MC4 24.3.0 ...
Swift 版本: Apple Swift version 6.1 ...
================================

[完整的测试输出]

================================
测试结束时间: Tue Oct 28 18:19:46 CST 2025
日志文件位置: /path/to/log/file
```

### 3. 日志管理工具

```bash
./scripts/view_test_logs.sh
```

提供以下功能：
- 📄 查看最新的测试日志
- 📋 列出所有测试日志
- 🔍 查看指定的测试日志
- 🗑️ 删除旧的测试日志
- 📊 查看日志统计信息

## 📋 使用示例

### 快速测试（不录制）
```bash
./scripts/test_sdk.sh --no-record
```
输出：
```
🧪 AudioRecord SDK 测试脚本
================================
📝 测试日志将保存到: test_logs/sdk_test_20251028_181936.log
⏭️ 将跳过实际录制测试
================================
[编译和测试过程...]
✅ SDK 测试完成
📝 完整日志已保存到: test_logs/sdk_test_20251028_181936.log
📊 日志文件大小: 4.0K
```

### 自动录制测试
```bash
./scripts/test_sdk.sh --record
```
- 自动回答 "y" 进行录制测试
- 不会卡住等待用户输入
- 完整记录录制过程

### 查看测试历史
```bash
./scripts/view_test_logs.sh
```
交互式菜单：
```
📋 AudioRecord SDK 测试日志管理
================================
📁 日志目录: /path/to/test_logs
📊 找到 5 个测试日志文件

请选择操作:
  1) 查看最新的测试日志
  2) 列出所有测试日志
  3) 查看指定的测试日志
  4) 删除旧的测试日志
  5) 查看日志统计信息
  6) 退出
```

## 🔧 技术实现

### 输入处理机制
```bash
case "$RECORD_TEST" in
    "yes")
        echo "y" | "$TEST_BUILD_DIR/$APP_NAME" 2>&1 | tee -a "$TEST_LOG_FILE"
        ;;
    "no")
        echo "n" | "$TEST_BUILD_DIR/$APP_NAME" 2>&1 | tee -a "$TEST_LOG_FILE"
        ;;
    *)
        "$TEST_BUILD_DIR/$APP_NAME" 2>&1 | tee -a "$TEST_LOG_FILE"
        ;;
esac
```

### 日志文件管理
- 使用 `tee` 命令同时输出到控制台和文件
- 时间戳格式：`YYYYMMDD_HHMMSS`
- 自动创建日志目录
- 记录文件大小和位置

### 环境信息收集
```bash
{
    echo "AudioRecord SDK 测试日志"
    echo "测试时间: $(date)"
    echo "测试环境: $(uname -a)"
    echo "Swift 版本: $(swift --version 2>/dev/null || echo '未知')"
    echo "================================"
    echo ""
} > "$TEST_LOG_FILE"
```

## 📊 测试结果示例

### 基础测试结果
```
📊 测试总结:
==================================================
总测试数: 7
通过: 7 ✅
失败: 0 ❌
跳过: 0 ⚠️

🎉 所有测试通过！SDK 工作正常。
```

### 日志统计信息
```
📊 测试日志统计信息
================================
📁 日志目录: /path/to/test_logs
📊 总文件数: 5
💾 总大小: 18KB
🆕 最新日志: sdk_test_20251028_181936.log
🕰️ 最旧日志: sdk_test_20251028_181619.log
```

## 💡 最佳实践

### 1. CI/CD 集成
```bash
# 在自动化脚本中使用
./scripts/test_sdk.sh --no-record
if [ $? -eq 0 ]; then
    echo "✅ SDK 测试通过"
else
    echo "❌ SDK 测试失败"
    cat test_logs/$(ls -t test_logs/sdk_test_*.log | head -1)
    exit 1
fi
```

### 2. 开发调试
```bash
# 快速验证修改
./scripts/test_sdk.sh --no-record

# 完整功能测试
./scripts/test_sdk.sh --record

# 查看测试历史
./scripts/view_test_logs.sh
```

### 3. 日志管理
- 定期清理旧日志（保留最近5-10个）
- 重要测试结果可以备份到其他位置
- 使用日志分析工具提取关键信息

## 🎉 改进效果

### 解决的问题
- ✅ **不再卡住** - 自动化输入处理
- ✅ **完整日志** - 所有输出都被记录
- ✅ **易于查看** - 专门的日志管理工具
- ✅ **自动化友好** - 支持 CI/CD 集成

### 新增价值
- 📈 **测试历史追踪** - 可以对比不同时间的测试结果
- 🔍 **问题排查** - 完整的日志便于调试
- 📊 **统计分析** - 可以分析测试趋势
- 🛠️ **开发效率** - 快速验证和完整测试两种模式

现在的测试脚本已经完全解决了卡住的问题，并提供了强大的日志管理功能！🎉

