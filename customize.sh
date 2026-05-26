#!/system/bin/sh

wait_volume_key() {
    while true; do
        _ev=$(getevent -lqc 1 2>/dev/null)
        case "$_ev" in
            *KEY_VOLUMEUP*DOWN*)   return 0 ;;
            *KEY_VOLUMEDOWN*DOWN*) return 1 ;;
        esac
    done
}

ui_print " "
ui_print "- 请仔细阅读下列模块说明"
ui_print " "
ui_print "- 1.任何模块均有影响系统稳定性乃至损坏设备的可能"
ui_print "- 2.模块作者不对刷写此模块带来的任何后果负责"
ui_print "- 3.使用 WebUI 可在管理器内点击模块进入"
ui_print "- 4.日志路径: /data/local/tmp/wechat_push_keeper.log"
ui_print "- 5.调整配置后保存即可生效，无需重启设备"
ui_print " "
ui_print "- [音量＋]我已仔细阅读并知悉上述说明"
ui_print "- [音量－]退出安装"
ui_print " "
wait_volume_key
if [ $? -eq 1 ]; then
    abort "- 退出安装"
fi
ui_print "- 已确认阅读说明，继续安装"
ui_print " "

ui_print " "
ui_print "- 正在安装..."
ui_print " "

if [ -f "$MODPATH/updatelog.txt" ]; then
    ui_print "- 更新日志:"
    while IFS= read -r line; do
        ui_print "  $line"
    done < "$MODPATH/updatelog.txt"
fi

ui_print " "
ui_print "- 安装完成"
ui_print "- 重启后即可生效"
ui_print "- 日志路径: /data/local/tmp/wechat_push_keeper.log"
ui_print "- WebUI: 在模块管理器中点击模块进入"
ui_print " "