#!/usr/bin/env bash
# start.sh — 本地最小版 my-agent 大脑（LuaJIT FFI 打开终端并键入 tmux 命令）
#
# 结构:
#   qterminal（一个 tab）→ tmux session local-my-agent
#   ├─ window serve: opencode serve --port 4097
#   └─ window tui:   opencode attach http://127.0.0.1:4097
#
# tmux 窗口即标签；设了 destroy-unattached，关掉终端即销毁会话，不留后台。
# 大脑工作目录 operator/；server 用 operator/opencode.json 限制权限。
#
# 用法:
#   ./start.sh          # 打开终端并启动
#   AGENT_PORT=4098 ./start.sh
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$DIR/operator/ports.env" ]; then set -a; . "$DIR/operator/ports.env"; set +a; fi
export AGENT_WORKDIR="$DIR/operator"
exec "$DIR/tools/lua.sh" "$DIR/tools/start_gui.lua" "$@"
