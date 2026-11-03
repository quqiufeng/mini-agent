#!/usr/bin/env bash
# @desc 第二台手机（Redmi Note 14 5G / 微信）控制：mDNS 自动找无线调试端口并连接
# @usage plugins/phone/phone2.sh connect|status|shot [out]|open <app>|text <文本>|key <KEYCODE>|tap X Y|apps
# @rule 无线调试端口会变；默认手机 192.168.1.59，可用 PHONE2_IP 覆盖
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
IP="${PHONE2_IP:-192.168.1.59}"
CACHE=/tmp/myagent_phone2.serial

mdns_port() {
    timeout 5 avahi-browse -rt _adb-tls-connect._tcp 2>/dev/null | awk -v ip="$IP" '
        /address = \[/ { a=$0; gsub(/.*\[|\].*/, "", a) }
        /port = \[/ && a == ip { p=$0; gsub(/.*\[|\].*/, "", p); print p; exit }'
}

do_connect() {
    local s p
    s=$(adb devices | awk -v ip="$IP" '$1 ~ ("^" ip ":") && $2 == "device" { print $1; exit }')
    if [ -n "$s" ]; then printf '%s\n' "$s" > "$CACHE"; printf '%s\n' "$s"; return 0; fi
    p=$(mdns_port)
    if [ -z "$p" ]; then
        echo "[phone2] 没扫到无线调试端口：保持亮屏、同一 Wi-Fi、无线调试开启" >&2
        return 1
    fi
    adb connect "$IP:$p" >/dev/null 2>&1
    s="$IP:$p"
    if adb -s "$s" get-state >/dev/null 2>&1; then
        printf '%s\n' "$s" > "$CACHE"
        printf '%s\n' "$s"
        return 0
    fi
    echo "[phone2] 连接失败: $s" >&2
    return 1
}

get_serial() {
    local s
    if [ -f "$CACHE" ]; then
        s=$(cat "$CACHE")
        if adb -s "$s" get-state >/dev/null 2>&1; then printf '%s\n' "$s"; return 0; fi
    fi
    do_connect
}

serial=$(get_serial) || exit 1
cmd="${1:-status}"

case "$cmd" in
    connect)
        echo "$serial"
        ;;
    status|battery)
        echo "serial: $serial"
        adb -s "$serial" shell 'printf "model: "; getprop ro.product.model; printf "brand: "; getprop ro.product.brand; printf "android: "; getprop ro.build.version.release; dumpsys battery | grep -E "level:|status:|temperature:"' 2>/dev/null | tr -d '\r'
        ;;
    shot)
        OUT="${2:-/tmp/phone2.png}"
        adb -s "$serial" exec-out screencap -p > "$OUT" 2>/dev/null
        [ -s "$OUT" ] && echo "$OUT" || { echo "[phone2] 截图失败" >&2; exit 1; }
        ;;
    open)
        APP="${2:-}"
        [ -n "$APP" ] || { echo "用法: $0 open <包名|wechat|douyin|music|amap|alipay|taobao|settings|clock>" >&2; exit 2; }
        case "$APP" in
            wechat) APP=com.tencent.mm ;;
            douyin) APP=com.ss.android.ugc.aweme ;;
            music) APP=com.luna.music ;;
            amap) APP=com.autonavi.minimap ;;
            alipay) APP=com.eg.android.AlipayGphone ;;
            taobao) APP=com.taobao.taobao ;;
            settings) APP=com.android.settings ;;
            clock) APP=com.android.deskclock ;;
        esac
        adb -s "$serial" shell "monkey -p $APP -c android.intent.category.LAUNCHER 1" >/dev/null 2>&1 || \
            adb -s "$serial" shell "monkey -p $APP 1" >/dev/null 2>&1
        echo "opened $APP"
        ;;
    text)
        TEXT="${2:-}"
        [ -n "$TEXT" ] || { echo "用法: $0 text <文本>" >&2; exit 2; }
        OLD=$(adb -s "$serial" shell settings get secure default_input_method 2>/dev/null | tr -d '\r')
        adb -s "$serial" shell ime enable com.android.adbkeyboard/.AdbIME >/dev/null 2>&1
        adb -s "$serial" shell ime set com.android.adbkeyboard/.AdbIME >/dev/null 2>&1
        sleep 0.4
        adb -s "$serial" shell am broadcast -a ADB_INPUT_TEXT --es msg "$TEXT" >/dev/null 2>&1
        sleep 0.4
        [ -n "$OLD" ] && adb -s "$serial" shell ime set "$OLD" >/dev/null 2>&1 || true
        echo "typed: $TEXT"
        ;;
    key)
        [ -n "${2:-}" ] || { echo "用法: $0 key <KEYCODE>" >&2; exit 2; }
        adb -s "$serial" shell input keyevent "$2"
        ;;
    tap)
        [ -n "${2:-}" ] && [ -n "${3:-}" ] || { echo "用法: $0 tap X Y" >&2; exit 2; }
        adb -s "$serial" shell input tap "$2" "$3"
        ;;
    apps)
        adb -s "$serial" shell pm list packages -3 2>/dev/null | sed 's/package://' | sort
        ;;
    *)
        echo "用法: $0 connect|status|shot [out]|open <app>|text <文本>|key <KEYCODE>|tap X Y|apps" >&2
        exit 2
        ;;
esac
