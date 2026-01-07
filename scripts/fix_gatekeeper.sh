#!/bin/bash
# 修复Gatekeeper问题的脚本

echo "🔧 修复AudioRecord应用Gatekeeper问题..."

# 方法1：移除隔离属性
echo "方法1: 移除隔离属性"
xattr -d com.apple.quarantine /Applications/AudioRecordMac.app 2>/dev/null || echo "应用未安装到Applications目录"

# 方法2：如果用户从DMG运行，移除DMG的隔离属性
echo "方法2: 移除DMG隔离属性"
if [ -f "/Volumes/AudioRecord/AudioRecord.app" ]; then
    xattr -d com.apple.quarantine "/Volumes/AudioRecord/AudioRecord.app"
    echo "✅ 已移除DMG中应用的隔离属性"
fi

echo ""
echo "📋 如果仍然无法运行，请尝试以下方法："
echo "1. 右键点击应用 -> 打开"
echo "2. 系统偏好设置 -> 安全性与隐私 -> 允许从以下位置下载的应用 -> 选择'任何来源'"
echo "3. 或者运行: sudo spctl --master-disable"
echo ""
echo "⚠️  注意：这些操作会降低系统安全性，请谨慎使用"
