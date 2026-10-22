#!/usr/bin/env bash
# @desc 手机音频转发：调远程 phone_audio.sh，用 scrcpy 把 USB 手机声音转到 3.5mm 小音响
# @usage tools/phone_audio.sh start|stop|status
# @rule 只转发音频，不控制手机播放；start/stop/status
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
[ $# -ge 1 ] || { echo "用法: $0 start|stop|status" >&2; exit 2; }
exec "$DIR/remote.sh" phone_audio "$@"
