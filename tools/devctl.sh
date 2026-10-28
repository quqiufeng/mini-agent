#!/usr/bin/env bash
# @desc 统一设备操作入口：状态/媒体/手机/镜像/音量/摄像头
# @usage tools/devctl.sh state ... | media <act> | phone <act> | mirror <wechat|off> | volume ... | camera ... | pause | status
# @rule 所有设备操作只走这里；具体实现仍由 media.sh / phone_music.sh / wechat_show.sh / volume.sh / camera_block.sh 完成
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
STATE="$DIR/state.sh"

active_src() { "$STATE" active-media 2>/dev/null || true; }

media_act() {
    local act="${1:-}"
    local src; src=$(active_src)
    case "$src" in
        media.phone)
            case "$act" in
                pause)  exec "$DIR/phone_music.sh" pause ;;
                resume) exec "$DIR/phone_music.sh" resume ;;
                stop)   exec "$DIR/phone_music.sh" stop ;;
                status) exec "$DIR/phone_music.sh" status ;;
                next|prev) exec "$DIR/phone_media.sh" "$act" ;;
                toggle|playpause)
                    local val; val=$("$STATE" get media.phone 2>/dev/null | awk '{print $1}' || true)
                    if [ "$val" = "playing" ]; then exec "$DIR/phone_music.sh" pause; fi
                    exec "$DIR/phone_music.sh" resume
                    ;;
                *) echo "手机不支持: $act" >&2; exit 2 ;;
            esac
            ;;
        media.vlc)
            exec "$DIR/media.sh" "$act" ;;
    esac
    if [ -f /tmp/myagent-phone-music.pid ] && kill -0 "$(cat /tmp/myagent-phone-music.pid)" 2>/dev/null; then
        case "$act" in
            next|prev) exec "$DIR/phone_media.sh" "$act" ;;
            pause|resume|stop|status) exec "$DIR/phone_music.sh" "$act" ;;
            toggle|playpause)
                local val; val=$("$STATE" get media.phone 2>/dev/null | awk '{print $1}' || true)
                if [ "$val" = "playing" ]; then exec "$DIR/phone_music.sh" pause; fi
                exec "$DIR/phone_music.sh" resume
                ;;
        esac
    fi
    if [ -f /tmp/myagent-media.pid ] && kill -0 "$(cat /tmp/myagent-media.pid)" 2>/dev/null; then
        exec "$DIR/media.sh" "$act"
    fi
    echo "没有在播放" >&2
    exit 1
}

cmd="${1:-status}"; shift || true
case "$cmd" in
    state)  exec "$STATE" "$@" ;;
    media)
        act="${1:-}"; shift || true
        case "$act" in
            play|list) exec "$DIR/media.sh" "$act" "$@" ;;
            "") echo "用法: $0 media play|list|pause|resume|toggle|next|prev|stop|status" >&2; exit 2 ;;
            *) media_act "$act" ;;
        esac
        ;;
    phone)
        act="${1:-}"; shift || true
        case "$act" in
            play|pause|resume|stop|status) exec "$DIR/phone_music.sh" "$act" ;;
            wechat) exec "$DIR/wechat_show.sh" start ;;
            "") echo "用法: $0 phone play|pause|resume|stop|status|wechat" >&2; exit 2 ;;
            *) echo "未知手机操作: $act" >&2; exit 2 ;;
        esac
        ;;
    mirror)
        act="${1:-}"; shift || true
        case "$act" in
            wechat) exec "$DIR/wechat_show.sh" start ;;
            off|stop) exec "$DIR/wechat_show.sh" stop ;;
            status) exec "$DIR/wechat_show.sh" status ;;
            *) echo "用法: $0 mirror wechat|off|status" >&2; exit 2 ;;
        esac
        ;;
    volume|camera)
        exec "$DIR/$cmd.sh" "$@" ;;
    pause)
        exec "$DIR/pause_all.sh" ;;
    status)
        echo "== devices =="; "$STATE" show
        echo "== active =="; active_src || echo "none"
        ;;
    *)
        echo "用法: $0 state|media|phone|mirror|volume|camera|pause|status ..." >&2
        exit 2
        ;;
esac
