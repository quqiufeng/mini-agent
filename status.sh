#!/usr/bin/env bash
# status.sh — 查看本地 my-agent 大脑状态
set -uo pipefail

SESSION="${AGENT_SESSION:-local-my-agent}"
PORT="${AGENT_PORT:-4097}"

echo "== tmux =="
tmux ls 2>&1 || true
echo
echo "== windows =="
tmux list-windows -t "$SESSION" -F '#{window_index}: #{window_name} (#{pane_current_command})' 2>&1 || true
echo
echo "== health :$PORT =="
if curl --max-time 2 -sf "http://127.0.0.1:$PORT/global/health"; then
  echo
  echo "OK"
else
  echo "DOWN"
fi
