#!/system/bin/sh
#==============================================================================
# @author  bomo
# @description 微信保推送杀主进程 - 卸载清理脚本
# 精确清理 PID 文件定位的进程 + pgrep 兜底，确保无残留
#==============================================================================

# 1. 通过 PID 文件精确定位本模块进程，避免误杀系统进程
PID_FILE="/data/local/tmp/wechat_push_keeper.pid"
SCR_PID_FILE="/data/local/tmp/wechat_screen_kill.pid"
VOIP_PID_FILE="/data/local/tmp/wechat_voip_polling.pid"

for pid_file in "$PID_FILE" "$SCR_PID_FILE" "$VOIP_PID_FILE"; do
    if [ -f "$pid_file" ]; then
        target_pid=$(cat "$pid_file" 2>/dev/null)
        if [ -n "$target_pid" ] && kill -0 "$target_pid" 2>/dev/null; then
            kill -9 "$target_pid" 2>/dev/null
            pkill -9 -P "$target_pid" 2>/dev/null
        fi
        rm -f "$pid_file" 2>/dev/null
    fi
done

# 2. pgrep 兜底：防止 PID 文件未及时更新时有残留进程
for pid in $(pgrep -f "wechat_push_keeper" 2>/dev/null); do
    kill -9 "$pid" 2>/dev/null
done

# 3. 清理临时文件
rm -f /data/local/tmp/wechat_push_keeper.log 2>/dev/null
rm -f /data/local/tmp/wechat_push_keeper.conf 2>/dev/null
rm -f /data/local/tmp/wechat_push_keeper.log.bak 2>/dev/null
rm -f /data/local/tmp/wechat_push_keeper.log.tmp 2>/dev/null
rm -f /data/local/tmp/wechat_voip_polling.lock 2>/dev/null
rm -f /data/local/tmp/wechat_screen_kill.lock 2>/dev/null

exit 0