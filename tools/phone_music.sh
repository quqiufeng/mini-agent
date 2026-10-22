#!/usr/bin/env bash
# @desc 手机汽水音乐：调远程 phone_music.sh，打开手机汽水音乐并把声音转到小音响
# @usage tools/phone_music.sh play|stop
# @rule 说“手机放汽水音乐/打开汽水音乐”→ play；停止音频转发→ stop（手机播放/暂停仍由手机控制）
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
[ $# -ge 1 ] || { echo "用法: $0 play|stop" >&2; exit 2; }
exec "$DIR/remote.sh" phone_music "$@"
