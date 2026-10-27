#!/usr/bin/env bash
# @desc 本地闹钟：N 分钟后或指定时间，用标题语音提醒 5 遍（本地 TTS，独立于 GUI/大脑）
# @usage tools/alarm.sh in <时长> <标题...>
#        tools/alarm.sh at <HH:MM> <标题...>
#        tools/alarm.sh list | cancel <id|all> | stop
#        tools/alarm.sh test [标题]
# @rule 时长支持 10m / 1h30m / 90s / 1d / 10分钟；at 支持 7:30 / 7点30 / 7点半，已过则排到明天
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
SELF="$DIR/alarm.sh"
TTS="$DIR/tts.sh"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/my-agent/alarms"
LOG="$STATE/alarm.log"
mkdir -p "$STATE"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

parse_duration() {
    local s="${1// /}" total=0 n u
    s="${s//以后/}"; s="${s//之后/}"; s="${s//后/}"
    s="${s//一个半小时/90m}"; s="${s//半小时/30m}"; s="${s//一刻钟/15m}"
    s="${s//小时/h}"; s="${s//分钟/m}"; s="${s//分/m}"; s="${s//秒/s}"; s="${s//天/d}"
    if [[ "$s" =~ ^[0-9]+$ ]]; then
        echo $((s * 60))
        return 0
    fi
    while [[ "$s" =~ ^([0-9]+)([smhd])(.*)$ ]]; do
        n="${BASH_REMATCH[1]}"; u="${BASH_REMATCH[2]}"; s="${BASH_REMATCH[3]}"
        case "$u" in
            s) total=$((total + n)) ;;
            m) total=$((total + n * 60)) ;;
            h) total=$((total + n * 3600)) ;;
            d) total=$((total + n * 86400)) ;;
        esac
    done
    if [ -z "$s" ] && [ "$total" -gt 0 ]; then echo "$total"; return 0; fi
    return 1
}

parse_at() {
    local s="${1// /}" hh mm due now
    s="${s//：/:}"
    if [[ "$s" =~ ^([0-9]{1,2}):([0-9]{1,2})$ ]]; then
        hh="${BASH_REMATCH[1]}"; mm="${BASH_REMATCH[2]}"
    elif [[ "$s" =~ ^([0-9]{1,2})点半$ ]]; then
        hh="${BASH_REMATCH[1]}"; mm=30
    elif [[ "$s" =~ ^([0-9]{1,2})点([0-9]{1,2})分?$ ]]; then
        hh="${BASH_REMATCH[1]}"; mm="${BASH_REMATCH[2]}"
    elif [[ "$s" =~ ^([0-9]{1,2})点$ ]]; then
        hh="${BASH_REMATCH[1]}"; mm=0
    else
        return 1
    fi
    (( hh >= 0 && hh <= 23 && mm >= 0 && mm <= 59 )) || return 1
    date -d "$(date +%F) $(printf '%02d:%02d' "$hh" "$mm")" +%s 2>/dev/null
}

schedule() {
    local due="$1" title="${2:-闹钟}" id meta wav pid i
    title="${title#标题是}"; title="${title#标题：}"; title="${title#标题:}"; title="${title#标题 }"
    [ -n "$title" ] || title="闹钟"
    id="alarm_$(date +%Y%m%d_%H%M%S)_$RANDOM"
    meta="$STATE/$id.meta"
    wav="$STATE/$id.wav"
    printf 'due=%s\ntitle=%s\npid=\nwav=%s\n' "$due" "$title" "$wav" > "$meta"
    setsid "$SELF" __worker "$due" "$title" "$meta" "$wav" >>"$LOG" 2>&1 < /dev/null &
    for i in $(seq 1 30); do
        [ -s "$meta.pid" ] && { pid=$(cat "$meta.pid"); break; }
        sleep 0.1
    done
    if [ -n "${pid:-}" ]; then
        sed -i "s/^pid=.*/pid=$pid/" "$meta"
    fi
    echo "已设置闹钟 $id：$(date -d "@$due" '+%F %T') — $title"
    echo "id=$id"
}

__worker() {
    local due="$1" title="$2" meta="$3" wav="$4" i now rem
    echo $$ > "$meta.pid"
    trap 'rm -f "$meta" "$meta.pid" "$wav" "$wav.tmp"; exit 0' TERM INT
    [ -f "$meta" ] || exit 0

    if [ ! -s "$wav" ]; then
        TTS_NOPLAY=1 TTS_LOCAL_OUT="$wav" "$TTS" "闹钟提醒：$title" >>"$LOG" 2>&1
    fi

    while :; do
        now=$(date +%s)
        [ "$now" -ge "$due" ] && break
        rem=$((due - now))
        [ "$rem" -gt 30 ] && rem=30
        [ "$rem" -lt 1 ] && rem=1
        sleep "$rem"
    done

    for i in 1 2 3 4 5; do
        echo "$(date '+%F %T') play $i: $title" >>"$LOG"
        if [ -s "$wav" ] && command -v paplay >/dev/null 2>&1; then
            paplay "$wav" 2>>"$LOG" || "$TTS" "闹钟提醒：$title" >>"$LOG" 2>&1
        else
            "$TTS" "闹钟提醒：$title" >>"$LOG" 2>&1
        fi
        [ "$i" -lt 5 ] && sleep 1
    done
    rm -f "$meta" "$meta.pid" "$wav" "$wav.tmp"
}

list_alarms() {
    local f due title pid found=0
    for f in "$STATE"/*.meta; do
        [ -e "$f" ] || continue
        found=1
        due=$(sed -n 's/^due=//p' "$f" | head -1)
        title=$(sed -n 's/^title=//p' "$f" | head -1)
        pid=$(sed -n 's/^pid=//p' "$f" | head -1)
        echo "$(basename "$f" .meta)  $(date -d "@$due" '+%F %T')  $title  pid=${pid:-?}"
    done
    [ "$found" -eq 1 ] || echo "没有闹钟"
}

cancel_one() {
    local id="$1" f="$STATE/$1.meta" pid
    [ -f "$f" ] || return 1
    pid=$(sed -n 's/^pid=//p' "$f" | head -1)
    if [ -n "$pid" ]; then
        kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
    fi
    rm -f "$f" "$STATE/$id.pid" "$STATE/$id.wav" "$STATE/$id.wav.tmp"
    echo "已取消 $id"
}

cmd="${1:-help}"
shift || true

case "$cmd" in
    in)
        [ $# -ge 1 ] || { echo "用法: $0 in <时长> <标题...>" >&2; exit 2; }
        secs=$(parse_duration "$1") || { echo "[alarm] 无法解析时长: $1" >&2; exit 2; }
        [ "$secs" -gt 0 ] || { echo "[alarm] 时长必须大于 0" >&2; exit 2; }
        shift
        schedule "$(( $(date +%s) + secs ))" "${*:-闹钟}"
        ;;
    at)
        tomorrow=0
        if [ "${1:-}" = "明天" ] || [ "${1:-}" = "tomorrow" ]; then tomorrow=1; shift; fi
        [ $# -ge 1 ] || { echo "用法: $0 at <HH:MM> <标题...>" >&2; exit 2; }
        due=$(parse_at "$1") || { echo "[alarm] 无法解析时间: $1" >&2; exit 2; }
        now=$(date +%s)
        if [ "$tomorrow" -eq 1 ] || [ "$due" -le "$now" ]; then
            due=$((due + 86400))
        fi
        shift
        schedule "$due" "${*:-闹钟}"
        ;;
    list|ls) list_alarms ;;
    cancel)
        [ $# -ge 1 ] || { echo "用法: $0 cancel <id|all>" >&2; exit 2; }
        if [ "$1" = "all" ]; then
            for f in "$STATE"/*.meta; do
                [ -e "$f" ] || continue
                cancel_one "$(basename "$f" .meta)" >/dev/null
            done
            echo "已取消全部闹钟"
        else
            cancel_one "$1" || { echo "[alarm] 找不到: $1" >&2; exit 1; }
        fi
        ;;
    stop) exec "$0" cancel all ;;
    test)
        shift || true
        schedule "$(( $(date +%s) + 5 ))" "${*:-测试闹钟}"
        ;;
    __worker) __worker "$@" ;;
    help|-h|--help|*)
        echo "用法:"
        echo "  $0 in <时长> <标题...>     例: in 10m 关火"
        echo "  $0 at <HH:MM> <标题...>    例: at 7:30 起床（已过则明天）"
        echo "  $0 list | cancel <id|all> | stop"
        echo "  $0 test [标题]             5 秒后测试，响 5 遍"
        ;;
esac
