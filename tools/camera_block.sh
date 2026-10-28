#!/usr/bin/env bash
# @desc 摄像头被遮挡 → 暂停音乐（本机 OpenCV 直连 TP-Link）
# @usage tools/camera_block.sh start <media_pid> | stop | status
# @rule 只做遮挡判定；播放时自动启动，触发暂停后退出；播放结束也退出
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
BIN="$DIR/camera_block"
PIDFILE=/tmp/myagent-camera-block.pid
LOG=/tmp/myagent-camera-block.log

running() { [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; }

case "${1:-}" in
    start)
        pid="${2:-}"
        [[ "$pid" =~ ^[0-9]+$ ]] || { echo "用法: $0 start <media_pid>" >&2; exit 2; }
        [ -x "$BIN" ] || { echo "[camera_block] 未编译: $BIN" >&2; exit 1; }
        [ -r "$HOME/.env" ] || { echo "[camera_block] 缺少 ~/.env" >&2; exit 1; }
        set -a
        . "$HOME/.env"
        set +a
        [ -n "${TPLINK_RTSP:-}" ] || { echo "[camera_block] 缺少 TPLINK_RTSP" >&2; exit 1; }
        if running; then
            kill "$(cat "$PIDFILE")" 2>/dev/null || true
            sleep 0.2
        fi
        echo "=== start $(date +%s) media_pid=$pid ===" >>"$LOG"
        setsid nohup "$BIN" --watch "$pid" >>"$LOG" 2>&1 </dev/null &
        echo $! > "$PIDFILE"
        echo "started pid=$! media_pid=$pid"
        ;;
    stop)
        if running; then
            kill "$(cat "$PIDFILE")" 2>/dev/null || true
            echo "stopped"
        else
            echo "not-running"
        fi
        rm -f "$PIDFILE"
        ;;
    status)
        if running; then
            echo "running pid=$(cat "$PIDFILE")"
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
