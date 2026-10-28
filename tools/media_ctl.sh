#!/usr/bin/env bash
# @desc 音乐控制：优先手机汽水音乐，其次本机 VLC
# @usage tools/media_ctl.sh prev | next | playpause
# @rule GUI 的上一首/下一首/暂停播放按钮统一走这里
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
act="${1:-}"
case "$act" in prev|next|playpause) ;; *) echo "用法: $0 prev|next|playpause" >&2; exit 2 ;; esac
if [ -f /tmp/myagent-phone-music.pid ] && kill -0 "$(cat /tmp/myagent-phone-music.pid)" 2>/dev/null; then
    exec "$DIR/phone_media.sh" "$act"
fi
case "$act" in
    prev) exec "$DIR/media.sh" prev ;;
    next) exec "$DIR/media.sh" next ;;
    playpause) exec "$DIR/media.sh" toggle ;;
esac
