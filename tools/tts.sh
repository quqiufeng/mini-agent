#!/usr/bin/env bash
# @desc 文本转语音：调远程 living_audio.sh；默认走 Pulse/PipeWire，受本机 OS 音量控制
# @usage tools/tts.sh "文本"
# @rule 远程合成+scp+播放；AOUT 默认 pulse，物理音响旋钮和 OS 音量都可调
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
AOUT="${SMALLPC_AOUT:-pulse}"
[[ "$AOUT" =~ ^[A-Za-z0-9_-]+$ ]] || { echo "非法 AOUT: $AOUT" >&2; exit 2; }

[ $# -ge 1 ] || { echo "用法: $0 \"文本\"" >&2; exit 2; }
TEXT="$*"

if ! "$DIR/remote.sh" --env "SMALLPC_AOUT=$AOUT" living_audio say "$TEXT" \
  >/tmp/myagent-tts.log 2>&1; then
  echo "[tts] 远程合成/播放失败" >&2
  tail -20 /tmp/myagent-tts.log >&2 || true
  exit 1
fi

cat /tmp/myagent-tts.log
