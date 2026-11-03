#!/usr/bin/env bash
# @desc 摄像头被遮挡 → 暂停音乐（本机 OpenCV 直连 TP-Link）
# @usage plugins/camera/camera_block.sh start <media_pid> | stop | status
# @rule 摄像头归属走 device.sh 的 camera lease；触发暂停走 devctl.sh pause
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/../.." && pwd)"
BIN="$DIR/camera_block"
LOG=/tmp/myagent-camera-block.log
STATE="$ROOT/tools/state.sh"
DEVICE="$ROOT/tools/device.sh"

lease_pid() { "$DEVICE" lease camera 2>/dev/null | awk '{print $1}'; }
running() { p=$(lease_pid); [ -n "$p" ] && [ "$p" -gt 1 ] 2>/dev/null && kill -0 "$p" 2>/dev/null; }

case "${1:-}" in
    start)
        pid="${2:-}"
        [[ "$pid" =~ ^[0-9]+$ ]] || { echo "用法: $0 start <media_pid>" >&2; exit 2; }
        [ -x "$BIN" ] || { echo "[camera_block] 未编译: $BIN" >&2; exit 1; }
        [ -r "$HOME/.env" ] || { echo "[camera_block] 缺少 ~/.env" >&2; exit 1; }
        set -a; . "$HOME/.env"; set +a
        [ -n "${TPLINK_RTSP:-}" ] || { echo "[camera_block] 缺少 TPLINK_RTSP" >&2; exit 1; }
        p=$(lease_pid)
        if [ -n "$p" ] && [ "$p" -gt 1 ] 2>/dev/null && kill -0 "$p" 2>/dev/null; then
            kill "$p" 2>/dev/null || true; sleep 0.2
        fi
        "$DEVICE" release camera >/dev/null 2>&1 || true
        echo "=== start $(date +%s) media_pid=$pid ===" >>"$LOG"
        setsid nohup "$BIN" --watch "$pid" >>"$LOG" 2>&1 </dev/null &
        wpid=$!
        if ! "$DEVICE" acquire camera camera_block 3600 "$wpid" >/dev/null 2>&1; then
            kill "$wpid" 2>/dev/null || true
            echo "[camera_block] 摄像头被占用" >&2; exit 1
        fi
        echo "started pid=$wpid media_pid=$pid"
        ;;
    stop)
        p=$(lease_pid)
        if [ -n "$p" ] && [ "$p" -gt 1 ] 2>/dev/null && kill -0 "$p" 2>/dev/null; then
            kill "$p" 2>/dev/null || true
            echo "stopped"
        else
            echo "not-running"
        fi
        "$DEVICE" release camera >/dev/null 2>&1 || true
        "$STATE" set camera clear 0 >/dev/null 2>&1 || true
        ;;
    status)
        p=$(lease_pid)
        if [ -n "$p" ] && [ "$p" -gt 1 ] 2>/dev/null && kill -0 "$p" 2>/dev/null; then
            echo "running pid=$p"
            [ -s "$LOG" ] && tail -3 "$LOG"
        else
            echo "stopped"
        fi
        ;;
    *)
        echo "用法: $0 start <media_pid> | stop | status" >&2
        exit 2
        ;;
esac
