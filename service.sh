#!/system/bin/sh
#==============================================================================
# @author  bomo
# @description 微信保推送杀主进程 - Logcat事件驱动 + 灭屏杀进程
#   1. 监听 am_proc_start 事件，检测微信非:push进程启动后等5秒杀灭
#   2. 监听屏幕熄灭事件，灭屏后立即杀灭非:push进程
#   3. VoIP通话期间延迟杀进程
#==============================================================================

LOG_FILE="/data/local/tmp/wechat_push_keeper.log"
VOIP_LOCK="/data/local/tmp/wechat_voip_polling.lock"
SCREEN_LOCK="/data/local/tmp/wechat_screen_kill.lock"
PID_FILE="/data/local/tmp/wechat_push_keeper.pid"
SCR_PID_FILE="/data/local/tmp/wechat_screen_kill.pid"
VOIP_PID_FILE="/data/local/tmp/wechat_voip_polling.pid"

# 记录主进程 PID
echo $$ > "$PID_FILE"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# 日志轮转：超过100行则截断
LINE_COUNT=$(wc -l < "$LOG_FILE" 2>/dev/null)
if [ "$LINE_COUNT" -gt 100 ] 2>/dev/null; then
    tail -n 50 "$LOG_FILE" > "${LOG_FILE}.tmp" 2>/dev/null
    mv "${LOG_FILE}.tmp" "$LOG_FILE" 2>/dev/null
fi
log "========== service.sh 启动 =========="

# 等待系统启动完成
log "等待系统启动完成..."
until [ "$(getprop sys.boot_completed)" == "1" ]; do
    sleep 5
done

log "系统启动完成，等待15秒..."
sleep 15
log "开始监听..."

# ==================== 工具函数 ====================

is_numeric() {
    case "$1" in
        ''|*[!0-9]*) return 1 ;;
        *) return 0 ;;
    esac
}

list_wechat_non_push_pids() {
    {
        ps -A 2>/dev/null || ps -e 2>/dev/null || ps 2>/dev/null
    } | while read -r ps_line; do
        case "$ps_line" in
            *com.tencent.mm*) ;;
            *) continue ;;
        esac
        case "$ps_line" in
            *:push*) continue ;;
        esac
        local pid
        pid=$(echo "$ps_line" | awk '{print $2}')
        if ! is_numeric "$pid"; then
            pid=$(echo "$ps_line" | awk '{print $1}')
        fi
        if is_numeric "$pid" && [ "$pid" -gt 100 ]; then
            echo "$pid"
        fi
    done
}

is_wechat_foreground() {
    local fg
    fg=$(dumpsys window 2>/dev/null | grep -E 'mCurrentFocus|mFocusedApp' | head -1 | awk '{print $3}' | cut -d'/' -f1 | tr -d '}')
    [ "$fg" = "com.tencent.mm" ]
}

is_wechat_voip_active() {
    local match_line
    match_line=$(dumpsys activity services com.tencent.mm 2>/dev/null | grep -i "VoipNewForegroundService")
    if [ -n "$match_line" ]; then
        log "VoIP服务检测到: $match_line"
        return 0
    fi
    return 1
}

is_screen_on() {
    # 检查屏幕是否亮着
    dumpsys power 2>/dev/null | grep -q "mWakefulness=Awake"
}

voip_polling_kill() {
    if [ -f "$VOIP_LOCK" ]; then
        return
    fi
    log "VoIP通话中，启动后台轮询（间隔20秒）..."
    (
        echo $$ > "$VOIP_PID_FILE"
        touch "$VOIP_LOCK"
        while true; do
            sleep 20
            if ! is_wechat_voip_active; then
                log "VoIP通话已结束，执行延迟杀进程"
                local pids
                pids=$(list_wechat_non_push_pids)
                if [ -n "$pids" ] && ! is_wechat_foreground; then
                    for pid in $pids; do
                        is_numeric "$pid" || continue
                        [ "$pid" -le 500 ] && continue
                        log "杀 PID=$pid (VoIP后延迟)"
                        kill -9 "$pid" 2>/dev/null
                    done
                fi
                rm -f "$VOIP_LOCK"
                exit 0
            fi
        done
    ) &
}

kill_wechat_non_push() {
    local pids
    pids=$(list_wechat_non_push_pids)
    if [ -z "$pids" ]; then
        return
    fi

    if is_wechat_foreground; then
        log "微信在前台，跳过"
        return
    fi

    if is_wechat_voip_active; then
        voip_polling_kill
        return
    fi

    for pid in $pids; do
        is_numeric "$pid" || continue
        [ "$pid" -le 500 ] && continue
        log "杀 PID=$pid"
        kill -9 "$pid" 2>/dev/null
    done
}

extract_proc_name() {
    local line="$1"
    local name
    name=$(echo "$line" | awk -F',' '{print $4}')
    if [ -n "$name" ]; then
        echo "$name"
        return
    fi
    name=$(echo "$line" | grep -oE 'com\.tencent\.mm[^,} )]*' | head -1)
    echo "$name"
}

# ==================== 灭屏监听（后台运行） ====================

monitor_screen_off() {
    echo $$ > "$SCR_PID_FILE"
    log "灭屏监听启动"
    local last_state="on"

    while true; do
        if is_screen_on; then
            last_state="on"
        elif [ "$last_state" = "on" ]; then
            # 屏幕刚从亮变灭
            last_state="off"
            log "检测到屏幕熄灭，执行杀进程"
            kill_wechat_non_push
            # 灭屏后延迟3秒再杀一次，确保进程彻底清理
            sleep 3
            kill_wechat_non_push
        fi
        sleep 2
    done
}

# ==================== 主循环 ====================

RETRY_DELAY=5
MAX_DELAY=120

# 启动灭屏监听（后台）
monitor_screen_off &

while true; do
    log "启动 logcat 监听 (重试间隔=${RETRY_DELAY}s)..."

    logcat -b events -s am_proc_start 2>>"$LOG_FILE" | while read -r line; do
        case "$line" in
            *com.tencent.mm*) ;;
            *) continue ;;
        esac

        log "事件: $line"

        PROC_NAME=$(extract_proc_name "$line")
        log "进程: [$PROC_NAME]"

        [ -z "$PROC_NAME" ] && continue
        case "$PROC_NAME" in
            *:push*) log "跳过 :push"; continue ;;
        esac

        log "非push进程 [$PROC_NAME]，等5秒..."
        sleep 5
        kill_wechat_non_push
    done

    log "logcat 管道断开，${RETRY_DELAY}秒后重试..."
    sleep "$RETRY_DELAY"

    RETRY_DELAY=$((RETRY_DELAY * 2))
    [ "$RETRY_DELAY" -gt "$MAX_DELAY" ] && RETRY_DELAY="$MAX_DELAY"

    kill_wechat_non_push
done