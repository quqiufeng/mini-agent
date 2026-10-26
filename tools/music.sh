#!/usr/bin/env bash
# @desc [兼容入口] 等同 tools/media.sh（本地 NAS 搜索 + VLC 播放）
# @usage tools/music.sh play|list|stop|status <关键词>
exec "$(cd "$(dirname "$0")" && pwd)/media.sh" "$@"
