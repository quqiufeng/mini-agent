#!/usr/bin/env bash
# @desc 语音转文本：本地音频 scp 到远程，调用封装好的 listen.sh 识别
# @usage tools/asr.sh <本地音频文件>
# @rule 本机不做 ASR；远程用 ffmpeg 转 16k 单声道后交给 voice/listen.sh
set -euo pipefail

HOST="${REMOTE_HOST:-quqiufeng@192.168.1.10}"
[ $# -eq 1 ] || { echo "用法: $0 <本地音频文件>" >&2; exit 2; }
SRC="$1"
[ -f "$SRC" ] || { echo "[asr] 文件不存在: $SRC" >&2; exit 1; }
LANG="${ASR_LANG:-zh}"
[[ "$LANG" =~ ^[A-Za-z0-9_-]+$ ]] || { echo "非法 ASR_LANG: $LANG" >&2; exit 2; }
LANG_Q="$(printf '%q' "$LANG")"

BASE="myagent-asr-$(date +%s)-$$"
REMOTE_IN="/tmp/${BASE}.input"
REMOTE_WAV="/tmp/${BASE}.wav"
IN_Q="$(printf '%q' "$REMOTE_IN")"
WAV_Q="$(printf '%q' "$REMOTE_WAV")"

scp -q "$SRC" "$HOST:$REMOTE_IN"

CMD="ffmpeg -y -loglevel error -i $IN_Q -ar 16000 -ac 1 $WAV_Q"
CMD+=" && SENSEVOICE_LANG=$LANG_Q /opt/my-agent/voice/listen.sh --file $WAV_Q --no-forward"

set +e
OUT="$(ssh -o BatchMode=yes -o ConnectTimeout=10 "$HOST" "$CMD" 2>&1)"
STATUS=$?
set -e
ssh -o BatchMode=yes "$HOST" "rm -f $IN_Q $WAV_Q" >/dev/null 2>&1 || true

if [ "$STATUS" -ne 0 ]; then
  echo "[asr] 远程识别失败" >&2
  printf '%s\n' "$OUT" >&2
  exit "$STATUS"
fi

TEXT="$(printf '%s\n' "$OUT" | sed -n 's/^\[识别\][[:space:]]*//p' | tail -1)"
if [ -z "$TEXT" ]; then
  echo "[asr] 没有识别结果" >&2
  printf '%s\n' "$OUT" >&2
  exit 1
fi
printf '%s\n' "$TEXT"
