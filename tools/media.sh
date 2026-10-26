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
    local root="$1" kw="$2"
    local base="$root/mp3/无损" name e f
    # 音乐：一次 readdir + grep，按文件名命中
    local names mhits
    names=$(ls -1 "$base" 2>/dev/null)
    mhits=$(printf '%s\n' "$names" | grep -F "$kw")
    if [ -n "$mhits" ]; then
        printf '%s\n' "$mhits" | while IFS= read -r name; do
            [ -n "$name" ] && printf '%s/%s\n' "$base" "$name"
        done
        return
    fi
    # 影视：只展开目录名命中的剧/电影（两层 ls，避免全库 stat）
    while IFS= read -r name; do
        case "$name" in *"$kw"*) ;; *) continue ;; esac
        local d="$root/$name"
        [ -d "$d" ] || continue
        while IFS= read -r e; do
            [ -z "$e" ] && continue
            if [ -d "$d/$e" ]; then
                while IFS= read -r f; do
                    [ -n "$f" ] && printf '%s/%s/%s\n' "$d" "$e" "$f"
                done < <(ls -1 "$d/$e" 2>/dev/null)
            else
                printf '%s/%s\n' "$d" "$e"
            fi
        done < <(ls -1 "$d" 2>/dev/null)
    done < <(ls -1 "$root" 2>/dev/null) | grep -iE "\.($VIDEO_EXT|$AUDIO_EXT)$"
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
        if [ "$is_audio" = "1" ]; then
            pick="${MEDIA_PICK:-5}"
            if [ "${#files[@]}" -gt "$pick" ]; then
                mapfile -t files < <(printf '%s\n' "${files[@]}" | shuf -n "$pick")
            fi
        fi
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
