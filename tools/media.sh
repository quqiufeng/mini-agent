#!/usr/bin/env bash
# @desc 本地媒体：NAS 上搜歌曲/美剧/电影，用本机 VLC 播放（音频→USB 小音箱，视频→本机/电视 HDMI）
# @usage tools/media.sh play <关键词> [--fullscreen] | list <关键词> | stop | status
# @rule 说“播放/放 <歌名/歌手/美剧/电影>”→ tools/media.sh play <关键词>；视频要上电视加 --fullscreen
set -uo pipefail
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DISPLAY="${DISPLAY:-:0}"
export XAUTHORITY="${XAUTHORITY:-/tmp/xauth_pLarOv}"
PIDFILE=/tmp/myagent-media.pid
AUDIO_EXT='flac|wma|ape|mp3|m4a|wav|aac|ogg'
VIDEO_EXT='mkv|mp4|avi|ts|mov|m2ts|wmv|rmvb'

ensure_mount() {
    local m
    m=$(ls -d /run/user/$(id -u)/gvfs/dav:host=192.168.1.53,port=5005,ssl=false* 2>/dev/null | head -1)
    if [ -n "$m" ] && [ -d "$m/sata11-18072858035" ]; then echo "$m"; return 0; fi
    set -a; . "$HOME/.env"; set +a
    local cred
    cred=$(python3 -c 'import os,urllib.parse;print(urllib.parse.quote(os.environ["WEBDAV_USER"],safe="")+":"+urllib.parse.quote(os.environ["WEBDAV_PASS"],safe=""))')
    timeout 15 gio mount "dav://$cred@192.168.1.53:5005" >/dev/null 2>&1 || true
    m=$(ls -d /run/user/$(id -u)/gvfs/dav:host=192.168.1.53,port=5005,ssl=false* 2>/dev/null | head -1)
    [ -n "$m" ] && echo "$m" && return 0
    return 1
}

search() {
    local root="$1" kw="$2" f g d
    # 音乐（单层目录，直接 glob，快）
    for f in "$root/mp3/无损"/*; do
        [ -f "$f" ] && printf '%s\n' "$f"
    done | grep -F "$kw"
    # 影视（两级 glob：剧名目录/季目录/文件）
    for d in "$root"/*/; do
        case "$d" in */mp3/) continue ;; esac
        for f in "$d"*; do
            if [ -f "$f" ]; then
                printf '%s\n' "$f"
            elif [ -d "$f" ]; then
                for g in "$f"/*; do [ -f "$g" ] && printf '%s\n' "$g"; done
            fi
        done
    done | grep -iE "\.($VIDEO_EXT|$AUDIO_EXT)$" | grep -F "$kw"
}

cmd="${1:-}"; shift || true
case "$cmd" in
    list)
        [ $# -ge 1 ] || { echo "用法: $0 list <关键词>" >&2; exit 2; }
        m=$(ensure_mount) || { echo "[media] NAS 未挂载" >&2; exit 1; }
        search "$m/sata11-18072858035" "$*" | head -60
        ;;
    play)
        kw="$1"; shift || true
        [ -n "$kw" ] || { echo "用法: $0 play <关键词> [--fullscreen]" >&2; exit 2; }
        m=$(ensure_mount) || { echo "[media] NAS 未挂载" >&2; exit 1; }
        mapfile -t files < <(search "$m/sata11-18072858035" "$kw")
        [ ${#files[@]} -gt 0 ] || { echo "[media] 没找到: $kw" >&2; exit 1; }
        if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
            kill "$(cat "$PIDFILE")" 2>/dev/null || true; sleep 0.3
        fi
        is_audio=1
        for f in "${files[@]}"; do
            case "${f,,}" in
                *.mkv|*.mp4|*.avi|*.ts|*.mov|*.m2ts|*.wmv|*.rmvb) is_audio=0; break ;;
            esac
        done
        args=(--no-video-title-show --play-and-exit)
        [ "${1:-}" = "--fullscreen" ] && args+=(--fullscreen)
        [ "$is_audio" = "1" ] && args+=(--no-video)
        setsid nohup vlc "${args[@]}" "${files[@]}" >/tmp/myagent-media.log 2>&1 &
        echo $! > "$PIDFILE"
        echo "播放 ${#files[@]} 个: $(basename "${files[0]}")"
        ;;
    stop)
        if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
            kill "$(cat "$PIDFILE")" 2>/dev/null || true; rm -f "$PIDFILE"; echo "已停止"
        else echo "没有在播放"; fi
        ;;
    status)
        if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
            echo "播放中 pid=$(cat "$PIDFILE")"
        else echo "未播放"; fi
        ;;
    *) echo "用法: $0 play <关键词> [--fullscreen] | list <关键词> | stop | status" >&2; exit 2 ;;
esac
