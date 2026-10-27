#!/usr/bin/env bash
# @desc 运行 Lua 脚本：优先用内嵌 LuaJIT 的 myagent-voice，没有则退回系统 luajit
# @usage tools/lua.sh <script.lua | -e code> [args...]
# @rule 构建 gui/sdl/myagent-voice 后，本机脚本不再依赖系统 luajit 命令
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
export LD_LIBRARY_PATH="$DIR/../gui/lib:${LD_LIBRARY_PATH:-}"
BIN="$DIR/../gui/sdl/myagent-voice"
if [ -x "$BIN" ]; then
    exec "$BIN" --lua "$@"
fi
exec luajit "$@"
