#!/usr/bin/env bash
# @desc 硬件冒烟：VLC 播放/暂停/停止 + lease、摄像头 lease、小音箱状态、设备状态
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
say() { printf '%-24s %s\n' "$1" "$2"; }
CAM_BLOCK=0 plugins/media/media.sh play 周杰伦 >/dev/null 2>&1
sleep 3
say "active" "$(tools/state.sh active-media || echo none)"
say "media.vlc" "$(tools/state.sh get media.vlc | awk '{print $1}')"
say "lease vlc" "$(tools/device.sh lease vlc || echo free)"
vp=$(tools/state.sh get media.vlc | awk '{print $3}')
plugins/camera/camera_block.sh start "$vp" >/dev/null 2>&1
sleep 1
say "lease camera" "$(tools/device.sh lease camera || echo free)"
plugins/camera/camera_block.sh stop >/dev/null 2>&1
tools/media_ctl.sh playpause >/dev/null 2>&1; sleep 0.3
say "paused" "$(tools/state.sh get media.vlc | awk '{print $1}')"
tools/media_ctl.sh playpause >/dev/null 2>&1; sleep 0.3
say "resumed" "$(tools/state.sh get media.vlc | awk '{print $1}')"
say "speaker" "$(tools/state.sh get speaker | awk '{print $1}')"
tools/media_ctl.sh stop >/dev/null 2>&1; sleep 0.3
say "stopped" "$(tools/state.sh get media.vlc | awk '{print $1}')"
say "lease after" "$(tools/device.sh lease vlc || echo free)"
say "camera after" "$(tools/device.sh lease camera || echo free)"
say "phone" "$(plugins/phone/music.sh status 2>&1 | head -1)"
say "wechat" "$(plugins/wechat/wechat.sh status 2>&1 | head -1)"
