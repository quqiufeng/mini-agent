#!/usr/bin/env bash
# send.sh — 向本地 my-agent 大脑提交一条消息
#
# 用法:
#   ./send.sh "现在几点"
#   ./send.sh "播放夜曲"
#
# 依赖: python3 + requests
set -uo pipefail

PORT="${AGENT_PORT:-4097}"
if [ $# -eq 0 ]; then
  echo "用法: $0 \"文本\"" >&2
  exit 2
fi
TEXT="$*"

if ! curl --max-time 2 -sf "http://127.0.0.1:$PORT/global/health" >/dev/null; then
  echo "[send] 大脑未启动，先运行 ./start.sh" >&2
  exit 1
fi

python3 - "$PORT" "$TEXT" <<'PY'
import sys
import requests

port, text = sys.argv[1], sys.argv[2]
base = f"http://127.0.0.1:{port}"
r = requests.post(base + "/tui/append-prompt", json={"text": text}, timeout=10)
r.raise_for_status()
r = requests.post(base + "/tui/submit-prompt", json={}, timeout=10)
r.raise_for_status()
print("sent")
PY
