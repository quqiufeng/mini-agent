#!/usr/bin/env bash
# @desc 暂停当前播放：VLC 或手机汽水音乐（摄像头遮挡触发）
# @usage tools/pause_all.sh
# @rule 只暂停正在播放的源；不关闭播放器
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
srcs=$("$DIR/state.sh" any-playing 2>/dev/null || true)
case " $srcs " in
    *" media.vlc "*) "$DIR/../plugins/media/media.sh" pause >/dev/null 2>&1 || true ;;
esac
case " $srcs " in
    *" media.phone "*) "$DIR/../plugins/phone/music.sh" pause >/dev/null 2>&1 || true ;;
esac
