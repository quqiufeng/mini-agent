#!/usr/bin/env bash
# @desc 开发者模式：把文本直接粘贴进大脑 TUI 输入框并回车（绕过语音转发/工具规则）
# @usage tools/tui_type.sh "<文本>"
set -uo pipefail
SESSION="${AGENT_SESSION:-local-my-agent}"
export DISPLAY="${DISPLAY:-:0}"
export XAUTHORITY="${XAUTHORITY:-/tmp/xauth_pLarOv}"
TEXT="${1:-}"
[ -n "$TEXT" ] || { echo "用法: $0 \"<文本>\"" >&2; exit 2; }

pid=$(tmux display-message -p -t "$SESSION" '#{client_pid}' 2>/dev/null || true)
[ -n "$pid" ] || { echo "[tui_type] 大脑 TUI 没在运行" >&2; exit 1; }

term_pid=""
cur="$pid"
for _ in $(seq 1 12); do
    comm=$(ps -o comm= -p "$cur" 2>/dev/null || true)
    case "$comm" in qterminal*) term_pid="$cur"; break ;; esac
    cur=$(ps -o ppid= -p "$cur" 2>/dev/null | tr -d ' ')
    [ -n "$cur" ] && [ "$cur" != "0" ] || break
done

wid=""
[ -n "$term_pid" ] && wid=$(xdotool search --pid "$term_pid" 2>/dev/null | tail -1 || true)
[ -n "$wid" ] || wid=$(xdotool search --name 'local-my-agent' 2>/dev/null | tail -1 || true)
[ -n "$wid" ] || { echo "[tui_type] 找不到大脑终端窗口" >&2; exit 1; }

xdotool windowactivate "$wid" 2>/dev/null || true
sleep 0.3
printf '%s' "$TEXT" | xclip -selection clipboard
sleep 0.2
xdotool key --clearmodifiers --window "$wid" ctrl+shift+v
sleep 0.3
xdotool key --clearmodifiers --window "$wid" Return
echo "已输入 TUI: $TEXT"
