#!/usr/bin/env bash
# @desc 找手机：按 MAC 从 ARP 找 IP，或扫 5555，adb connect 后校验型号（Z18）
# @usage plugins/phone/phone_ip.sh [--mac MA:CA:..]   # 输出可用的 adb serial
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/../.." && pwd)"
MAC="${PHONE_MAC:-76:d0:b4:67:89:a9}"
[ "${1:-}" = "--mac" ] && MAC="${2:-$MAC}"
CACHE=/tmp/myagent_phone.serial

is_phone() {
    local ser="$1" m
    m=$(adb -s "$ser" shell getprop ro.product.model 2>/dev/null | tr -d '\r')
    case "$m" in *Z18*|*NX606J*) return 0 ;; esac
    return 1
}

try_connect() {
    local ip="$1"
    adb connect "$ip:5555" >/dev/null 2>&1 || true
    sleep 0.3
    if is_phone "$ip:5555"; then echo "$ip:5555"; return 0; fi
    return 1
}

# 0) 现有设备里有手机就直接用
for s in $(adb devices | awk 'NR>1 && $2=="device"{print $1}'); do
    if is_phone "$s"; then echo "$s" > "$CACHE"; echo "$s"; exit 0; fi
done

# 1) 按 MAC 查 ARP（先做一轮 UDP 触发）
if [ -n "$MAC" ]; then
    "$ROOT/plugins/system/netscan.sh" udp 192.168.1 >/dev/null 2>&1 || true
    sleep 1.2
    ip=$(ip neigh | grep -i "$MAC" | awk '{print $1}' | head -1)
    if [ -n "$ip" ] && try_connect "$ip"; then echo "$ip:5555" > "$CACHE"; exit 0; fi
fi

# 2) 扫 5555
"$ROOT/plugins/system/netscan.sh" tcp 192.168.1 5555 400 >/tmp/myagent_scan5555.txt 2>/dev/null || true
while IFS= read -r ip; do
    [ -n "$ip" ] || continue
    if try_connect "$ip"; then echo "$ip:5555" > "$CACHE"; echo "$ip:5555"; exit 0; fi
done < /tmp/myagent_scan5555.txt

echo "[phone_ip] 没找到手机" >&2
exit 1
