#!/usr/bin/env bash
# @desc 本地 Chrome：打开网页 / headless 取 DOM / 截图 / 启动或停止 CDP
# @usage plugins/system/chrome.sh open <url> | dump <url> | shot <url> <out.png> | cdp [port] | stop [port]
# @rule 说“打开网页/打开 <网站>”→ plugins/system/chrome.sh open <url>；本地 Chrome 可访问外网；只允许 http/https；CDP 默认 9222
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

require_http() {
  case "$1" in
    http://*|https://*) ;;
    *) echo "只允许 http/https: $1" >&2; exit 2 ;;
  esac
}

case "$cmd" in
  open)
    [ $# -ge 1 ] || { echo "用法: $0 open <url>" >&2; exit 2; }
    require_http "$1"
    exec google-chrome --new-window "$1"
    ;;
  dump)
    [ $# -ge 1 ] || { echo "用法: $0 dump <url>" >&2; exit 2; }
    require_http "$1"
    exec google-chrome --headless=new --no-sandbox --disable-gpu --dump-dom "$1"
    ;;
  shot)
    [ $# -ge 2 ] || { echo "用法: $0 shot <url> <out.png>" >&2; exit 2; }
    require_http "$1"
    exec google-chrome --headless=new --no-sandbox --disable-gpu --screenshot="$2" "$1"
    ;;
  cdp)
    PORT="${1:-${CDP_PORT:-9222}}"
    [[ "$PORT" =~ ^[0-9]+$ ]] || { echo "非法端口: $PORT" >&2; exit 2; }
    PROFILE="${CDP_PROFILE:-$HOME/.chrome-debug}"
    exec google-chrome --remote-debugging-port="$PORT" \
      --remote-allow-origins='*' \
      --user-data-dir="$PROFILE" \
      --no-first-run --no-default-browser-check \
      --new-window about:blank
    ;;
  stop)
    PORT="${1:-${CDP_PORT:-9222}}"
    [[ "$PORT" =~ ^[0-9]+$ ]] || { echo "非法端口: $PORT" >&2; exit 2; }
    fuser -k "$PORT/tcp" 2>/dev/null || true
    echo "stopped CDP on :$PORT"
    ;;
  *)
    echo "用法: $0 open <url> | dump <url> | shot <url> <out.png> | cdp [port] | stop [port]" >&2
    exit 2
    ;;
esac
