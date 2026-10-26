#!/usr/bin/env bash
# @desc 文本转语音：远程合成 WAV，scp 回本机，用默认输出（USB 小音箱）播放
# @usage tools/tts.sh "文本"
# @rule 本机不做 TTS；远程 say.sh 合成（TTS_OUT），本地 paplay 到默认 sink
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
HOST="${REMOTE_HOST:-quqiufeng@192.168.1.10}"
OUT="${TTS_LOCAL_OUT:-/tmp/myagent-tts.wav}"
REMOTE_OUT="/tmp/myagent-tts-$$.wav"

[ $# -ge 1 ] || { echo "用法: $0 \"文本\"" >&2; exit 2; }
TEXT="$*"

if ! "$DIR/remote.sh" --env "TTS_OUT=$REMOTE_OUT" --env "SAY_NOPLAY=1" say "$TEXT" \
    >/tmp/myagent-tts.log 2>&1; then
  echo "[tts] 远程合成失败" >&2
  tail -20 /tmp/myagent-tts.log >&2 || true
  exit 1
fi

if ! scp -q "$HOST:$REMOTE_OUT" "$OUT"; then
  echo "[tts] 拉取 WAV 失败" >&2
  exit 1
fi
ssh -o BatchMode=yes "$HOST" "rm -f $REMOTE_OUT" >/dev/null 2>&1 || true

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
if [ "${TTS_NOPLAY:-0}" = "1" ]; then
  echo "$OUT"
  exit 0
fi
if command -v paplay >/dev/null 2>&1; then
  paplay "$OUT"
elif command -v pw-play >/dev/null 2>&1; then
  pw-play "$OUT"
else
  echo "[tts] 没有 paplay/pw-play" >&2
  exit 1
fi
echo "$OUT"
