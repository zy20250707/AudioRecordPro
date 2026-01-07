#!/bin/bash
# 完整的Gatekeeper修复脚本

echo "🔧 完整修复AudioRecord应用Gatekeeper问题..."

APP_PATH="/Applications/AudioRecordMac.app"
DMG_APP_PATH="/Volumes/AudioRecord/AudioRecord.app"

# 检查应用是否存在
if [ -d "$APP_PATH" ]; then
    echo "📱 修复已安装的应用..."
    
    # 移除所有隔离属性
    xattr -dr com.apple.quarantine "$APP_PATH" 2>/dev/null || true
    xattr -dr com.apple.metadata:kMDItemWhereFroms "$APP_PATH" 2>/dev/null || true
    
    # 重新签名（使用adhoc签名）
    codesign --force --deep --sign - "$APP_PATH" 2>/dev/null || true
    
    echo "✅ 已修复已安装的应用"
fi

# 检查DMG中的应用
if [ -d "$DMG_APP_PATH" ]; then
    echo "💿 修复DMG中的应用..."
    
    # 移除所有隔离属性
    xattr -dr com.apple.quarantine "$DMG_APP_PATH" 2>/dev/null || true
    xattr -dr com.apple.metadata:kMDItemWhereFroms "$DMG_APP_PATH" 2>/dev/null || true
    
    # 重新签名
    codesign --force --deep --sign - "$DMG_APP_PATH" 2>/dev/null || true
    
    echo "✅ 已修复DMG中的应用"
fi

echo ""
echo "🎯 如果仍然无法运行，请尝试以下方法："
echo ""
echo "方法1: 右键点击应用 -> 打开"
echo "方法2: 系统偏好设置 -> 安全性与隐私 -> 允许从以下位置下载的应用"
echo "方法3: 临时禁用Gatekeeper (不推荐):"
echo "     sudo spctl --master-disable"
echo ""
echo "方法4: 只允许这个应用 (推荐):"
echo "     sudo spctl --add /Applications/AudioRecordMac.app"
echo ""
echo "⚠️  注意：这些操作会降低系统安全性，请谨慎使用"
