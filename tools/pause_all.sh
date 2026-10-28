#!/usr/bin/env bash
# @desc 暂停当前播放：VLC 或手机汽水音乐（摄像头遮挡触发）
# @usage tools/pause_all.sh
# @rule 只暂停正在播放的源；不关闭播放器
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
st=$("$DIR/media.sh" status 2>/dev/null || true)
case "$st" in
    播放中*) "$DIR/media.sh" pause >/dev/null 2>&1 || true ;;
esac
if [ -f /tmp/myagent-phone-music.pid ] && kill -0 "$(cat /tmp/myagent-phone-music.pid)" 2>/dev/null; then
    "$DIR/phone_music.sh" pause >/dev/null 2>&1 || true
fi
