#!/usr/bin/env bash
# send.sh — 向本地 my-agent 大脑提交一条消息（LuaJIT FFI，无 Python）
#
# 用法:
#   ./send.sh "现在几点"
#
# 依赖: curl（健康检查）、tools/lua.sh（内嵌 LuaJIT + libcurl）
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
PORT="${AGENT_PORT:-4097}"
if [ $# -eq 0 ]; then
    echo "用法: $0 \"文本\"" >&2
    exit 2
fi
TEXT="$*"

if ! curl --max-time 2 -sf "http://127.0.0.1:$PORT/global/health" >/dev/null; then
    echo "[send] 大脑未启动，先运行 ./start.sh" >&2
    exit 1
fi

AGENT_PORT="$PORT" "$DIR/tools/lua.sh" "$DIR/tools/send.lua" "$TEXT" || exit 1

# 标记本次是 GUI/语音发出的指令（时间 + 原文），只念这条指令的回复
TMPW="/tmp/myagent_speak_want.$$"
{ date +%s; printf '%s' "$TEXT"; } > "$TMPW" && mv "$TMPW" /tmp/myagent_speak_want
