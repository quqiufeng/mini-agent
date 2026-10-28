#!/usr/bin/env bash
# send.sh — 向本地 my-agent 大脑提交一条消息
#
# 用法:
#   ./send.sh "现在几点"
#   ./send.sh "播放夜曲"
#   SPEAK_REPLY=1 ./send.sh "现在几点"   # 同时抓大脑短回复并用本地 TTS 朗读
#
# 依赖: python3 + requests
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
PORT="${AGENT_PORT:-4097}"
if [ $# -eq 0 ]; then
  echo "用法: $0 \"文本\"" >&2
  exit 2
fi
TEXT="$*"
START_MS="$(python3 -c 'import time; print(int(time.time()*1000))')"

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

# 语音回复由 tools/speak_watch.py 统一处理；标记本次是 GUI/语音发出的指令，只念它的回复
date +%s > /tmp/myagent_speak_want
