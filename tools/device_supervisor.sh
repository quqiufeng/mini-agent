#!/usr/bin/env bash
# @desc GUI 常驻设备监督：小音箱占用、摄像头遮挡、麦克风/网络设备状态统一探测
# @usage tools/device_supervisor.sh start [gui_pid] | stop | status
# @rule 单实例；由 gui/launch.sh 启动，GUI 退出后自动结束；摄像头遮挡沿用 camera_block 常驻检测
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIR="$ROOT/tools"
PIDFILE=/tmp/myagent-device-supervisor.pid
LOG=/tmp/myagent-device-supervisor.log
INTERVAL="${DEVICE_SUPERVISOR_INTERVAL:-5}"

running() { [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; }
gui_pid() { pgrep -f 'gui/sdl/myagent-voice$' | head -1; }

case "${1:-start}" in
    start)
        if running; then echo "already running pid=$(cat "$PIDFILE")"; exit 0; fi
        gui="${2:-$(gui_pid)}"
        setsid nohup "$0" _loop "$gui" >"$LOG" 2>&1 </dev/null &
        echo $! >"$PIDFILE"
        echo "started pid=$! gui=${gui:-none}"
        ;;
    stop)
        if running; then kill "$(cat "$PIDFILE")" 2>/dev/null || true; fi
        rm -f "$PIDFILE"
        "$ROOT/plugins/camera/camera_block.sh" stop >/dev/null 2>&1 || true
        echo stopped
        ;;
    status)
        if running; then echo "supervisor running pid=$(cat "$PIDFILE")"; else echo "supervisor stopped"; fi
        echo "speaker $(  "$DIR/speaker_watch.sh" status 2>/dev/null || echo stopped)"
        echo "camera  $(  "$ROOT/plugins/camera/camera_block.sh" status 2>/dev/null | head -1 || echo stopped)"
        echo "mic     $("$DIR/state.sh" get device.microphone 2>/dev/null || echo unknown)"
        ;;
    _loop)
        gui="${2:-}"
        cleanup() {
            "$ROOT/plugins/camera/camera_block.sh" stop >/dev/null 2>&1 || true
            rm -f "$PIDFILE"
        }
        trap cleanup EXIT TERM INT
        "$DIR/speaker_watch.sh" start >/dev/null 2>&1 || true
        "$ROOT/plugins/camera/camera_block.sh" resident >/dev/null 2>&1 || true
        last_maint=0
        while true; do
            if [ -n "$gui" ] && ! kill -0 "$gui" 2>/dev/null; then
                "$DIR/state.sh" set device.supervisor stopped 0 >/dev/null 2>&1 || true
                break
            fi
            "$DIR/state.sh" set device.supervisor running "$$" >/dev/null 2>&1 || true
            "$DIR/speaker_watch.sh" status 2>/dev/null | grep -q running || "$DIR/speaker_watch.sh" start >/dev/null 2>&1 || true
            "$DIR/device.sh" refresh >/dev/null 2>&1 || true
            "$DIR/device.sh" probe >/dev/null 2>&1 || true
            if ! "$ROOT/plugins/camera/camera_block.sh" status 2>/dev/null | grep -q running; then
                "$ROOT/plugins/camera/camera_block.sh" resident >/dev/null 2>&1 || true
            fi
            now=$(date +%s)
            if [ $((now - last_maint)) -ge 3600 ]; then
                last_maint=$now
                "$DIR/kv.sh" compact >/dev/null 2>&1 || true
            fi
            sleep "$INTERVAL"
        done
        ;;
    *)
        echo "用法: $0 start [gui_pid]|stop|status" >&2
        exit 2
        ;;
esac
