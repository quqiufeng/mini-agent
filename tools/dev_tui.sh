#!/usr/bin/env bash
# @desc 开发者模式：优先复用已有 TUI 窗口；没有才新建（tmux dev-tui + DEV TUI 窗口）
# @usage tools/dev_tui.sh start | type "<文本>" | stop | status
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SESSION=dev-tui
export DISPLAY="${DISPLAY:-:0}"
export XAUTHORITY="${XAUTHORITY:-/tmp/xauth_pLarOv}"

has() { tmux has-session -t "$SESSION" 2>/dev/null; }

# 查找可复用的 TUI 窗口：DEV TUI，或任意 "OC |" 窗口（排除 BRAIN TUI）
find_tui_win() {
    "$ROOT/tools/lua.sh" -e '
      package.path="'"$ROOT"'/tools/?.lua;"..package.path
      local Xdo=require("xdo"); local d=assert(Xdo.new())
      for _,w in ipairs(d:windows()) do
        local n=w.name or ""
        if n:find("DEV TUI",1,true) then print(tonumber(w.id)) return end
      end'
}

paste_win() {
    local wid="$1" text="$2"
    printf '%s' "$text" | xclip -selection clipboard >/dev/null 2>&1
    sleep 0.2
    "$ROOT/tools/lua.sh" -e '
      package.path="'"$ROOT"'/tools/?.lua;"..package.path
      local Xdo=require("xdo"); local d=assert(Xdo.new())
      local w=tonumber(arg[1]); if not w then os.exit(1) end
      d:activate(w); os.execute("sleep 0.2")
      d:key(w,"ctrl+shift+v"); os.execute("sleep 0.2"); d:key(w,"Return")' "$wid"
}

activate_win() {
    local wid="$1"
    [ -n "$wid" ] || return 0
    if command -v xdotool >/dev/null 2>&1 && \
       xdotool windowactivate "$wid" windowraise "$wid" >/dev/null 2>&1; then
        return 0
    fi
    "$ROOT/tools/lua.sh" -e '
      package.path="'"$ROOT"'/tools/?.lua;"..package.path
      local Xdo=require("xdo"); local d=assert(Xdo.new())
      local w=tonumber(arg[1]); if not w then os.exit(1) end
      d:show(w); d:activate(w)' "$wid"
}

resize_win() {
    local wid="$1"
    [ -n "$wid" ] || return 0
    DISPLAY="${DISPLAY:-:0}" "$ROOT/tools/win_resize.sh" "$wid" 1000 650 460 200 >/dev/null 2>&1 || true
}

start() {
    if has; then
        if [ -z "$(tmux list-clients -t "$SESSION" 2>/dev/null)" ]; then
            env -u TMUX setsid qterminal --workdir "$ROOT" -e "tmux attach -t $SESSION" >/dev/null 2>&1 &
            sleep 2
        fi
    else
        local wid; wid=$(find_tui_win)
        if [ -n "$wid" ]; then
            echo "复用已有 TUI 窗口 $wid"
            resize_win "$wid"
            activate_win "$wid"
            return 0
        fi
        tmux new-session -d -s "$SESSION" -c "$ROOT" \
            "env -u OPENCODE -u OPENCODE_PID -u OPENCODE_SERVER opencode"
        tmux set-option -t "$SESSION" set-titles on
        tmux set-option -t "$SESSION" set-titles-string "DEV TUI"
        env -u TMUX setsid qterminal --workdir "$ROOT" -e "tmux attach -t $SESSION" >/dev/null 2>&1 &
        sleep 2
    fi
    local wid2; wid2=$(find_tui_win)
    resize_win "$wid2"
    activate_win "$wid2"
    for _ in $(seq 1 20); do
        tmux capture-pane -p -t "$SESSION" 2>/dev/null | grep -q . && break
        sleep 0.3
    done
    sleep 1
}

case "${1:-}" in
    start) start ;;
    type)
        t="${2:-}"; [ -n "$t" ] || exit 2
        if has; then
            start
            tmux send-keys -t "$SESSION" -l "$t"; sleep 0.2; tmux send-keys -t "$SESSION" Enter
        else
            wid=$(find_tui_win)
            if [ -z "$wid" ]; then
                start
                wid=$(find_tui_win)
            fi
            [ -n "$wid" ] || { echo "[dev_tui] 没有可用 TUI" >&2; exit 1; }
            paste_win "$wid" "$t"
        fi
        echo "已输入 dev TUI: $t"
        ;;
    stop)
        tmux kill-session -t "$SESSION" 2>/dev/null || true
        echo "已关闭 dev TUI"
        ;;
    status)
        if has; then echo "dev TUI 运行中（tmux）"; else
            wid=$(find_tui_win); [ -n "$wid" ] && echo "复用窗口 $wid" || echo "dev TUI 未运行"
        fi
        ;;
    *) echo "用法: $0 start|type <文本>|stop|status" >&2; exit 2 ;;
esac
