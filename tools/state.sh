#!/usr/bin/env bash
# @desc 统一设备/媒体状态：原子读写 /tmp/myagent_state/<key>，供所有工具和 GUI 查询
# @usage tools/state.sh set <key> <value> [extra...] | get <key> | show | tidy | active-media | any-playing | playing <key> | stale <key> <秒>
# @rule 值的格式为 "<value> <epoch> [extra...]"；写入用临时文件 + mv 原子替换；进程类状态带 pid 便于判活
set -uo pipefail
DIR="${STATE_DIR:-/tmp/myagent_state}"
mkdir -p "$DIR"

pid_matches() {
    local key="$1" pid="$2" cl
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null || return 1
    [ -r "/proc/$pid/cmdline" ] || return 1
    cl=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true)
    case "$key" in
        media.vlc) echo "$cl" | grep -q 'vlc' ;;
        media.phone|display.wechat) echo "$cl" | grep -q 'scrcpy' ;;
        *) return 0 ;;
    esac
}

case "${1:-show}" in
    set)
        key="${2:-}"; val="${3:-}"
        [ -n "$key" ] && [ -n "$val" ] || { echo "用法: $0 set <key> <value> [extra...]" >&2; exit 2; }
        shift 3 || true
        tmp="$DIR/.$key.$$"
        { printf '%s %s' "$val" "$(date +%s)"; [ $# -gt 0 ] && printf ' %s' "$@"; printf '\n'; } > "$tmp"
        mv -f "$tmp" "$DIR/$key"
        ;;
    get)
        [ -n "${2:-}" ] || { echo "用法: $0 get <key>" >&2; exit 2; }
        cat "$DIR/$2" 2>/dev/null
        ;;
    show)
        for f in "$DIR"/*; do
            [ -f "$f" ] || continue
            printf '%-16s %s\n' "$(basename "$f")" "$(cat "$f")"
        done
        ;;
    stale)
        key="${2:-}"; max="${3:-5}"
        line=$(cat "$DIR/$key" 2>/dev/null || true)
        [ -n "$line" ] || exit 1
        ts=$(printf '%s\n' "$line" | awk '{print $2}')
        now=$(date +%s)
        [ $((now - ts)) -gt "$max" ] && exit 0 || exit 1
        ;;
    tidy)
        for key in media.vlc media.phone display.wechat; do
            line=$(cat "$DIR/$key" 2>/dev/null || true)
            [ -n "$line" ] || continue
            val=$(printf '%s\n' "$line" | awk '{print $1}')
            pid=$(printf '%s\n' "$line" | awk '{print $3}')
            case "$key:$val" in
                media.vlc:playing|media.vlc:paused|media.phone:playing|media.phone:paused|display.wechat:on)
                    if ! pid_matches "$key" "$pid"; then
                        case "$key" in
                            media.vlc|media.phone) "$0" set "$key" stopped "${pid:-0}" ;;
                            display.wechat) "$0" set "$key" off "${pid:-0}" ;;
                        esac
                    fi
                    ;;
            esac
        done
        ;;
    active-media)
        best_play=""; best_play_ts=-1
        best_pause=""; best_pause_ts=-1
        for key in media.phone media.vlc; do
            line=$(cat "$DIR/$key" 2>/dev/null || true)
            [ -n "$line" ] || continue
            val=$(printf '%s\n' "$line" | awk '{print $1}')
            ts=$(printf '%s\n' "$line" | awk '{print $2}')
            pid=$(printf '%s\n' "$line" | awk '{print $3}')
            case "$val" in playing|paused) ;; *) continue ;; esac
            pid_matches "$key" "$pid" || continue
            if [ "$val" = "playing" ]; then
                if [ "${ts:-0}" -gt "$best_play_ts" ]; then best_play="$key"; best_play_ts=$ts; fi
            else
                if [ "${ts:-0}" -gt "$best_pause_ts" ]; then best_pause="$key"; best_pause_ts=$ts; fi
            fi
        done
        [ -n "$best_play" ] && { echo "$best_play"; exit 0; }
        [ -n "$best_pause" ] && { echo "$best_pause"; exit 0; }
        exit 1
        ;;
    any-playing)
        for key in media.phone media.vlc; do
            line=$(cat "$DIR/$key" 2>/dev/null || true)
            [ -n "$line" ] || continue
            val=$(printf '%s\n' "$line" | awk '{print $1}')
            pid=$(printf '%s\n' "$line" | awk '{print $3}')
            [ "$val" = "playing" ] && pid_matches "$key" "$pid" && echo "$key"
        done
        ;;
    playing)
        line=$(cat "$DIR/${2:-}" 2>/dev/null || true)
        [ "$(printf '%s\n' "$line" | awk '{print $1}')" = "playing" ]
        ;;
    *)
        echo "用法: $0 set <key> <value> [extra...] | get <key> | show | tidy | active-media | any-playing | playing <key> | stale <key> <秒>" >&2
        exit 2
        ;;
esac
