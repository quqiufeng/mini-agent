#!/usr/bin/env bash
# @desc 打开远程桌面：电视开机+切 HDMI3（显示本机桌面），再在本机打开主电脑的 noVNC
# @usage tools/remote_desktop.sh
# @rule 说“打开远程桌面/看主电脑”→ tools/remote_desktop.sh
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
export DISPLAY="${DISPLAY:-:0}"
export XAUTHORITY="${XAUTHORITY:-/tmp/xauth_pLarOv}"
"$DIR/tv_on.sh" --desktop
setsid nohup "$HOME/.local/bin/open-mainpc-vnc.sh" >/tmp/myagent-remote-desktop.log 2>&1 &
sleep 2
echo "远程桌面已打开（HDMI3 + noVNC）"
