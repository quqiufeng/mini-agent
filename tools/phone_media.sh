#!/usr/bin/env bash
# @desc 手机媒体控制：上一首/下一首/播放暂停（ADB 媒体键）
# @usage tools/phone_media.sh prev | next | playpause | play | pause
set -uo pipefail
serial() { adb devices | awk 'NR>1 && $2=="device" {print $1; exit}'; }
s=$(serial); [ -n "$s" ] || { echo "[phone_media] 手机未连接" >&2; exit 1; }
case "${1:-}" in
    prev)      k=88 ;;
    next)      k=87 ;;
    playpause) k=85 ;;
    play)      k=126 ;;
    pause)     k=127 ;;
    *) echo "用法: $0 prev|next|playpause|play|pause" >&2; exit 2 ;;
esac
adb -s "$s" shell input keyevent "$k"
echo "已发送媒体键 $k"
