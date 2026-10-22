#!/usr/bin/env bash
# stop.sh — 停止本地 my-agent 大脑
set -uo pipefail

SESSION="${AGENT_SESSION:-local-my-agent}"

if tmux has-session -t "$SESSION" 2>/dev/null; then
  tmux kill-session -t "$SESSION"
  echo "已停止: $SESSION"
else
  echo "未运行: $SESSION"
fi
