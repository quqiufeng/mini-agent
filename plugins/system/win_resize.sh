#!/usr/bin/env bash
# @desc 取消窗口最大化并调整大小/位置（LuaJIT + Xlib FFI 薄入口）
# @usage plugins/system/win_resize.sh <window_id> <width> <height> [x] [y]
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/../.." && pwd)"
exec "$ROOT/tools/lua.sh" "$DIR/win_resize.lua" "$@"
