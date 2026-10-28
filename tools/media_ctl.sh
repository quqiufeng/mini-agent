#!/usr/bin/env bash
# @desc 媒体控制兼容入口：统一交给 devctl media（按当前活动源）
# @usage tools/media_ctl.sh prev | next | playpause | pause | resume | stop
# @rule GUI/旧脚本用这里；具体分发给 devctl.sh media
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
case "${1:-}" in
    playpause) exec "$DIR/devctl.sh" media toggle ;;
    prev|next|pause|resume|stop|status) exec "$DIR/devctl.sh" media "$1" ;;
    *) echo "用法: $0 prev|next|playpause|pause|resume|stop" >&2; exit 2 ;;
esac
