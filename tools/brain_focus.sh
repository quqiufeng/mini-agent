#!/usr/bin/env bash
# @desc 把大脑 TUI 窗口前置（LuaJIT FFI/libxdo，不用 xdotool 命令）
# @usage tools/brain_focus.sh
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
export DISPLAY="${DISPLAY:-:0}"
export XAUTHORITY="${XAUTHORITY:-/tmp/xauth_pLarOv}"
exec luajit "$DIR/winctl.lua" focus "BRAIN TUI"
