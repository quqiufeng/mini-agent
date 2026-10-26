#!/usr/bin/env bash
# @desc 手机音频转发：scrcpy 把手机声音转到本机 USB 小音箱
# @usage tools/phone_audio.sh start|stop|status
set -uo pipefail
exec "$(cd "$(dirname "$0")" && pwd)/phone_music.sh" "$@"
