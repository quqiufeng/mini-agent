#!/usr/bin/env bash
# start.sh — 本地最小版 my-agent 大脑（tmux + opencode）
#
# 结构:
#   tmux session: local-my-agent
#   ├─ window "serve": opencode serve --port 4097   # 真正的 server/大脑
#   └─ window "tui":   opencode attach http://127.0.0.1:4097
#
# opencode 的工作目录固定为本目录（~/my-agent），自动读取 ~/my-agent/AGENTS.md。
#
# 用法:
#   ./start.sh          # 启动后 attach
#   ./start.sh --bg     # 只后台启动
#   AGENT_PORT=4098 ./start.sh
#   AGENT_SESSION=my-brain ./start.sh
set -uo pipefail

SESSION="${AGENT_SESSION:-local-my-agent}"
PORT="${AGENT_PORT:-4097}"
WORKDIR="$(cd "$(dirname "$0")" && pwd)"

health() {
  curl --max-time 2 -sf "http://127.0.0.1:$PORT/global/health" >/dev/null 2>&1
}

has_window() {
  tmux list-windows -t "$SESSION" -F '#{window_name}' 2>/dev/null | grep -qx "$1"
}

port_in_use() {
  ss -ltn 2>/dev/null | awk '{print $4}' | grep -q ":$PORT$"
}

ensure_tui() {
  if has_window tui && pgrep -f "opencode[ ]attach http://127.0.0.1:$PORT" >/dev/null 2>&1; then
    return 0
  fi
  tmux kill-window -t "$SESSION:tui" 2>/dev/null || true
  tmux new-window -d -t "$SESSION" -n tui -c "$WORKDIR" \
    "opencode attach http://127.0.0.1:$PORT; echo; echo '[tui 已退出] 按回车'; read _"
  for _ in $(seq 1 15); do
    if pgrep -f "opencode[ ]attach http://127.0.0.1:$PORT" >/dev/null 2>&1; then
      sleep 2
      return 0
    fi
    sleep 1
  done
  return 1
}

if tmux has-session -t "$SESSION" 2>/dev/null; then
  if health; then
    ensure_tui || { echo "[start] TUI 启动超时" >&2; exit 1; }
    echo "已在运行: tmux attach -t $SESSION"
  else
    echo "[start] 会话 $SESSION 存在，但 :$PORT 不健康；先运行 stop.sh" >&2
    exit 1
  fi
else
  if health || port_in_use; then
    echo "[start] 端口 $PORT 已被占用，且不是 tmux session $SESSION" >&2
    exit 1
  fi
  tmux new-session -d -s "$SESSION" -n serve -c "$WORKDIR" \
    "opencode serve --port $PORT"
  for _ in $(seq 1 30); do
    health && break
    sleep 1
  done
  if ! health; then
    echo "[start] opencode serve 启动失败（端口 $PORT）" >&2
    exit 1
  fi
  ensure_tui || { echo "[start] TUI 启动超时" >&2; exit 1; }
  echo "已启动: tmux attach -t $SESSION"
fi

if [ "${1:-}" != "--bg" ]; then
  exec tmux attach -t "$SESSION"
fi
