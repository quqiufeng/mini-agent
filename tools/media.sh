#!/usr/bin/env bash
# @desc 本地媒体：NAS 上搜歌曲/美剧/电影，用本机 VLC 播放（音频→USB 小音箱，视频→本机/电视 HDMI）
# @usage tools/media.sh play <关键词> [第X季] [第Y集] [--fullscreen] | list <关键词> | pause | resume | toggle | next | prev | stop | status
# @rule 说“播放/放 XX”（未提电视）→ 本机 VLC；只有明确说“电视播放/在电视上播”才用 tools/tv_play.sh；音频默认整列表顺序播放（MEDIA_PICK=N 随机 N 首）；GESTURE_STOP=0 可关闭手势暂停
set -uo pipefail
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DISPLAY="${DISPLAY:-:0}"
export XAUTHORITY="${XAUTHORITY:-/tmp/xauth_pLarOv}"
PIDFILE=/tmp/myagent-media.pid
STATE="$(cd "$(dirname "$0")" && pwd)/state.sh"
AUDIO_EXT='flac|wma|ape|mp3|m4a|wav|aac|ogg'
VIDEO_EXT='mkv|mp4|avi|ts|mov|m2ts|wmv|rmvb'

ensure_mount() {
    local m
    m=$(ls -d /run/user/$(id -u)/gvfs/dav:host=192.168.1.53,port=5005,ssl=false* 2>/dev/null | head -1)
    if [ -n "$m" ] && [ -d "$m/sata11-18072858035" ]; then echo "$m"; return 0; fi
    set -a; . "$HOME/.env"; set +a
    local cred
    enc() { printf '%s' "$1" | od -An -v -tx1 | tr -d ' \n' | sed 's/../%&/g'; }
    cred="$(enc "$WEBDAV_USER"):$(enc "$WEBDAV_PASS")"
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

cn_num() {
    case "$1" in
        一) echo 1;; 二) echo 2;; 三) echo 3;; 四) echo 4;; 五) echo 5;;
        六) echo 6;; 七) echo 7;; 八) echo 8;; 九) echo 9;; 十) echo 10;;
        十一) echo 11;; 十二) echo 12;; 十三) echo 13;; 十四) echo 14;;
        十五) echo 15;; *) echo "$1";;
    esac
}

has_video() {
    ls -1 "$1" 2>/dev/null | grep -qiE "\.($VIDEO_EXT)$"
}

cmd="${1:-}"; shift || true
case "$cmd" in
    list)
        [ $# -ge 1 ] || { echo "用法: $0 list <关键词>" >&2; exit 2; }
        m=$(ensure_mount) || { echo "[media] NAS 未挂载" >&2; exit 1; }
        search "$m/sata11-18072858035" "$*" | head -60
        ;;
    play)
        [ $# -ge 1 ] || { echo "用法: $0 play <关键词> [第X季] [第Y集] [--fullscreen]" >&2; exit 2; }
        fullscreen=0
        query=""
        for a in "$@"; do
            if [ "$a" = "--fullscreen" ]; then fullscreen=1; else query="${query:+$query }$a"; fi
        done
        [ -n "$query" ] || { echo "用法: $0 play <关键词> [--fullscreen]" >&2; exit 2; }
        m=$(ensure_mount) || { echo "[media] NAS 未挂载" >&2; exit 1; }
        root="$m/sata11-18072858035"

        # 第X季 / Sxx / 第Y集 / Exx
        season="" ep=""
        if [[ "$query" =~ 第([0-9]+|[一二三四五六七八九十]+)季 ]]; then season=$(cn_num "${BASH_REMATCH[1]}"); fi
        if [ -z "$season" ] && [[ "$query" =~ [Ss]([0-9]{1,2}) ]]; then season=$((10#${BASH_REMATCH[1]})); fi
        if [ -z "$season" ] && [[ "$query" =~ ([0-9]{1,2})季 ]]; then season=$((10#${BASH_REMATCH[1]})); fi
        if [[ "$query" =~ 第([0-9]+)集 ]]; then ep=$((10#${BASH_REMATCH[1]})); fi
        if [ -z "$ep" ] && [[ "$query" =~ [Ee]([0-9]{1,2}) ]]; then ep=$((10#${BASH_REMATCH[1]})); fi
        name=$(printf '%s' "$query" | sed -E 's/第[0-9一二三四五六七八九十]+季//g; s/[Ss][0-9]{1,2}([Ee][0-9]{1,2})?//g; s/[0-9]{1,2}季//g; s/第[0-9]+集//g; s/[Ee][0-9]{1,2}//g' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
        [ -n "$name" ] || name="$query"

        files=()
        # 优先匹配顶层剧集/电影目录（避免同名歌曲抢命中）
        dir="" exact="" sub=""
        for d in "$root"/*; do
            [ -d "$d" ] || continue
            bn=$(basename "$d")
            if [ "${bn,,}" = "${name,,}" ]; then exact="$d"; break; fi
            if [ -z "$sub" ] && [[ "${bn,,}" == *"${name,,}"* ]]; then sub="$d"; fi
        done
        dir="${exact:-$sub}"
        if [ -n "$dir" ]; then
            sdir=""
            if [ -n "$season" ]; then
                for x in "$dir"/*; do
                    [ -d "$x" ] || continue
                    bn=$(basename "$x")
                    if [[ "$bn" =~ ^[Ss]0?${season}([^0-9]|$) ]] || [[ "$bn" == *"第${season}季"* ]]; then sdir="$x"; break; fi
                done
            fi
            if [ -z "$sdir" ]; then
                if has_video "$dir"; then
                    sdir="$dir"
                else
                    while IFS= read -r x; do
                        [ -d "$x" ] && has_video "$x" && { sdir="$x"; break; }
                    done < <(find "$dir" -mindepth 1 -maxdepth 1 -type d | sort -V)
                fi
            fi
            if [ -n "$sdir" ]; then
                mapfile -t eps < <(ls -1 "$sdir" 2>/dev/null | grep -iE "\.($VIDEO_EXT)$" | sort -V)
                if [ ${#eps[@]} -gt 0 ]; then
                    pick_ep=""
                    if [ -n "$ep" ]; then
                        pick_ep=$(printf '%s\n' "${eps[@]}" | grep -iE "([Ee]0?${ep}([^0-9]|$)|第${ep}集)" | head -1)
                    fi
                    [ -n "$pick_ep" ] || pick_ep="${eps[0]}"
                    files=("$sdir/$pick_ep")
                fi
            fi
        fi

        if [ ${#files[@]} -eq 0 ]; then
            mapfile -t files < <(search "$root" "$name")
        fi
        [ ${#files[@]} -gt 0 ] || { echo "[media] 没找到: $query" >&2; exit 1; }
        if [ "${MEDIA_DRY:-0}" = "1" ]; then printf '%s\n' "${files[@]}"; exit 0; fi
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
            pick="${MEDIA_PICK:-0}"
            if [ "$pick" -gt 0 ] && [ "${#files[@]}" -gt "$pick" ]; then
                mapfile -t files < <(printf '%s\n' "${files[@]}" | shuf -n "$pick")
            fi
        fi
        args=(--no-video-title-show --play-and-exit --qt-continue=0)
        [ "$fullscreen" = "1" ] && args+=(--fullscreen)
        [ "$is_audio" = "1" ] && args+=(--no-video)
        setsid nohup vlc "${args[@]}" "${files[@]}" >/tmp/myagent-media.log 2>&1 &
        echo $! > "$PIDFILE"
        "$STATE" set media.vlc playing "$(cat "$PIDFILE")"
        # 播放期间检测摄像头遮挡；被挡住就暂停（CAM_BLOCK=0 可关闭）
        if [ "${CAM_BLOCK:-1}" != "0" ]; then
            ( "$(dirname "$0")/camera_block.sh" start "$(cat "$PIDFILE")" >/dev/null 2>&1 ) &
        fi
        if [ "$is_audio" = "1" ]; then
            # 音频列表：把 VLC 置前并确保播放列表可见
            cfg="$HOME/.config/vlc/vlc-qt-interface.conf"
            toggle=0
            grep -q '^playlist-visible=false' "$cfg" 2>/dev/null && toggle=1
            (
                sleep 1.2
                wmain=""
                for wid in $(xdotool search --name 'VLC media player' 2>/dev/null); do
                    eval "$(xdotool getwindowgeometry --shell "$wid" 2>/dev/null)"
                    [ "${WIDTH:-0}" -gt 200 ] && { wmain="$wid"; break; }
                done
                if [ -n "$wmain" ]; then
                    xdotool windowactivate --sync "$wmain" 2>/dev/null
                    [ "$toggle" = 1 ] && xdotool key ctrl+l 2>/dev/null
                fi
            ) >/dev/null 2>&1 &
        fi
        echo "播放 ${#files[@]} 个: $(basename "${files[0]}")"
        ;;
    pause|resume|toggle)
        pid="$(cat "$PIDFILE" 2>/dev/null || true)"
        [ -n "$pid" ] || pid=$("$STATE" get media.vlc 2>/dev/null | awk '{print $3}')
        if [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null; then
            echo "没有在播放"; exit 1
        fi
        export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/$(id -u)/bus}"
        status=$(dbus-send --session --print-reply --dest=org.mpris.MediaPlayer2.vlc /org/mpris/MediaPlayer2 \
            org.freedesktop.DBus.Properties.Get string:org.mpris.MediaPlayer2.Player string:PlaybackStatus 2>/dev/null \
            | sed -n 's/.*string "\(.*\)"/\1/p')
        want=""
        case "$cmd" in
            pause)  want="Paused" ;;
            resume) want="Playing" ;;
            toggle) [ "$status" = "Playing" ] && want="Paused" || want="Playing" ;;
        esac
        [ "$status" = "$want" ] || dbus-send --session --type=method_call --dest=org.mpris.MediaPlayer2.vlc /org/mpris/MediaPlayer2 \
            org.mpris.MediaPlayer2.Player.PlayPause >/dev/null 2>&1 || { echo "暂停/继续失败" >&2; exit 1; }
        if [ "$want" = "Paused" ]; then "$STATE" set media.vlc paused "$pid"; else "$STATE" set media.vlc playing "$pid"; fi
        wid=""
        for w in $(xdotool search --name 'VLC media player' 2>/dev/null); do
            eval "$(xdotool getwindowgeometry --shell "$w" 2>/dev/null)"
            [ "${WIDTH:-0}" -gt 200 ] && { wid="$w"; break; }
        done
        if [ "$want" = "Paused" ]; then
            [ -n "$wid" ] && xdotool windowminimize "$wid" 2>/dev/null || true
            echo "已暂停"
        else
            if [ -n "$wid" ]; then
                xdotool windowmap "$wid" 2>/dev/null || true
                xdotool windowactivate --sync "$wid" 2>/dev/null || true
            fi
            if [ "${CAM_BLOCK:-1}" != "0" ]; then
                cb="$("$(dirname "$0")/camera_block.sh" status 2>/dev/null || true)"
                case "$cb" in
                    *running*) ;;
                    *)
                        echo "=== resume-start $(date +%s) ===" >>/tmp/myagent-camera-block.log
                        ( "$(dirname "$0")/camera_block.sh" start "$pid" >/dev/null 2>&1 ) &
                        ;;
                esac
            fi
            echo "已继续"
        fi
        ;;
    next|prev|previous)
        pid="$(cat "$PIDFILE" 2>/dev/null || true)"
        [ -n "$pid" ] || pid=$("$STATE" get media.vlc 2>/dev/null | awk '{print $3}')
        if [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null; then
            echo "没有在播放"; exit 1
        fi
        export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/$(id -u)/bus}"
        if [ "$cmd" = "prev" ] || [ "$cmd" = "previous" ]; then
            method=Previous; label=上一首
        else
            method=Next; label=下一首
        fi
        dbus-send --session --type=method_call --dest=org.mpris.MediaPlayer2.vlc /org/mpris/MediaPlayer2 \
            "org.mpris.MediaPlayer2.Player.$method" >/dev/null 2>&1 || { echo "$label失败" >&2; exit 1; }
        echo "$label"
        ;;
    stop)
        pid="$(cat "$PIDFILE" 2>/dev/null || true)"
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true; echo "已停止"
        else echo "没有在播放"; fi
        "$STATE" set media.vlc stopped "${pid:-0}"
        rm -f "$PIDFILE"
        ( "$(dirname "$0")/camera_block.sh" stop >/dev/null 2>&1 || true ) &
        ;;
    status)
        pid="$(cat "$PIDFILE" 2>/dev/null || true)"
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/$(id -u)/bus}"
            st=$(dbus-send --session --print-reply --dest=org.mpris.MediaPlayer2.vlc /org/mpris/MediaPlayer2 \
                org.freedesktop.DBus.Properties.Get string:org.mpris.MediaPlayer2.Player string:PlaybackStatus 2>/dev/null \
                | sed -n 's/.*string "\(.*\)"/\1/p')
            if [ "$st" = "Paused" ]; then echo "已暂停 pid=$pid"; else echo "播放中 pid=$pid"; fi
        else echo "未播放"; fi
        ;;
    *) echo "用法: $0 play <关键词> [--fullscreen] | list <关键词> | stop | status" >&2; exit 2 ;;
esac
