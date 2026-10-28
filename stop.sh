#!/usr/bin/env bash
# stop.sh — 停止本地 my-agent 大脑（tmux）
set -uo pipefail
SESSION="${AGENT_SESSION:-local-my-agent}"
PORT="${AGENT_PORT:-4097}"
if tmux has-session -t "$SESSION" 2>/dev/null; then
  tmux kill-session -t "$SESSION"
  echo "已停止 tmux: $SESSION"
fi
pkill -f "opencode attach http://127.0.0.1:$PORT" 2>/dev/null && echo "已停止 TUI"
pkill -f "opencode serve --port $PORT" 2>/dev/null && echo "已停止 serve"
pkill -f "speak_watch.lua" 2>/dev/null && echo "已停止语音回复"
echo "完成"
