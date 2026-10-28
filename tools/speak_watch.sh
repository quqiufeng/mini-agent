#!/usr/bin/env bash
# @desc 监听本地大脑会话并朗读回复（LuaJIT FFI 薄入口）
# @usage tools/speak_watch.sh
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/lua.sh" "$DIR/speak_watch.lua" "$@"
