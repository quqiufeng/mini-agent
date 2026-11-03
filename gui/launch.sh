#!/usr/bin/env bash
# gui/launch.sh — 桌面图标入口：单实例启动语音控制台（Terminal=false）
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export LD_LIBRARY_PATH="$ROOT/gui/lib:${LD_LIBRARY_PATH:-}"
export DISPLAY="${DISPLAY:-:0}"
export XAUTHORITY="${XAUTHORITY:-/tmp/xauth_pLarOv}"
cd "$ROOT"
if pgrep -f 'gui/sdl/myagent-voice$' >/dev/null 2>&1; then
    xdotool search --name 'ai助手' windowactivate >/dev/null 2>&1 || true
    setsid --fork "$ROOT/plugins/voice/speak_watch.sh" >>/tmp/myagent-speak-watch.log 2>&1 </dev/null
    "$ROOT/tools/speaker_watch.sh" start >/dev/null 2>&1
    gpid=$(pgrep -f 'gui/sdl/myagent-voice$' | head -1)
    "$ROOT/tools/device_supervisor.sh" start "$gpid" >/dev/null 2>&1 || true
    exit 0
fi
setsid --fork "$ROOT/plugins/voice/speak_watch.sh" >>/tmp/myagent-speak-watch.log 2>&1 </dev/null
"$ROOT/tools/speaker_watch.sh" start >/dev/null 2>&1
"$ROOT/tools/device_supervisor.sh" start "$$" >/dev/null 2>&1 || true
exec "$ROOT/gui/sdl/myagent-voice" "$@"
