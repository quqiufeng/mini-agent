#!/usr/bin/env bash
# @desc 手机汽水音乐：启动 com.luna.music，声音经 scrcpy 转到本机 USB 小音箱
# @usage tools/phone_music.sh play | stop | status
# @rule 说“播放汽水音乐/手机放歌”→ tools/phone_music.sh play；不要走远程
set -uo pipefail
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
PIDFILE=/tmp/myagent-phone-music.pid
PKG=com.luna.music

serial() { adb devices | awk 'NR>1 && $2=="device" {print $1; exit}'; }

case "${1:-}" in
    play)
        s=$(serial); [ -n "$s" ] || { echo "[phone_music] 手机未连接" >&2; exit 1; }
        adb -s "$s" shell "monkey -p $PKG -c android.intent.category.LAUNCHER 1" >/dev/null 2>&1 || true
        sleep 2
        adb -s "$s" shell 'cmd media_session volume --stream 3 --set 20' >/dev/null 2>&1 || true
        adb -s "$s" shell 'input keyevent 126' >/dev/null 2>&1 || true
        if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
            echo "已在播放（音频转发 pid=$(cat "$PIDFILE")）"; exit 0
        fi
        # 视频窗口钉在 GUI 右侧预览区（真同步），音频仍走 USB 小音箱
        export DISPLAY="${DISPLAY:-:0}" XAUTHORITY="${XAUTHORITY:-/tmp/xauth_pLarOv}"
        gx=960; gy=0; gw=450; gh=900
        gwid=$(xdotool search --name 'My Agent' 2>/dev/null | tail -1 || true)
        if [ -n "$gwid" ]; then
            ax=$(xwininfo -id "$gwid" 2>/dev/null | awk -F: '/Absolute upper-left X/{gsub(/ /,"",$2);print $2}')
            ay=$(xwininfo -id "$gwid" 2>/dev/null | awk -F: '/Absolute upper-left Y/{gsub(/ /,"",$2);print $2}')
            [ -n "$ax" ] && [ -n "$ay" ] && { gx=$((ax + 480)); gy=$ay; }
        fi
        setsid nohup scrcpy -s "$s" --audio-source=output --no-control \
            --window-borderless --always-on-top \
            --window-x "$gx" --window-y "$gy" --window-width "$gw" --window-height "$gh" \
            >/tmp/myagent-phone-music.log 2>&1 &
        echo $! > "$PIDFILE"
        sleep 2
        echo "汽水音乐播放中（音频 → USB 小音箱）"
        ;;
    stop)
        if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
            kill "$(cat "$PIDFILE")" 2>/dev/null || true
            rm -f "$PIDFILE"
        fi
        s=$(serial)
        [ -n "$s" ] && adb -s "$s" shell 'input keyevent 127' >/dev/null 2>&1 || true
        echo "已停止"
        ;;
    status)
        if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
            echo "播放中 pid=$(cat "$PIDFILE")"
        else echo "未播放"; fi
        ;;
    *) echo "用法: $0 play|stop|status" >&2; exit 2 ;;
esac
