#!/usr/bin/env bash
# @desc 语音转文本：本机 SenseVoice.cpp 优先，失败再回退远程 SenseVoice.cpp
# @usage plugins/voice/asr.sh <本地音频文件>
# @rule 本机有 /opt/SenseVoice.cpp/bin/sense-voice-main + 模型时完全本地；任意采样率/24bit 先用 ffmpeg 转 16k 单声道
set -euo pipefail

[ $# -eq 1 ] || { echo "用法: $0 <本地音频文件>" >&2; exit 2; }
SRC="$1"
[ -f "$SRC" ] || { echo "[asr] 文件不存在: $SRC" >&2; exit 1; }
LANG="${ASR_LANG:-zh}"
[[ "$LANG" =~ ^[A-Za-z0-9_-]+$ ]] || { echo "非法 ASR_LANG: $LANG" >&2; exit 2; }

SV_BIN="${SENSEVOICE_BIN:-/opt/SenseVoice.cpp/bin/sense-voice-main}"
SV_MODEL="${SENSEVOICE_MODEL:-/opt/SenseVoice.cpp/models/sense-voice-small-q4_k.gguf}"
SV_LIB="${SENSEVOICE_LIB:-/opt/SenseVoice.cpp/lib}"
SV_THREADS="${SENSEVOICE_THREADS:-4}"
SV_DIR="${SENSEVOICE_DIR:-/opt/SenseVoice.cpp}"

# ── 本地优先 ────────────────────────────────────────────────
if [ "${ASR_LOCAL:-1}" != "0" ] && [ -x "$SV_BIN" ] && [ -r "$SV_MODEL" ]; then
    TMP16="$(mktemp /tmp/myagent-asr16-XXXXXX.wav)"
    if ffmpeg -nostdin -loglevel error -y -i "$SRC" -ac 1 -ar 16000 -sample_fmt s16 "$TMP16" >/dev/null 2>&1; then
        set +e
        RAW="$(cd "$SV_DIR" 2>/dev/null && LD_LIBRARY_PATH="$SV_LIB:${LD_LIBRARY_PATH:-}" timeout 30 \
            "$SV_BIN" -m "$SV_MODEL" -t "$SV_THREADS" -l "$LANG" -ng "$TMP16" 2>/tmp/myagent-asr.log)"
        RC=$?
        set -e
        TEXT="$(printf '%s\n' "$RAW" \
            | sed -n 's/^\[[0-9.]*-[0-9.]*\][[:space:]]*//p' \
            | sed 's/<|[^|]*|>//g' \
            | tr '\n' ' ' \
            | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/[[:space:]][[:space:]]*/ /g')"
        rm -f "$TMP16"
        if [ "$RC" -eq 0 ] && [ -n "$TEXT" ]; then
            printf '%s\n' "$TEXT"
            exit 0
        fi
        echo "[asr] 本地识别失败，回退远程" >&2
        [ -s /tmp/myagent-asr.log ] && tail -3 /tmp/myagent-asr.log >&2 || true
    else
        rm -f "$TMP16"
    fi
fi

# ── 远程回退 ────────────────────────────────────────────────
HOST="${REMOTE_HOST:-quqiufeng@192.168.1.10}"
LANG_Q="$(printf '%q' "$LANG")"

BASE="myagent-asr-$(date +%s)-$$"
REMOTE_IN="/tmp/${BASE}.input"
REMOTE_WAV="/tmp/${BASE}.wav"
IN_Q="$(printf '%q' "$REMOTE_IN")"
WAV_Q="$(printf '%q' "$REMOTE_WAV")"

scp -q "$SRC" "$HOST:$REMOTE_IN"

CMD="ffmpeg -y -loglevel error -i $IN_Q -ar 16000 -ac 1 $WAV_Q"
CMD+=" && /opt/SenseVoice.cpp/bin/sense-voice-main"
CMD+=" -m ${REMOTE_SENSEVOICE_MODEL:-/data/models/sense-voice-small-q4_k.gguf}"
CMD+=" -t 4 -l $LANG_Q -f $WAV_Q"

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

TEXT="$(printf '%s\n' "$OUT" \
  | sed -n 's/^\[[0-9.]*-[0-9.]*\][[:space:]]*//p' \
  | sed 's/<|[^|]*|>//g' \
  | tr '\n' ' ' \
  | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/[[:space:]][[:space:]]*/ /g')"
if [ -z "$TEXT" ]; then
  echo "[asr] 没有识别结果" >&2
  printf '%s\n' "$OUT" >&2
  exit 1
fi
printf '%s\n' "$TEXT"
