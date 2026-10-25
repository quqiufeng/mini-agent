#!/usr/bin/env bash
# gui/launch.sh — 桌面图标入口：小窗口启动语音控制台（Terminal=false）
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DISPLAY="${DISPLAY:-:0}"
cd "$ROOT"
exec "$ROOT/gui/sdl/myagent-voice" "$@"
