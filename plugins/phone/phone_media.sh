#!/usr/bin/env bash
# @desc 手机媒体控制：上一首/下一首/播放暂停（ADB 媒体键）
# @usage plugins/phone/phone_media.sh prev | next | playpause | play | pause
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/../.." && pwd)"
serial() {
    if [ -n "${PHONE_SERIAL:-}" ]; then echo "$PHONE_SERIAL"; return; fi
    for s in $(adb devices | awk 'NR>1 && $2=="device" {print $1}'); do
        m=$(adb -s "$s" shell getprop ro.product.model 2>/dev/null | tr -d '\r')
        case "$m" in *Z18*|*NX606J*) echo "$s"; return ;; esac
    done
    ip=$("$ROOT/tools/device.sh" ip phone 2>/dev/null || true)
    if [ -n "$ip" ] && adb -s "$ip:5555" get-state 2>/dev/null | grep -q device; then
        echo "$ip:5555"; return
    fi
    if adb -s 192.168.1.59:5555 get-state 2>/dev/null | grep -q device; then
        echo 192.168.1.59:5555; return
    fi
    "$(dirname "$0")/phone_ip.sh" 2>/dev/null
}
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
