#!/usr/bin/env bash
# @desc 文本转语音：调远程 living_audio.sh；默认走 Pulse/PipeWire，受本机 OS 音量控制
# @usage tools/tts.sh "文本"
# @rule 远程合成+scp+播放；AOUT 默认 pulse，物理音响旋钮和 OS 音量都可调
set -euo pipefail

HOST="${REMOTE_HOST:-quqiufeng@192.168.1.10}"
AOUT="${SMALLPC_AOUT:-pulse}"
[ $# -ge 1 ] || { echo "用法: $0 \"文本\"" >&2; exit 2; }
TEXT="$*"
TEXT_Q="$(printf '%q' "$TEXT")"

CMD="SMALLPC_AOUT=$AOUT /opt/my-agent/operator/tools/living_audio.sh say $TEXT_Q"
if ! ssh -o BatchMode=yes -o ConnectTimeout=10 "$HOST" "$CMD" >/tmp/myagent-tts.log 2>&1; then
  echo "[tts] 远程合成/播放失败" >&2
  tail -20 /tmp/myagent-tts.log >&2 || true
  exit 1
fi

cat /tmp/myagent-tts.log
