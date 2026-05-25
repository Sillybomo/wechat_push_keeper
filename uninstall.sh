#!/system/bin/sh
#==============================================================================
# @author  bomo
# @description 微信保推送杀主进程 - 卸载清理脚本
#==============================================================================

# 精确清理：通过 PID 文件定位本模块进程，避免误杀系统其他进程
PID_FILE="/data/local/tmp/wechat_push_keeper.pid"
SCR_PID_FILE="/data/local/tmp/wechat_screen_kill.pid"
VOIP_PID_FILE="/data/local/tmp/wechat_voip_polling.pid"

for pid_file in "$PID_FILE" "$SCR_PID_FILE" "$VOIP_PID_FILE"; do
    if [ -f "$pid_file" ]; then
        target_pid=$(cat "$pid_file" 2>/dev/null)
        if [ -n "$target_pid" ] && kill -0 "$target_pid" 2>/dev/null; then
            kill -9 "$target_pid" 2>/dev/null
        fi
        # 杀子进程组，确保管道和子 shell 也被清理
        if [ -n "$target_pid" ]; then
            pkill -9 -P "$target_pid" 2>/dev/null
        fi
        rm -f "$pid_file" 2>/dev/null
    fi
done

# 清理临时文件
rm -f /data/local/tmp/wechat_push_keeper.log 2>/dev/null
rm -f /data/local/tmp/wechat_push_keeper.log.bak 2>/dev/null
rm -f /data/local/tmp/wechat_push_keeper.log.tmp 2>/dev/null
rm -f /data/local/tmp/wechat_voip_polling.lock 2>/dev/null
rm -f /data/local/tmp/wechat_screen_kill.lock 2>/dev/null

exit 0