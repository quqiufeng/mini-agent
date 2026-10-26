#!/usr/bin/env bash
# gui/launch.sh — 桌面图标入口：单实例启动语音控制台（Terminal=false）
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DISPLAY="${DISPLAY:-:0}"
export XAUTHORITY="${XAUTHORITY:-/tmp/xauth_pLarOv}"
cd "$ROOT"
if pgrep -x myagent-voice >/dev/null 2>&1; then
    xdotool search --name 'My Agent' windowactivate >/dev/null 2>&1 || true
    exit 0
fi
exec "$ROOT/gui/sdl/myagent-voice" "$@"
