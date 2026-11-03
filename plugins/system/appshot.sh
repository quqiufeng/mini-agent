#!/usr/bin/env bash
# @desc 抓当前“正在跑的应用”的界面，给语音 GUI 右侧预览
# @usage plugins/system/appshot.sh [输出.png]
# @rule 手机汽水音乐 → 手机截图；电视操作 → 电视 adb 截图；VLC/NAS 播放 → VLC 窗口截图
set -uo pipefail
OUT="${1:-/tmp/myagent_preview.png}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export DISPLAY="${DISPLAY:-:0}"
export XAUTHORITY="${XAUTHORITY:-/tmp/xauth_pLarOv}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

# 1) 手机汽水音乐（state.media.phone 在播/暂停，scrcpy 存活）
line=$("$(cd "$(dirname "$0")/../.." && pwd)/tools/state.sh" get media.phone 2>/dev/null || true)
mpid=$(printf '%s\n' "$line" | awk '{print $3}')
mser=$(printf '%s\n' "$line" | awk '{print $4}')
case "$line" in
    playing*|paused*)
        if [ -n "$mpid" ] && kill -0 "$mpid" 2>/dev/null && [ -n "$mser" ]; then
            serial="$mser"
            adb -s "$serial" exec-out screencap -p > "$OUT.tmp" 2>/dev/null && mv "$OUT.tmp" "$OUT" && echo "phone"; exit 0
        fi
        ;;
esac

# 2) 本机 VLC（NAS 音乐/视频）——窗口几何走 LuaJIT FFI/libxdo
read -r vx vy vw vh < <("$(cd "$(dirname "$0")/../.." && pwd)/tools/lua.sh" "$(cd "$(dirname "$0")/../.." && pwd)/tools/winctl.lua" geom vlc 2>/dev/null || true)
if [ -n "${vw:-}" ] && [ "${vw:-0}" -gt 100 ]; then
    scrot -o -a "${vx},${vy},${vw},${vh}" "$OUT" 2>/dev/null && echo "vlc"; exit 0
fi

# 3) 电视（醒着且 adb 可达）
_tv=$("$ROOT/tools/device.sh" ip tv 2>/dev/null || true)
TV="${TV_SERIAL:-${_tv:+$_tv:5555}}"
TV="${TV:-192.168.1.110:5555}"
if adb -s "$TV" shell 'dumpsys power | grep -m1 mWakefulness' 2>/dev/null | grep -q Awake; then
    adb -s "$TV" exec-out screencap -p > "$OUT.tmp" 2>/dev/null
    if [ -s "$OUT.tmp" ] && [ "$(stat -c%s "$OUT.tmp")" -gt 1000 ]; then mv "$OUT.tmp" "$OUT"; echo "tv"; exit 0; fi
    rm -f "$OUT.tmp"
fi

echo "none"; exit 3
