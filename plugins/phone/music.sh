#!/usr/bin/env bash
# @desc 手机汽水音乐：启动 com.luna.music，声音经 scrcpy 转到本机 USB 小音箱
# @usage plugins/phone/music.sh play | pause | resume | stop | status
# @rule 设备归属走 device.sh 的 phone lease；状态走 state.sh；不再使用 pid 文件
set -uo pipefail
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DISPLAY="${DISPLAY:-:0}"
export XAUTHORITY="${XAUTHORITY:-/tmp/xauth_pLarOv}"
DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/../.." && pwd)"
STATE="$ROOT/tools/state.sh"
DEVICE="$ROOT/tools/device.sh"
FOLLOW_PIDFILE=/tmp/myagent_mirror_follow.pid
PKG=com.luna.music

alive_cmd() { [ -n "${1:-}" ] && [ "$1" -gt 1 ] 2>/dev/null && kill -0 "$1" 2>/dev/null || return 1; tr '\0' ' ' < "/proc/$1/cmdline" 2>/dev/null | grep -q "$2"; }
pid_of() { "$STATE" get media.phone 2>/dev/null | awk '{print $3}'; }
serial() {
    if [ -n "${PHONE_SERIAL:-}" ]; then echo "$PHONE_SERIAL"; return; fi
    for s in $(adb devices | awk 'NR>1 && $2=="device" {print $1}'); do
        m=$(adb -s "$s" shell getprop ro.product.model 2>/dev/null | tr -d '\r')
        case "$m" in *Z18*|*NX606J*) echo "$s"; return ;; esac
    done
    ip=$("$ROOT/tools/device.sh" ip phone 2>/dev/null || true)
    if [ -n "$ip" ] && adb -s "$ip:5555" get-state 2>/dev/null | grep -q device; then
        echo "$ip:5555"; return
    fi
    if adb -s 192.168.1.59:5555 get-state 2>/dev/null | grep -q device; then
        echo 192.168.1.59:5555; return
    fi
    "$ROOT/plugins/phone/phone_ip.sh" 2>/dev/null
}

case "${1:-}" in
    play)
        s=$(serial); [ -n "$s" ] || { echo "[phone_music] 手机未连接" >&2; exit 1; }
        [ "$(adb -s "$s" get-state 2>/dev/null)" = "device" ] || { echo "[phone_music] 设备不可用: $s" >&2; exit 1; }
        cur=$(pid_of)
        if [ -n "$cur" ] && alive_cmd "$cur" scrcpy; then
            "$DEVICE" acquire phone phone_music 3600 "$cur" >/dev/null 2>&1 || {
                echo "[phone_music] 手机被占用" >&2; exit 1
            }
            "$STATE" set media.phone playing "$cur" "$s"
            echo "已在播放（音频转发 pid=$cur）"; exit 0
        fi
        adb -s "$s" shell "monkey -p $PKG -c android.intent.category.LAUNCHER 1" >/dev/null 2>&1 || true
        sleep 2
        adb -s "$s" shell 'cmd media_session volume --stream 3 --set 9' >/dev/null 2>&1 || true
        adb -s "$s" shell 'input keyevent 126' >/dev/null 2>&1 || true
        setsid nohup scrcpy -s "$s" --audio-source=playback --no-control \
            --window-borderless --always-on-top --window-width 405 --window-height 900 \
            --window-title=scrcpy-music >/tmp/myagent-phone-music.log 2>&1 </dev/null &
        pid=$!
        sleep 2
        if ! alive_cmd "$pid" scrcpy; then
            "$STATE" set media.phone stopped 0
            echo "[phone_music] scrcpy 启动失败" >&2; exit 1
        fi
        if ! "$DEVICE" acquire phone phone_music 3600 "$pid" >/dev/null 2>&1; then
            kill "$pid" 2>/dev/null || true
            echo "[phone_music] 手机被占用" >&2; exit 1
        fi
        "$STATE" set media.phone playing "$pid" "$s"
        "$ROOT/tools/lua.sh" "$ROOT/tools/winctl.lua" mirror-sync 2>/dev/null || true
        if [ -f "$FOLLOW_PIDFILE" ] && kill -0 "$(cat "$FOLLOW_PIDFILE")" 2>/dev/null; then
            kill "$(cat "$FOLLOW_PIDFILE")" 2>/dev/null || true
        fi
        setsid nohup "$ROOT/tools/lua.sh" "$ROOT/tools/winctl.lua" mirror-follow \
            >/tmp/myagent-music-follow.log 2>&1 </dev/null &
        echo $! > "$FOLLOW_PIDFILE"
        if [ "${CAM_BLOCK:-1}" != "0" ]; then
            ( "$ROOT/plugins/camera/camera_block.sh" start "$pid" >/dev/null 2>&1 ) &
        fi
        echo "汽水音乐播放中（音频 → USB 小音箱）"
        ;;
    pause|resume)
        s=$(serial); [ -n "$s" ] || { echo "[phone_music] 手机未连接" >&2; exit 1; }
        pid=$(pid_of)
        if [ -z "$pid" ] || ! alive_cmd "$pid" scrcpy; then
            echo "没有在播放"; exit 1
        fi
        if [ "$1" = "pause" ]; then
            adb -s "$s" shell input keyevent 127 >/dev/null 2>&1 || true
            "$STATE" set media.phone paused "$pid" "$s"
            echo "已暂停"
        else
            adb -s "$s" shell input keyevent 126 >/dev/null 2>&1 || true
            "$STATE" set media.phone playing "$pid" "$s"
            echo "已继续"
        fi
        ;;
    stop)
        if [ -f "$FOLLOW_PIDFILE" ] && kill -0 "$(cat "$FOLLOW_PIDFILE")" 2>/dev/null; then
            kill "$(cat "$FOLLOW_PIDFILE")" 2>/dev/null || true
        fi
        rm -f "$FOLLOW_PIDFILE"
        ( "$ROOT/plugins/camera/camera_block.sh" stop >/dev/null 2>&1 || true ) &
        pid=$(pid_of)
        if [ -n "$pid" ] && alive_cmd "$pid" scrcpy; then
            kill "$pid" 2>/dev/null || true
        fi
        [ -n "$pid" ] && "$DEVICE" release phone "$pid" >/dev/null 2>&1 || true
        "$STATE" set media.phone stopped 0
        rm -f /tmp/myagent_mirror.id
        s=$(serial)
        [ -n "$s" ] && adb -s "$s" shell 'input keyevent 127' >/dev/null 2>&1 || true
        echo "已停止"
        ;;
    status)
        pid=$(pid_of)
        if [ -n "$pid" ] && alive_cmd "$pid" scrcpy; then
            echo "播放中 pid=$pid"
        else echo "未播放"; fi
        ;;
    *) echo "用法: $0 play|pause|resume|stop|status" >&2; exit 2 ;;
esac
