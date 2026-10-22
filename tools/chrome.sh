#!/usr/bin/env bash
# @desc 本地 Chrome：打开网页 / headless 取 DOM / 截图 / 启动 CDP
# @usage tools/chrome.sh open <url> | dump <url> | shot <url> <out.png> | cdp [port]
# @rule 本地优先用 Chrome；需要远程登录态/专用 Chrome MCP 时再走远程
set -euo pipefail

export DISPLAY="${DISPLAY:-:0}"
if [ -z "${XAUTHORITY:-}" ]; then
  for p in $(pgrep -u "$USER" -f 'lxqt-session|openbox' 2>/dev/null); do
    XA="$(tr '\0' '\n' < "/proc/$p/environ" 2>/dev/null | sed -n 's/^XAUTHORITY=//p' | head -1)"
    if [ -n "$XA" ]; then
      export XAUTHORITY="$XA"
      break
    fi
  done
fi

cmd="${1:-}"
shift || true

case "$cmd" in
  open)
    [ $# -ge 1 ] || { echo "用法: $0 open <url>" >&2; exit 2; }
    exec google-chrome --new-window "$1"
    ;;
  dump)
    [ $# -ge 1 ] || { echo "用法: $0 dump <url>" >&2; exit 2; }
    exec google-chrome --headless=new --no-sandbox --disable-gpu --dump-dom "$1"
    ;;
  shot)
    [ $# -ge 2 ] || { echo "用法: $0 shot <url> <out.png>" >&2; exit 2; }
    exec google-chrome --headless=new --no-sandbox --disable-gpu --screenshot="$2" "$1"
    ;;
  cdp)
    PORT="${1:-9222}"
    exec google-chrome --remote-debugging-port="$PORT" \
      --user-data-dir="$HOME/.chrome-debug" \
      --no-first-run --no-default-browser-check \
      --new-window about:blank
    ;;
  *)
    echo "用法: $0 open <url> | dump <url> | shot <url> <out.png> | cdp [port]" >&2
    exit 2
    ;;
esac
