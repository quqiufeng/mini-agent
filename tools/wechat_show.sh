#!/usr/bin/env bash
# @desc 显示微信：连接 Redmi 手机，打开微信并把画面镜像到 GUI“当前应用”预览
# @usage tools/wechat_show.sh start | stop | status
# @rule 复用汽水音乐的 scrcpy + winctl mirror-sync 方式；只镜像画面不接管触控，不改手机音量
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DISPLAY="${DISPLAY:-:0}"
export XAUTHORITY="${XAUTHORITY:-/tmp/xauth_pLarOv}"
SERIAL="${PHONE2_SERIAL:-192.168.1.59:5555}"
PIDFILE=/tmp/myagent-wechat-show.pid
FOLLOW_PIDFILE=/tmp/myagent_mirror_follow.pid
STATE="$(cd "$(dirname "$0")" && pwd)/state.sh"
LOG=/tmp/myagent-wechat-show.log
PKG=com.tencent.mm

running() { [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; }

ensure_phone() {
    local st
    st=$(adb -s "$SERIAL" get-state 2>/dev/null || true)
    if [ "$st" != "device" ]; then
        adb connect "$SERIAL" >/dev/null 2>&1 || true
        sleep 1
        st=$(adb -s "$SERIAL" get-state 2>/dev/null || true)
    fi
    [ "$st" = "device" ] || { echo "[wechat_show] 手机未连接: $SERIAL" >&2; exit 1; }
}

case "${1:-start}" in
    start)
        ensure_phone
        adb -s "$SERIAL" shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 \
            || adb -s "$SERIAL" shell am start -n com.tencent.mm/.ui.LauncherUI >/dev/null 2>&1 || true
        if running; then
            kill "$(cat "$PIDFILE")" 2>/dev/null || true
            sleep 0.3
        fi
        setsid nohup scrcpy -s "$SERIAL" --no-audio -n \
            --window-borderless --always-on-top --window-width 450 --window-height 900 \
            --window-title=scrcpy-wechat >"$LOG" 2>&1 </dev/null &
        echo $! > "$PIDFILE"
        "$STATE" set display.wechat on "$(cat "$PIDFILE")"
        sleep 2
        "$DIR/lua.sh" "$DIR/winctl.lua" mirror-sync 2>/dev/null || true
        if [ -f "$FOLLOW_PIDFILE" ] && kill -0 "$(cat "$FOLLOW_PIDFILE")" 2>/dev/null; then
            kill "$(cat "$FOLLOW_PIDFILE")" 2>/dev/null || true
        fi
        setsid nohup "$DIR/lua.sh" "$DIR/winctl.lua" mirror-follow \
            >/tmp/myagent-wechat-follow.log 2>&1 </dev/null &
        echo $! > "$FOLLOW_PIDFILE"
        sleep 1
        echo "微信已显示「当前应用」($SERIAL)"
        ;;
    stop)
        if [ -f "$FOLLOW_PIDFILE" ] && kill -0 "$(cat "$FOLLOW_PIDFILE")" 2>/dev/null; then
            kill "$(cat "$FOLLOW_PIDFILE")" 2>/dev/null || true
        fi
        rm -f "$FOLLOW_PIDFILE"
        if running; then
            kill "$(cat "$PIDFILE")" 2>/dev/null || true
            "$STATE" set display.wechat off "$(cat "$PIDFILE")"
            rm -f "$PIDFILE" /tmp/myagent_mirror.id
            echo "已关闭微信预览"
        else
            echo "没有在显示微信"
        fi
        ;;
    status)
        if running; then
            echo "显示中 pid=$(cat "$PIDFILE") serial=$SERIAL"
            adb -s "$SERIAL" shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus || true
        else
            echo "未显示"
        fi
        ;;
    *)
        echo "用法: $0 start | stop | status" >&2
        exit 2
        ;;
esac
