#!/usr/bin/env bash
# @desc 小音箱常驻状态监视：USB 音箱 sink 在出声就写 busy，空闲写 idle，语音入口据此暂停/恢复监听
# @usage tools/speaker_watch.sh start|stop|status|restart
DIR="$(cd "$(dirname "$0")" && pwd)"
# @rule 单实例常驻（PulseAudio/PipeWire 常驻进程维持正确判断）；所有走小音箱的声音（VLC/手机/TTS/闹钟）都算占用
set -uo pipefail
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
SINK="${SPEAKER_SINK:-alsa_output.usb-DUNU_DTC_480_DTC_480-00.analog-stereo}"
STATE="${SPEAKER_STATE:-/tmp/myagent_speaker.state}"
PIDFILE=/tmp/myagent-speaker-watch.pid
INTERVAL="${SPEAKER_POLL:-0.3}"

running() { [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; }

write_state() {
    "$DIR/state.sh" set speaker "$1" 2>/dev/null || true
}

case "${1:-start}" in
    start)
        if running; then echo "已在运行 pid=$(cat "$PIDFILE")"; exit 0; fi
        write_state idle
        setsid nohup "$0" _loop >/tmp/myagent-speaker-watch.log 2>&1 </dev/null &
        echo $! > "$PIDFILE"
        echo "started pid=$! sink=$SINK"
        ;;
    stop)
        if running; then kill "$(cat "$PIDFILE")" 2>/dev/null || true; fi
        rm -f "$PIDFILE" "$STATE"
        echo "stopped"
        ;;
    restart)
        "$0" stop >/dev/null
        exec "$0" start
        ;;
    status)
        if running; then
            echo "running pid=$(cat "$PIDFILE") $("$DIR/state.sh" get speaker 2>/dev/null || echo "no-state")"
        else
            echo "stopped"
        fi
        ;;
    _loop)
        THRESH="${SPEAKER_RMS:-80}"
        PEAK_TH="${SPEAKER_PEAK:-800}"
        HOLD_MS="${SPEAKER_HOLD_MS:-800}"
        last_busy=$(date +%s%N)
        cleanup() { pkill -TERM -P $$ 2>/dev/null || true; rm -f "$STATE"; }
        trap cleanup EXIT TERM INT
        parec --device="$SINK.monitor" --format=s16le --rate=16000 --channels=1 \
            --client-name=myagent-level 2>/dev/null | "$DIR/audio_level" | while read -r rms peak; do
            now=$(date +%s%N)
            busy=0
            if [ "${rms:-0}" -gt "$THRESH" ] || [ "${peak:-0}" -gt "$PEAK_TH" ]; then
                last_busy=$now; busy=1
            fi
            if [ "$busy" = 1 ] || [ $(( (now - last_busy) / 1000000 )) -lt "$HOLD_MS" ]; then
                write_state busy
            else
                write_state idle
            fi
        done
        ;;
    *)
        echo "用法: $0 start|stop|status|restart" >&2
        exit 2
        ;;
esac
