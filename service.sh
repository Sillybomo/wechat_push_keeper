#!/system/bin/sh
#==============================================================================
# @author  bomo
# @description 微信保推送杀主进程 - Logcat事件驱动 + 灭屏结束进程
#   1. 监听 am_proc_start 事件，检测微信非:push进程启动后启动延迟结束
#   2. 监听屏幕熄灭事件，灭屏后立即结束非:push进程
#   3. VoIP通话期间延迟结束进程
#==============================================================================

# 使用模块目录作为工作目录，避免 SELinux 权限问题
MODDIR="/data/adb/modules/wechat_push_keeper"
TMP_DIR="${MODDIR}/tmp"
mkdir -p "$TMP_DIR" 2>/dev/null

LOG_FILE="${TMP_DIR}/wechat_push_keeper.log"
CONFIG_FILE="${TMP_DIR}/wechat_push_keeper.conf"
VOIP_LOCK="${TMP_DIR}/wechat_voip_polling.lock"
SCREEN_LOCK="${TMP_DIR}/wechat_screen_kill.lock"
PID_FILE="${TMP_DIR}/wechat_push_keeper.pid"
SCR_PID_FILE="${TMP_DIR}/wechat_screen_kill.pid"
VOIP_PID_FILE="${TMP_DIR}/wechat_voip_polling.pid"

# ==================== 默认配置 ====================
SCREEN_KILL_ENABLED=1         # 灭屏灭杀检测开关 (1=开启, 0=关闭)
KILL_DELAY=5                  # 检测到非push进程后的等待秒数 (原sleep 5)
SCREEN_FIRST_KILL_DELAY=0     # 灭屏后第一次清理前等待秒数 (0=立即清理)
SCREEN_KILL_DELAY=3           # 灭屏第一次清理后到第二次清理的延迟秒数
SCREEN_POLL_INTERVAL=2        # 灭屏监听轮询间隔 (原sleep 2)
VOIP_POLL_INTERVAL=20         # VoIP轮询间隔 (原sleep 20)
LOG_MAX_LINES=100             # 日志最大行数
# ==================================================

# 加载配置文件（如果存在）
if [ -f "$CONFIG_FILE" ]; then
    . "$CONFIG_FILE" 2>/dev/null
fi

# 记录主进程 PID
echo $$ > "$PID_FILE"

# 日志轮转：超过 LOG_MAX_LINES 行则截断保留一半
rotate_log() {
    local line_count
    line_count=$(wc -l < "$LOG_FILE" 2>/dev/null | tr -d ' ')
    if [ "${line_count:-0}" -gt "$LOG_MAX_LINES" ] 2>/dev/null; then
        local keep=$(( LOG_MAX_LINES / 2 ))
        tail -n "$keep" "$LOG_FILE" > "${LOG_FILE}.tmp" 2>/dev/null && \
            mv "${LOG_FILE}.tmp" "$LOG_FILE" 2>/dev/null
    fi
}

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
    rotate_log
}

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
    local ps_output
    ps_output=$(ps -A 2>/dev/null || ps -e 2>/dev/null || ps 2>/dev/null)
    if [ -z "$ps_output" ]; then
        return
    fi
    echo "$ps_output" | while read -r ps_line; do
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

# dumpsys 通用超时保护，避免长时间运行后卡住导致结束进程失效
DUMP_TIMEOUT=3

safe_dumpsys() {
    timeout "$DUMP_TIMEOUT" dumpsys "$@" 2>/dev/null
}

is_wechat_foreground() {
    local dump_line

    # 优先检测 mCurrentFocus（窗口焦点），直接匹配微信包名
    dump_line=$(safe_dumpsys window | grep 'mCurrentFocus')
    if echo "$dump_line" | grep -qE 'com\.tencent\.mm'; then
        log "[前台检测] mCurrentFocus=微信, 结果=微信前台"
        return 0
    fi

    # 若 mCurrentFocus 不是微信（如按住发语音时出现 PopupWindow），检测 mFocusedApp
    # PopupWindow 弹出时，mCurrentFocus 指向弹窗，但 mFocusedApp 仍指向微信
    dump_line=$(safe_dumpsys window | grep 'mFocusedApp')
    if echo "$dump_line" | grep -qE 'com\.tencent\.mm'; then
        log "[前台检测] mCurrentFocus非微信但mFocusedApp=微信, 结果=微信前台"
        return 0
    fi

    # 备用方案：通过 activity 判断前台
    local fg
    fg=$(safe_dumpsys activity activities 2>/dev/null | grep -E 'mResumedActivity|topResumedActivity' | head -1 | grep -oE 'com\.[a-zA-Z0-9.]+' | head -1)

    log "[前台检测] mCurrentFocus非微信,mFocusedApp非微信, activityTop=$fg, 结果=$([ "$fg" = "com.tencent.mm" ] && echo "微信前台" || echo "非微信前台")"
    [ "$fg" = "com.tencent.mm" ]
}

is_wechat_voip_active() {
    local match_line
    match_line=$(safe_dumpsys activity services com.tencent.mm | grep -i "VoipNewForegroundService")
    if [ -n "$match_line" ]; then
        log "VoIP服务检测到: $match_line"
        return 0
    fi
    return 1
}

is_screen_on() {
    # 检查屏幕是否亮着
    safe_dumpsys power | grep -q "mWakefulness=Awake"
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
            sleep "$VOIP_POLL_INTERVAL"
            if ! is_wechat_voip_active; then
                log "VoIP通话已结束，执行延迟结束进程"
                local pids
                pids=$(list_wechat_non_push_pids)
                if [ -n "$pids" ] && ! is_wechat_foreground; then
                    for pid in $pids; do
                        is_numeric "$pid" || continue
                        [ "$pid" -le 500 ] && continue
                        log "结束 PID=$pid (VoIP后延迟)"
                        kill -9 "$pid" 2>/dev/null
                    done
                fi
                rm -f "$VOIP_LOCK"
                exit 0
            fi
        done
    ) &
}

KILL_LOCK="${TMP_DIR}/wechat_kill.lock"
FG_COOLDOWN_FILE="${TMP_DIR}/wechat_fg_cooldown"
FG_COOLDOWN_SECONDS=10

is_foreground_cooldown_active() {
    [ ! -f "$FG_COOLDOWN_FILE" ] && return 1
    local last_fg
    last_fg=$(cat "$FG_COOLDOWN_FILE" 2>/dev/null)
    is_numeric "$last_fg" || return 1
    local now elapsed
    now=$(date +%s)
    elapsed=$((now - last_fg))
    if [ "$elapsed" -lt "$FG_COOLDOWN_SECONDS" ]; then
        local remain=$((FG_COOLDOWN_SECONDS - elapsed))
        log "[冷却] 冷却保护中（剩余${remain}s）"
        return 0
    fi
    log "[冷却] 冷却已过期（距今${elapsed}s）"
    return 1
}

set_foreground_cooldown() {
    date +%s > "$FG_COOLDOWN_FILE" 2>/dev/null
    log "[冷却] 设置前台冷却${FG_COOLDOWN_SECONDS}s"
}

kill_wechat_non_push() {
    (
        flock -n 9 || { log "[kill] flock竞争失败，跳过"; exit 0; }
        log "[kill] 获取锁，开始检查..."

        if is_wechat_foreground; then
            set_foreground_cooldown
            log "[kill] 微信在前台，跳过（已设冷却${FG_COOLDOWN_SECONDS}s）"
            exit 0
        fi

        if is_foreground_cooldown_active; then
            log "[kill] 冷却保护生效，跳过"
            exit 0
        fi

        local pids
        pids=$(list_wechat_non_push_pids)
        if [ -z "$pids" ]; then
            log "[kill] 无非push进程"
            exit 0
        fi

        if is_wechat_voip_active; then
            log "[kill] VoIP通话中，启动轮询"
            voip_polling_kill
            exit 0
        fi

        log "[kill] 准备结束进程: $pids"
        for pid in $pids; do
            is_numeric "$pid" || continue
            [ "$pid" -le 500 ] && continue
            if is_wechat_foreground; then
                set_foreground_cooldown
                log "[kill] kill前检测微信在前台，中断（已设冷却${FG_COOLDOWN_SECONDS}s）"
                break
            fi
            log "[kill] 执行 kill -9 PID=$pid"
            kill -9 "$pid" 2>/dev/null
            local ret=$?
            log "[kill] kill -9 PID=$pid 返回值=$ret"
        done
        log "[kill] 完成"
    ) 9>"$KILL_LOCK"
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

# ==================== 配置热加载 ====================

CONFIG_MTIME=0

apply_config() {
    [ -f "$CONFIG_FILE" ] || return 1
    . "$CONFIG_FILE" 2>/dev/null
    log "[配置] 热加载完成: SCREEN_KILL_ENABLED=$SCREEN_KILL_ENABLED KILL_DELAY=$KILL_DELAY SFKD=$SCREEN_FIRST_KILL_DELAY SKD=$SCREEN_KILL_DELAY SPI=$SCREEN_POLL_INTERVAL VPI=$VOIP_POLL_INTERVAL LML=$LOG_MAX_LINES"
    return 0
}

file_mtime() {
    local file="$1"
    local mt
    mt=$(stat -c %Y "$file" 2>/dev/null) || mt=$(date -r "$file" +%s 2>/dev/null) || mt=$(date +%s)
    echo "$mt"
}

check_config_reload() {
    local new_mtime
    new_mtime=$(file_mtime "$CONFIG_FILE")
    if [ "$new_mtime" != "$CONFIG_MTIME" ]; then
        CONFIG_MTIME="$new_mtime"
        apply_config
    fi
}

# ==================== 灭屏监听（后台运行） ====================

monitor_screen_off() {
    echo $$ > "$SCR_PID_FILE"
    log "灭屏监听启动"
    local last_state="on"

    while true; do
        check_config_reload
        # 灭屏灭杀检测开关关闭时，跳过检测
        if [ "$SCREEN_KILL_ENABLED" != "1" ]; then
            last_state="on"
            sleep "$SCREEN_POLL_INTERVAL"
            continue
        fi
        if is_screen_on; then
            last_state="on"
        elif [ "$last_state" = "on" ]; then
            last_state="off"
            log "检测到屏幕熄灭，清除前台冷却状态..."
            rm -f "$FG_COOLDOWN_FILE" 2>/dev/null
            log "等待 ${SCREEN_FIRST_KILL_DELAY}秒 后执行第一次清理..."
            sleep "$SCREEN_FIRST_KILL_DELAY"
            kill_wechat_non_push
            log "等待 ${SCREEN_KILL_DELAY}秒 后执行第二次清理..."
            sleep "$SCREEN_KILL_DELAY"
            kill_wechat_non_push
        fi
        sleep "$SCREEN_POLL_INTERVAL"
    done
}

# ==================== 主循环 ====================

RETRY_DELAY=5
MAX_DELAY=120

# 启动灭屏监听（后台）
monitor_screen_off &

# 初始化配置修改时间
CONFIG_MTIME=$(file_mtime "$CONFIG_FILE")

while true; do
    check_config_reload
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

        # top-activity 表示用户主动打开微信（如发语音），不杀
        case "$line" in
            *top-activity*) log "跳过 top-activity（用户主动打开）"; continue ;;
        esac

        # 微信在前台时，所有子进程都不杀（用户正在使用，如发语音）
        if is_wechat_foreground; then
            set_foreground_cooldown
            log "[事件] 微信在前台，跳过[$PROC_NAME]（已设冷却${FG_COOLDOWN_SECONDS}s）"
            continue
        fi

        log "[事件] 微信不在前台，延迟${KILL_DELAY}s后kill [$PROC_NAME]"
        # 后台子进程延迟kill，不阻塞事件循环
        (
            sleep "$KILL_DELAY"
            kill_wechat_non_push
        ) &
    done

    log "logcat 管道断开，${RETRY_DELAY}秒后重试..."
    sleep "$RETRY_DELAY"

    RETRY_DELAY=$((RETRY_DELAY * 2))
    [ "$RETRY_DELAY" -gt "$MAX_DELAY" ] && RETRY_DELAY="$MAX_DELAY"

    kill_wechat_non_push
done