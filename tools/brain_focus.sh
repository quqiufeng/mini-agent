#!/usr/bin/env bash
# @desc 把大脑的 tmux TUI 窗口前置（按 tmux client → qterminal 进程 → X 窗口）
# @usage tools/brain_focus.sh
set -uo pipefail
SESSION="${AGENT_SESSION:-local-my-agent}"
export DISPLAY="${DISPLAY:-:0}"
export XAUTHORITY="${XAUTHORITY:-/tmp/xauth_pLarOv}"

pid=$(tmux display-message -p -t "$SESSION" '#{client_pid}' 2>/dev/null || true)
if [ -z "$pid" ]; then
  echo "[brain_focus] 找不到 tmux client（大脑没起？）" >&2
  exit 1
fi

# 沿父进程链找 qterminal
term_pid=""
cur="$pid"
for _ in $(seq 1 12); do
  comm=$(ps -o comm= -p "$cur" 2>/dev/null || true)
  case "$comm" in
    qterminal*) term_pid="$cur"; break ;;
  esac
  cur=$(ps -o ppid= -p "$cur" 2>/dev/null | tr -d ' ')
  [ -n "$cur" ] && [ "$cur" != "0" ] || break
done

wid=""
if [ -n "$term_pid" ]; then
  wid=$(xdotool search --pid "$term_pid" 2>/dev/null | tail -1 || true)
fi
if [ -z "$wid" ]; then
  wid=$(xdotool search --class qterminal 2>/dev/null | tail -1 || true)
fi
if [ -z "$wid" ]; then
  echo "[brain_focus] 没找到终端窗口" >&2
  exit 1
fi
xdotool windowactivate "$wid" 2>/dev/null || xdotool windowraise "$wid"
echo "已前置窗口 $wid（qterminal pid=${term_pid:-?}）"
