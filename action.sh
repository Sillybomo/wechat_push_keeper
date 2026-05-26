#!/system/bin/sh
#==============================================================================
# @author  bomo
# @description 微信保推送杀主进程 - WebUI 动作处理器
# 支持作为 CLI 终端命令或 WebUI CGI 后端
#   用法: sh action.sh [status|config|save|default|log|restart|help]
#==============================================================================

MODDIR="${0%/*}"
LOG_FILE="/data/local/tmp/wechat_push_keeper.log"
CONFIG_FILE="/data/local/tmp/wechat_push_keeper.conf"
PID_FILE="/data/local/tmp/wechat_push_keeper.pid"
SCR_PID_FILE="/data/local/tmp/wechat_screen_kill.pid"
VOIP_PID_FILE="/data/local/tmp/wechat_voip_polling.pid"

# ==================== 默认配置 ====================
DEFAULT_KILL_DELAY=5
DEFAULT_SCREEN_FIRST_KILL_DELAY=0
DEFAULT_SCREEN_KILL_DELAY=3
DEFAULT_SCREEN_POLL_INTERVAL=2
DEFAULT_VOIP_POLL_INTERVAL=20
DEFAULT_LOG_MAX_LINES=100
# ==================================================

is_numeric() {
    case "$1" in
        ''|*[!0-9]*) return 1 ;;
        *) return 0 ;;
    esac
}

read_config() {
    KILL_DELAY="$DEFAULT_KILL_DELAY"
    SCREEN_FIRST_KILL_DELAY="$DEFAULT_SCREEN_FIRST_KILL_DELAY"
    SCREEN_KILL_DELAY="$DEFAULT_SCREEN_KILL_DELAY"
    SCREEN_POLL_INTERVAL="$DEFAULT_SCREEN_POLL_INTERVAL"
    VOIP_POLL_INTERVAL="$DEFAULT_VOIP_POLL_INTERVAL"
    LOG_MAX_LINES="$DEFAULT_LOG_MAX_LINES"
    if [ -f "$CONFIG_FILE" ]; then
        . "$CONFIG_FILE" 2>/dev/null
    fi
}

write_config() {
    cat > "$CONFIG_FILE" <<EOF
# 微信保推送 - 用户配置
# 修改后执行: sh $MODDIR/action.sh restart 生效
KILL_DELAY=$1
SCREEN_FIRST_KILL_DELAY=$2
SCREEN_KILL_DELAY=$3
SCREEN_POLL_INTERVAL=$4
VOIP_POLL_INTERVAL=$5
LOG_MAX_LINES=$6
EOF
}

write_default_config() {
    write_config "$DEFAULT_KILL_DELAY" "$DEFAULT_SCREEN_FIRST_KILL_DELAY" \
        "$DEFAULT_SCREEN_KILL_DELAY" "$DEFAULT_SCREEN_POLL_INTERVAL" \
        "$DEFAULT_VOIP_POLL_INTERVAL" "$DEFAULT_LOG_MAX_LINES"
}

status() {
    read_config
    local running=0
    local screen_running=0
    local voip_running=0

    if [ -f "$PID_FILE" ]; then
        local pid
        pid=$(cat "$PID_FILE" 2>/dev/null)
        if is_numeric "$pid" && kill -0 "$pid" 2>/dev/null; then
            running=1
        fi
    fi

    if [ -f "$SCR_PID_FILE" ]; then
        local spid
        spid=$(cat "$SCR_PID_FILE" 2>/dev/null)
        if is_numeric "$spid" && kill -0 "$spid" 2>/dev/null; then
            screen_running=1
        fi
    fi

    if [ -f "$VOIP_PID_FILE" ]; then
        local vpid
        vpid=$(cat "$VOIP_PID_FILE" 2>/dev/null)
        if is_numeric "$vpid" && kill -0 "$vpid" 2>/dev/null; then
            voip_running=1
        fi
    fi

    local pid_val=""
    [ -f "$PID_FILE" ] && pid_val=$(cat "$PID_FILE" 2>/dev/null)

    local log_size=0
    [ -f "$LOG_FILE" ] && log_size=$(wc -c < "$LOG_FILE" 2>/dev/null | tr -d ' ')

    local log_lines=0
    [ -f "$LOG_FILE" ] && log_lines=$(wc -l < "$LOG_FILE" 2>/dev/null | tr -d ' ')

    cat <<JSON
{
  "running":$running,
  "screen_running":$screen_running,
  "voip_running":$voip_running,
  "pid":"${pid_val}",
  "log_size":${log_size:-0},
  "log_lines":${log_lines:-0},
  "kill_delay":$KILL_DELAY,
  "screen_first_kill_delay":$SCREEN_FIRST_KILL_DELAY,
  "screen_kill_delay":$SCREEN_KILL_DELAY,
  "screen_poll_interval":$SCREEN_POLL_INTERVAL,
  "voip_poll_interval":$VOIP_POLL_INTERVAL,
  "log_max_lines":$LOG_MAX_LINES
}
JSON
}

config() {
    read_config
    cat <<JSON
{
  "kill_delay":$KILL_DELAY,
  "screen_first_kill_delay":$SCREEN_FIRST_KILL_DELAY,
  "screen_kill_delay":$SCREEN_KILL_DELAY,
  "screen_poll_interval":$SCREEN_POLL_INTERVAL,
  "voip_poll_interval":$VOIP_POLL_INTERVAL,
  "log_max_lines":$LOG_MAX_LINES,
  "default_kill_delay":$DEFAULT_KILL_DELAY,
  "default_screen_first_kill_delay":$DEFAULT_SCREEN_FIRST_KILL_DELAY,
  "default_screen_kill_delay":$DEFAULT_SCREEN_KILL_DELAY,
  "default_screen_poll_interval":$DEFAULT_SCREEN_POLL_INTERVAL,
  "default_voip_poll_interval":$DEFAULT_VOIP_POLL_INTERVAL,
  "default_log_max_lines":$DEFAULT_LOG_MAX_LINES
}
JSON
}

log() {
    local tail_count="${1:-100}"
    if ! is_numeric "$tail_count"; then
        tail_count=100
    fi
    [ "$tail_count" -gt 500 ] && tail_count=500
    if [ -f "$LOG_FILE" ]; then
        tail -n "$tail_count" "$LOG_FILE" 2>/dev/null
    fi
}

save() {
    local kd="${1:-$DEFAULT_KILL_DELAY}"
    local sfkd="${2:-$DEFAULT_SCREEN_FIRST_KILL_DELAY}"
    local skd="${3:-$DEFAULT_SCREEN_KILL_DELAY}"
    local spi="${4:-$DEFAULT_SCREEN_POLL_INTERVAL}"
    local vpi="${5:-$DEFAULT_VOIP_POLL_INTERVAL}"
    local lml="${6:-$DEFAULT_LOG_MAX_LINES}"

    is_numeric "$kd" || kd=$DEFAULT_KILL_DELAY
    is_numeric "$sfkd" || sfkd=$DEFAULT_SCREEN_FIRST_KILL_DELAY
    is_numeric "$skd" || skd=$DEFAULT_SCREEN_KILL_DELAY

    # 第二次清理不允许小于第一次清理
    [ "$skd" -lt "$sfkd" ] 2>/dev/null && skd="$sfkd"
    is_numeric "$spi" || spi=$DEFAULT_SCREEN_POLL_INTERVAL
    is_numeric "$vpi" || vpi=$DEFAULT_VOIP_POLL_INTERVAL
    is_numeric "$lml" || lml=$DEFAULT_LOG_MAX_LINES

    write_config "$kd" "$sfkd" "$skd" "$spi" "$vpi" "$lml"
}

restart() {
    for pid_file in "$PID_FILE" "$SCR_PID_FILE" "$VOIP_PID_FILE"; do
        if [ -f "$pid_file" ]; then
            local tp
            tp=$(cat "$pid_file" 2>/dev/null)
            if is_numeric "$tp" && kill -0 "$tp" 2>/dev/null; then
                kill -9 "$tp" 2>/dev/null
            fi
        fi
    done

    rm -f /data/local/tmp/wechat_voip_polling.lock 2>/dev/null
    rm -f /data/local/tmp/wechat_screen_kill.lock 2>/dev/null

    if [ -f "$MODDIR/service.sh" ]; then
        nohup sh "$MODDIR/service.sh" > /dev/null 2>&1 &
    fi
}

default() {
    write_default_config
}

help_text() {
    cat <<HELP
微信保推送杀主进程 - 动作处理器
用法: sh action.sh <命令> [参数]

命令:
  status                 查看服务运行状态
  config                 查看当前配置项
  log [行数]              查看日志 (默认100行，最多500)
  save <KILL_DELAY> <SCREEN_FIRST_KILL_DELAY> <SCREEN_KILL_DELAY> <SCREEN_POLL_INTERVAL> <VOIP_POLL_INTERVAL> <LOG_MAX_LINES>
                          保存配置并重启服务
  default                恢复默认配置并重启服务
  restart                重启服务
  help                   显示此帮助

参数说明:
  KILL_DELAY              检测到非push进程后的等待秒数 (默认: $DEFAULT_KILL_DELAY)
  SCREEN_FIRST_KILL_DELAY 灭屏后第一次清理前等待秒数 (默认: $DEFAULT_SCREEN_FIRST_KILL_DELAY，0=立即清理)
  SCREEN_KILL_DELAY       灭屏第一次清理后到第二次清理的延迟秒数 (默认: $DEFAULT_SCREEN_KILL_DELAY)
  SCREEN_POLL_INTERVAL    灭屏监听轮询间隔秒数 (默认: $DEFAULT_SCREEN_POLL_INTERVAL)
  VOIP_POLL_INTERVAL      VoIP通话轮询间隔秒数 (默认: $DEFAULT_VOIP_POLL_INTERVAL)
  LOG_MAX_LINES           日志最大行数 (默认: $DEFAULT_LOG_MAX_LINES)
HELP
}

# ==================== 入口 ====================
# CGI 模式检测：Magisk HTTP 服务器通过 QUERY_STRING 传参
if [ -n "$GATEWAY_INTERFACE" ] && [ -n "$QUERY_STRING" ]; then
    # 解析 QUERY_STRING (格式: action=xxx&key=val&...)
    eval "$(echo "$QUERY_STRING" | awk -F'&' '{
      for(i=1;i<=NF;i++){
        split($i,a,"=");
        if(a[1]=="action") printf "CGI_ACTION=%s ", a[2];
        if(a[1]=="kd")     printf "CGI_KD=%s ", a[2];
        if(a[1]=="sfkd")   printf "CGI_SFKD=%s ", a[2];
        if(a[1]=="skd")    printf "CGI_SKD=%s ", a[2];
        if(a[1]=="spi")    printf "CGI_SPI=%s ", a[2];
        if(a[1]=="vpi")    printf "CGI_VPI=%s ", a[2];
        if(a[1]=="lml")    printf "CGI_LML=%s ", a[2];
      }
    }')"

    case "$CGI_ACTION" in
        status)
            status
            ;;
        config)
            config
            ;;
        log)
            log ""
            ;;
        save)
            save "$CGI_KD" "$CGI_SFKD" "$CGI_SKD" "$CGI_SPI" "$CGI_VPI" "$CGI_LML"
            restart
            status
            ;;
        default)
            default
            restart
            status
            ;;
        restart)
            restart
            status
            ;;
    esac
    exit 0
fi

# CLI 模式
action="${1:-help}"
shift 2>/dev/null

case "$action" in
    status)
        status
        ;;
    config)
        config
        ;;
    log)
        log "$1"
        ;;
    save)
        save "$1" "$2" "$3" "$4" "$5"
        restart
        status
        ;;
    default)
        default
        restart
        status
        ;;
    restart)
        restart
        status
        ;;
    help|--help|-h)
        help_text
        ;;
    *)
        echo "未知命令: $action"
        help_text
        exit 1
        ;;
esac
