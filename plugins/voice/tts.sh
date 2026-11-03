#!/usr/bin/env bash
# @desc 文本转语音：本机 sherpa-onnx + Kokoro 优先，失败再回退远程 say.sh
# @usage plugins/voice/tts.sh "文本"
# @rule 本机有 Kokoro 模型时完全本地合成；TTS_LOCAL=0 或本地失败时回退远程
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/../.." && pwd)"
_host=$("$ROOT/tools/device.sh" ip computer 2>/dev/null || true)
HOST="${REMOTE_HOST:-quqiufeng@${_host:-192.168.1.10}}"
OUT="${TTS_LOCAL_OUT:-/tmp/myagent-tts.wav}"
REMOTE_OUT="/tmp/myagent-tts-$$.wav"

[ $# -ge 1 ] || { echo "用法: $0 \"文本\"" >&2; exit 2; }
TEXT="$*"

TTS_LOCAL_BIN="${TTS_LOCAL_BIN:-/opt/sherpa-onnx/bin/sherpa-onnx-offline-tts}"
SHERPA_LIB="${SHERPA_LIB:-/opt/sherpa-onnx/lib}"
KOKORO_DIR="${KOKORO_DIR:-/opt/sherpa-onnx/models/kokoro-multi-lang-v1_0}"
KOKORO_SID="${KOKORO_SID:-47}"
TTS_THREADS="${TTS_THREADS:-4}"

LOCAL_OK=0
if [ "${TTS_LOCAL:-1}" != "0" ] && [ -x "$TTS_LOCAL_BIN" ] && [ -r "$KOKORO_DIR/model.onnx" ]; then
    rm -f "$OUT"
    if LD_LIBRARY_PATH="$SHERPA_LIB:${LD_LIBRARY_PATH:-}" "$TTS_LOCAL_BIN" \
        --kokoro-model="$KOKORO_DIR/model.onnx" \
        --kokoro-voices="$KOKORO_DIR/voices.bin" \
        --kokoro-tokens="$KOKORO_DIR/tokens.txt" \
        --kokoro-data-dir="$KOKORO_DIR/espeak-ng-data" \
        --kokoro-lexicon="$KOKORO_DIR/lexicon-us-en.txt,$KOKORO_DIR/lexicon-zh.txt" \
        --tts-rule-fsts="$KOKORO_DIR/date-zh.fst,$KOKORO_DIR/number-zh.fst" \
        --num-threads="$TTS_THREADS" --sid="$KOKORO_SID" \
        --output-filename="$OUT" "$TEXT" >/tmp/myagent-tts.log 2>&1 \
        && [ -s "$OUT" ]; then
        LOCAL_OK=1
    fi
fi

if [ "$LOCAL_OK" != "1" ]; then
    if ! "$DIR/remote.sh" --env "TTS_OUT=$REMOTE_OUT" --env "SAY_NOPLAY=1" say "$TEXT" \
        >/tmp/myagent-tts-remote.log 2>&1; then
        echo "[tts] 本地和远程合成都失败" >&2
        tail -20 /tmp/myagent-tts.log >&2 || true
        tail -20 /tmp/myagent-tts-remote.log >&2 || true
        exit 1
    fi
    if ! scp -q "$HOST:$REMOTE_OUT" "$OUT"; then
        echo "[tts] 拉取 WAV 失败" >&2
        exit 1
    fi
    ssh -o BatchMode=yes "$HOST" "rm -f $REMOTE_OUT" >/dev/null 2>&1 || true
fi

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
if [ "${TTS_NOPLAY:-0}" = "1" ]; then
  echo "$OUT"
  exit 0
fi
if command -v paplay >/dev/null 2>&1; then
  play_cmd=(paplay "$OUT")
elif command -v pw-play >/dev/null 2>&1; then
  play_cmd=(pw-play "$OUT")
else
  echo "[tts] 没有 paplay/pw-play" >&2
  exit 1
fi
playing=/tmp/myagent_tts.playing
touch "$playing"
trap 'rm -f "$playing"' EXIT INT TERM
"${play_cmd[@]}"
rm -f "$playing"
trap - EXIT
echo "$OUT"
