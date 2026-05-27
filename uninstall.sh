#!/system/bin/sh
#==============================================================================
# @author  bomo
# @description 微信保推送杀主进程 - 卸载清理脚本
#==============================================================================

# 使用模块目录作为工作目录，避免 SELinux 权限问题
MODDIR="/data/adb/modules/wechat_push_keeper"
TMP_DIR="${MODDIR}/tmp"

echo "🧹 正在清理微信保推送模块残留..."

# 1. 杀死所有模块相关进程（使用多种匹配模式确保全覆盖）
pkill -9 -f "wechat_push_keeper" 2>/dev/null
pkill -9 -f "monitor_config_reload" 2>/dev/null
pkill -9 -f "monitor_screen_off" 2>/dev/null
pkill -9 -f "logcat.*events.*am_proc_start" 2>/dev/null

# 2. 通过 PID 文件精确定位并终止进程
for pid_file in "$TMP_DIR/wechat_push_keeper.pid" "$TMP_DIR/wechat_screen_kill.pid" "$TMP_DIR/wechat_voip_polling.pid"; do
    if [ -f "$pid_file" ]; then
        target_pid=$(cat "$pid_file" 2>/dev/null)
        if [ -n "$target_pid" ] && kill -0 "$target_pid" 2>/dev/null; then
            kill -9 "$target_pid" 2>/dev/null
            pkill -9 -P "$target_pid" 2>/dev/null
        fi
        rm -f "$pid_file" 2>/dev/null
    fi
done

# 3. 等待进程完全终止
sleep 2

# 4. 清理所有临时文件（使用模块目录下的 tmp 目录）
rm -rf "$TMP_DIR" 2>/dev/null

# 5. 清理 /data/local/tmp 下的历史遗留文件（兼容旧版本）
rm -f /data/local/tmp/wechat_push_keeper.pid 2>/dev/null
rm -f /data/local/tmp/wechat_screen_kill.pid 2>/dev/null
rm -f /data/local/tmp/wechat_voip_polling.pid 2>/dev/null
rm -f /data/local/tmp/wechat_push_keeper.log 2>/dev/null
rm -f /data/local/tmp/wechat_push_keeper.log.tmp 2>/dev/null
rm -f /data/local/tmp/wechat_push_keeper.log.bak 2>/dev/null
rm -f /data/local/tmp/wechat_push_keeper.conf 2>/dev/null
rm -f /data/local/tmp/wechat_voip_polling.lock 2>/dev/null
rm -f /data/local/tmp/wechat_screen_kill.lock 2>/dev/null
rm -f /data/local/tmp/wechat_kill.lock 2>/dev/null
rm -f /data/local/tmp/wechat_fg_cooldown 2>/dev/null

echo "✅ 卸载完成，残留进程和文件已清理"
