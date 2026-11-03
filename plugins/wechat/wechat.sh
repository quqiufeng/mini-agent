#!/usr/bin/env bash
# @desc 显示微信：连接 Redmi 手机，打开微信并把画面镜像到 GUI“当前应用”预览
# @usage plugins/wechat/wechat.sh start | stop | status
# @rule 设备归属走 device.sh 的 mirror lease；状态走 state.sh；不再使用 pid 文件
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/../.." && pwd)"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DISPLAY="${DISPLAY:-:0}"
export XAUTHORITY="${XAUTHORITY:-/tmp/xauth_pLarOv}"
SERIAL="${PHONE2_SERIAL:-192.168.1.59:5555}"
STATE="$ROOT/tools/state.sh"
DEVICE="$ROOT/tools/device.sh"
FOLLOW_PIDFILE=/tmp/myagent_mirror_follow.pid
PKG=com.tencent.mm

alive_cmd() { [ -n "${1:-}" ] && [ "$1" -gt 1 ] 2>/dev/null && kill -0 "$1" 2>/dev/null || return 1; tr '\0' ' ' < "/proc/$1/cmdline" 2>/dev/null | grep -q "$2"; }
pid_of() { "$STATE" get display.wechat 2>/dev/null | awk '{print $3}'; }
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
        cur=$(pid_of)
        if [ -n "$cur" ] && alive_cmd "$cur" scrcpy; then
            "$DEVICE" acquire mirror wechat 3600 "$cur" >/dev/null 2>&1 || {
                echo "[wechat_show] 镜像被占用" >&2; exit 1
            }
            "$STATE" set display.wechat on "$cur"
            echo "微信已在预览 ($SERIAL)"; exit 0
        fi
        adb -s "$SERIAL" shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 \
            || adb -s "$SERIAL" shell am start -n com.tencent.mm/.ui.LauncherUI >/dev/null 2>&1 || true
        setsid nohup scrcpy -s "$SERIAL" --no-audio -n \
            --window-borderless --always-on-top --window-width 405 --window-height 900 \
            --window-title=scrcpy-wechat >/tmp/myagent-wechat-show.log 2>&1 </dev/null &
        pid=$!
        sleep 2
        if ! alive_cmd "$pid" scrcpy; then
            "$STATE" set display.wechat off 0
            echo "[wechat_show] scrcpy 启动失败" >&2; exit 1
        fi
        if ! "$DEVICE" acquire mirror wechat 3600 "$pid" >/dev/null 2>&1; then
            kill "$pid" 2>/dev/null || true
            echo "[wechat_show] 镜像被占用" >&2; exit 1
        fi
        "$STATE" set display.wechat on "$pid"
        "$ROOT/tools/lua.sh" "$ROOT/tools/winctl.lua" mirror-sync 2>/dev/null || true
        if [ -f "$FOLLOW_PIDFILE" ] && kill -0 "$(cat "$FOLLOW_PIDFILE")" 2>/dev/null; then
            kill "$(cat "$FOLLOW_PIDFILE")" 2>/dev/null || true
        fi
        setsid nohup "$ROOT/tools/lua.sh" "$ROOT/tools/winctl.lua" mirror-follow \
            >/tmp/myagent-wechat-follow.log 2>&1 </dev/null &
        echo $! > "$FOLLOW_PIDFILE"
        echo "微信已显示「当前应用」($SERIAL)"
        ;;
    stop)
        if [ -f "$FOLLOW_PIDFILE" ] && kill -0 "$(cat "$FOLLOW_PIDFILE")" 2>/dev/null; then
            kill "$(cat "$FOLLOW_PIDFILE")" 2>/dev/null || true
        fi
        rm -f "$FOLLOW_PIDFILE"
        pid=$(pid_of)
        if [ -n "$pid" ] && alive_cmd "$pid" scrcpy; then
            kill "$pid" 2>/dev/null || true
        fi
        [ -n "$pid" ] && "$DEVICE" release mirror "$pid" >/dev/null 2>&1 || true
        "$STATE" set display.wechat off 0
        rm -f /tmp/myagent_mirror.id
        echo "已关闭微信预览"
        ;;
    status)
        pid=$(pid_of)
        if [ -n "$pid" ] && alive_cmd "$pid" scrcpy; then
            echo "显示中 pid=$pid serial=$SERIAL"
        else echo "未显示"; fi
        ;;
    *)
        echo "用法: $0 start | stop | status" >&2
        exit 2
        ;;
esac
