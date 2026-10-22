#!/usr/bin/env bash
# remote_opencode_retry.sh — 单次向远程 opencode 第一个 tab 发送“继续”
#
# 由 opencode 每 5 分钟调用一次，例如：
#   sleep 300
#   ~/my-agent/tools/remote_opencode_retry.sh
#
# 脚本本身不 sleep、不循环；只做一次发送。
#
# 用法:
#   ~/my-agent/tools/remote_opencode_retry.sh ["文本"]
#   日志: ~/my-agent/logs/remote_opencode_retry.log
#
# 可调环境变量:
#   HOST=quqiufeng@192.168.1.10 WINDOW_ID=81788934
#   TAB_X=170 TAB_Y=86 PROMPT=继续
#   DISPLAY_VALUE=:0 XAUTH_VALUE=/tmp/xauth_zmBuaZ
set -uo pipefail

HOST="${HOST:-quqiufeng@192.168.1.10}"
WINDOW_ID="${WINDOW_ID:-81788934}"
TAB_X="${TAB_X:-170}"
TAB_Y="${TAB_Y:-86}"
PROMPT="${1:-${PROMPT:-继续}}"
DISPLAY_VALUE="${DISPLAY_VALUE:-:0}"
XAUTH_VALUE="${XAUTH_VALUE:-/tmp/xauth_zmBuaZ}"

LOG_DIR="$HOME/my-agent/logs"
LOG_FILE="$LOG_DIR/remote_opencode_retry.log"
mkdir -p "$LOG_DIR"

log() {
  echo "[$(date '+%F %T')] $*" >> "$LOG_FILE"
}

if timeout 20 ssh -o BatchMode=yes -o ConnectTimeout=8 "$HOST" "
  set -e
  export DISPLAY=$DISPLAY_VALUE XAUTHORITY=$XAUTH_VALUE
  PREV=\$(xdotool getactivewindow 2>/dev/null || true)
  printf '%s' '$PROMPT' | xclip -selection clipboard -l 1 >/dev/null 2>&1
  xdotool windowactivate --sync $WINDOW_ID 2>/dev/null
  xdotool mousemove $TAB_X $TAB_Y click 1
  sleep 0.4
  xdotool key --clearmodifiers ctrl+shift+v
  sleep 0.4
  xdotool key Return
  if [ -n \"\$PREV\" ]; then xdotool windowactivate \"\$PREV\" 2>/dev/null || true; fi
" 2>/dev/null; then
  log "sent $PROMPT"
  echo "sent $PROMPT"
else
  log "send failed"
  echo "send failed" >&2
  exit 1
fi
