#!/usr/bin/env bash
# @desc 电视直连 NAS 播放：本机只拼直链 + adb 唤起 VLC（LuaJIT FFI，无 Python）
# @usage tv_play.sh <关键词> | <NAS相对路径> | --find <关键词> | stop
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/../.." && pwd)"
exec "$ROOT/tools/lua.sh" "$DIR/tv_play.lua" "$@"
