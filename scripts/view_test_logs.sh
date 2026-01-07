#!/bin/bash

# 测试日志查看脚本

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_LOG_DIR="$ROOT_DIR/test_logs"

echo "📋 AudioRecord SDK 测试日志管理"
echo "================================"

# 检查日志目录是否存在
if [ ! -d "$TEST_LOG_DIR" ]; then
    echo "❌ 测试日志目录不存在: $TEST_LOG_DIR"
    echo "请先运行测试脚本生成日志"
    exit 1
fi

# 获取日志文件列表
LOG_FILES=($(ls -t "$TEST_LOG_DIR"/sdk_test_*.log 2>/dev/null))

if [ ${#LOG_FILES[@]} -eq 0 ]; then
    echo "❌ 未找到测试日志文件"
    echo "请先运行 ./scripts/test_sdk.sh 生成测试日志"
    exit 1
fi

echo "📁 日志目录: $TEST_LOG_DIR"
echo "📊 找到 ${#LOG_FILES[@]} 个测试日志文件"
echo ""

# 显示可用的操作
show_menu() {
    echo "请选择操作:"
    echo "  1) 查看最新的测试日志"
    echo "  2) 列出所有测试日志"
    echo "  3) 查看指定的测试日志"
    echo "  4) 删除旧的测试日志"
    echo "  5) 查看日志统计信息"
    echo "  6) 退出"
    echo ""
    read -p "请输入选择 (1-6): " choice
}

# 查看最新日志
view_latest_log() {
    local latest_log="${LOG_FILES[0]}"
    echo "📄 查看最新测试日志: $(basename "$latest_log")"
    echo "================================"
    cat "$latest_log"
}

# 列出所有日志
list_all_logs() {
    echo "📋 所有测试日志文件:"
    echo "================================"
    for i in "${!LOG_FILES[@]}"; do
        local log_file="${LOG_FILES[$i]}"
        local file_name=$(basename "$log_file")
        local file_size=$(du -h "$log_file" | cut -f1)
        local file_time=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$log_file" 2>/dev/null || date -r "$log_file" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "未知时间")
        
        printf "%2d) %s (%s) - %s\n" $((i+1)) "$file_name" "$file_size" "$file_time"
    done
}

# 查看指定日志
view_specific_log() {
    list_all_logs
    echo ""
    read -p "请输入要查看的日志编号 (1-${#LOG_FILES[@]}): " log_num
    
    if [[ "$log_num" =~ ^[0-9]+$ ]] && [ "$log_num" -ge 1 ] && [ "$log_num" -le ${#LOG_FILES[@]} ]; then
        local selected_log="${LOG_FILES[$((log_num-1))]}"
        echo "📄 查看测试日志: $(basename "$selected_log")"
        echo "================================"
        cat "$selected_log"
    else
        echo "❌ 无效的编号"
    fi
}

# 删除旧日志
cleanup_old_logs() {
    echo "🗑️ 清理旧的测试日志"
    echo "================================"
    
    if [ ${#LOG_FILES[@]} -le 3 ]; then
        echo "📊 当前只有 ${#LOG_FILES[@]} 个日志文件，建议保留"
        return
    fi
    
    echo "当前有 ${#LOG_FILES[@]} 个测试日志文件"
    read -p "保留最新的几个日志文件? (默认: 5): " keep_count
    
    # 默认保留5个
    keep_count=${keep_count:-5}
    
    if [[ ! "$keep_count" =~ ^[0-9]+$ ]] || [ "$keep_count" -lt 1 ]; then
        echo "❌ 无效的数量"
        return
    fi
    
    if [ "$keep_count" -ge ${#LOG_FILES[@]} ]; then
        echo "📊 要保留的数量大于等于现有文件数，无需清理"
        return
    fi
    
    # 删除旧文件
    local deleted_count=0
    for ((i=keep_count; i<${#LOG_FILES[@]}; i++)); do
        local old_log="${LOG_FILES[$i]}"
        echo "🗑️ 删除: $(basename "$old_log")"
        rm "$old_log"
        ((deleted_count++))
    done
    
    echo "✅ 已删除 $deleted_count 个旧日志文件，保留最新的 $keep_count 个"
}

# 查看日志统计
view_log_stats() {
    echo "📊 测试日志统计信息"
    echo "================================"
    
    local total_files=${#LOG_FILES[@]}
    local total_size=0
    local oldest_file=""
    local newest_file=""
    
    # 计算总大小
    for log_file in "${LOG_FILES[@]}"; do
        local size_bytes=$(stat -f "%z" "$log_file" 2>/dev/null || stat -c "%s" "$log_file" 2>/dev/null || echo "0")
        total_size=$((total_size + size_bytes))
    done
    
    # 转换为人类可读格式
    local total_size_human
    if command -v numfmt >/dev/null 2>&1; then
        total_size_human=$(numfmt --to=iec-i --suffix=B $total_size)
    else
        # 简单的大小转换
        if [ $total_size -gt 1048576 ]; then
            total_size_human="$((total_size / 1048576))MB"
        elif [ $total_size -gt 1024 ]; then
            total_size_human="$((total_size / 1024))KB"
        else
            total_size_human="${total_size}B"
        fi
    fi
    
    oldest_file=$(basename "${LOG_FILES[-1]}")
    newest_file=$(basename "${LOG_FILES[0]}")
    
    echo "📁 日志目录: $TEST_LOG_DIR"
    echo "📊 总文件数: $total_files"
    echo "💾 总大小: $total_size_human"
    echo "🆕 最新日志: $newest_file"
    echo "🕰️ 最旧日志: $oldest_file"
    
    echo ""
    echo "📋 最近5个测试日志:"
    for i in "${!LOG_FILES[@]}"; do
        if [ $i -ge 5 ]; then break; fi
        local log_file="${LOG_FILES[$i]}"
        local file_name=$(basename "$log_file")
        local file_size=$(du -h "$log_file" | cut -f1)
        printf "  %s (%s)\n" "$file_name" "$file_size"
    done
}

# 主循环
while true; do
    echo ""
    show_menu
    
    case $choice in
        1)
            view_latest_log
            ;;
        2)
            list_all_logs
            ;;
        3)
            view_specific_log
            ;;
        4)
            cleanup_old_logs
            # 重新获取日志文件列表
            LOG_FILES=($(ls -t "$TEST_LOG_DIR"/sdk_test_*.log 2>/dev/null))
            ;;
        5)
            view_log_stats
            ;;
        6)
            echo "👋 退出日志查看器"
            exit 0
            ;;
        *)
            echo "❌ 无效选择，请输入 1-6"
            ;;
    esac
    
    echo ""
    read -p "按 Enter 键继续..."
done
