#!/usr/bin/env bash
# @desc 音量：本机 USB 小音箱（默认 sink）与电视音量一起调
# @usage plugins/system/volume.sh up [步长] | down [步长] | mute | set <0-153> | status
# @rule 说“声音大一点/小一点/静音/音量调到 X”→ plugins/system/volume.sh up|down|mute|set X
set -uo pipefail
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
TV="${TV_SERIAL:-192.168.1.110:5555}"
STEP="${2:-5}"

sink_now() {
    pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null | head -1 | grep -o '[0-9]\+%' | head -1 | tr -d '%'
}
sink_set() {
    pactl set-sink-volume @DEFAULT_SINK@ "$1%" 2>/dev/null || true
}
tv_awake() {
    [ "${VOLUME_NO_TV:-0}" = "1" ] && return 1
    adb -s "$TV" shell 'dumpsys power | grep -m1 mWakefulness' 2>/dev/null | grep -q 'Awake'
}

case "${1:-status}" in
    up)
        cur=$(sink_now); [ -n "$cur" ] || cur=50
        new=$((cur + STEP)); [ "$new" -gt 153 ] && new=153
        sink_set "$new"
        if tv_awake; then
            adb -s "$TV" shell input keyevent 24 >/dev/null 2>&1 || true
            echo "音量 $cur% → $new%（电视同步 +1）"
        else
            echo "音量 $cur% → $new%（电视待机，未动）"
        fi
        ;;
    down)
        cur=$(sink_now); [ -n "$cur" ] || cur=50
        new=$((cur - STEP)); [ "$new" -lt 0 ] && new=0
        sink_set "$new"
        if tv_awake; then
            adb -s "$TV" shell input keyevent 25 >/dev/null 2>&1 || true
            echo "音量 $cur% → $new%（电视同步 -1）"
        else
            echo "音量 $cur% → $new%（电视待机，未动）"
        fi
        ;;
    mute)
        pactl set-sink-mute @DEFAULT_SINK@ toggle 2>/dev/null || true
        tv_awake && adb -s "$TV" shell input keyevent 164 >/dev/null 2>&1 || true
        echo "静音切换：$(pactl get-sink-mute @DEFAULT_SINK@ 2>/dev/null | tail -1)"
        ;;
    set)
        n="${2:-50}"; [[ "$n" =~ ^[0-9]+$ ]] || { echo "用法: $0 set <0-153>" >&2; exit 2; }
        [ "$n" -gt 153 ] && n=153
        sink_set "$n"
        if tv_awake; then
            cur_tv=$(adb -s "$TV" shell 'settings get system volume_music_speaker' 2>/dev/null | tr -d '\r')
            [[ "$cur_tv" =~ ^[0-9]+$ ]] || cur_tv=0
            tgt_tv=$((n * 100 / 153))
            delta=$((tgt_tv - cur_tv)); key=24
            [ "$delta" -lt 0 ] && { key=25; delta=$((-delta)); }
            [ "$delta" -gt 30 ] && delta=30
            for _ in $(seq 1 "$delta"); do adb -s "$TV" shell input keyevent "$key" >/dev/null 2>&1 || true; done
        fi
        echo "音量 → ${n}%"
        ;;
    status)
        v=$(sink_now); m=$(pactl get-sink-mute @DEFAULT_SINK@ 2>/dev/null | tail -1)
        echo "USB 小音箱: ${v:-?}% $m"
        if tv_awake; then
            tv=$(adb -s "$TV" shell 'settings get system volume_music_speaker' 2>/dev/null | tr -d '\r')
            echo "电视媒体音量: ${tv:-未知}"
        else
            echo "电视: 待机（未调整）"
        fi
        ;;
    *) echo "用法: $0 up|down|mute|set <0-153>|status" >&2; exit 2 ;;
esac
