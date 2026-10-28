#!/usr/bin/env bash
# @desc 本地 Google 搜索：用本机 Chrome CDP 打开 Google，提取结果正文和外部链接
# @usage tools/google_search.sh "关键词" [count]
# @rule 本地优先；headless 会被 Google 拦，必须用 headful Chrome CDP
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
[ $# -ge 1 ] || { echo "用法: $0 \"关键词\" [count]" >&2; exit 2; }
QUERY="$1"
COUNT="${2:-10}"
PORT="${CDP_PORT:-9222}"

if ! curl -sf "http://127.0.0.1:$PORT/json/version" >/dev/null 2>&1; then
  echo "[google] 启动本地 Chrome CDP..." >&2
  setsid nohup "$DIR/chrome.sh" cdp "$PORT" >/tmp/myagent-google-chrome.log 2>&1 &
  for _ in $(seq 1 20); do
    curl -sf "http://127.0.0.1:$PORT/json/version" >/dev/null 2>&1 && break
    sleep 0.5
  done
fi

if ! curl -sf "http://127.0.0.1:$PORT/json/version" >/dev/null 2>&1; then
  echo "[google] Chrome CDP 启动失败" >&2
  exit 1
fi

set +e
"$DIR/lua.sh" "$DIR/google_search.lua" "$QUERY" "$COUNT" "$PORT"
RC=$?
set -e
if [ "$RC" -eq 3 ]; then
  echo "[google] Google 不可用/被拦截，回退 DeepSeek 搜索" >&2
  exec "$DIR/deepseek_search.sh" "$QUERY" "$COUNT"
fi
exit "$RC"
