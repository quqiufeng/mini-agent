#!/usr/bin/env bash
# @desc 录制 USB 麦克风到 WAV
# @usage tools/record_mic.sh [seconds] [out.wav]
# @rule 默认自动选 Comica 输入（排除 monitor）；用于 ASR/回环测试
set -euo pipefail

SECS="${1:-5}"
OUT="${2:-/tmp/myagent-mic-$(date +%s).wav}"
[[ "$SECS" =~ ^[1-9][0-9]*$ ]] || { echo "seconds 必须是正整数" >&2; exit 2; }
SRC="${MIC_SOURCE:-}"
if [ -z "$SRC" ]; then
  SRC="$(pactl list short sources 2>/dev/null | awk '/[Cc]omica|COMICA/ && $2 !~ /\.monitor$/ {print $2; exit}')"
fi
[ -n "$SRC" ] || SRC="@DEFAULT_SOURCE@"

timeout "$SECS" parecord --device="$SRC" --format=s16le --rate=16000 --channels=1 \
  --file-format=wav "$OUT" >/tmp/myagent-record.log 2>&1 || true

[ -s "$OUT" ] || {
  echo "[record] 录音失败" >&2
  cat /tmp/myagent-record.log >&2 || true
  exit 1
}
echo "$OUT"
