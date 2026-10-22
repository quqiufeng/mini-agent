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
#   HOST=quqiufeng@192.168.1.10
#   WINDOW_ID=<可选，默认自动找 qterminal>
#   TAB_X=170 TAB_Y=32 PROMPT=继续
#   DISPLAY_VALUE=:0 XAUTH_VALUE=<可选，默认从 pcmanfm-qt 发现>
set -uo pipefail

HOST="${HOST:-quqiufeng@192.168.1.10}"
WINDOW_ID="${WINDOW_ID:-}"
TAB_X="${TAB_X:-170}"
TAB_Y="${TAB_Y:-32}"
PROMPT="${1:-${PROMPT:-继续}}"
DISPLAY_VALUE="${DISPLAY_VALUE:-:0}"
XAUTH_VALUE="${XAUTH_VALUE:-}"

[[ "$TAB_X" =~ ^[0-9]+$ ]] || { echo "非法 TAB_X: $TAB_X" >&2; exit 2; }
[[ "$TAB_Y" =~ ^[0-9]+$ ]] || { echo "非法 TAB_Y: $TAB_Y" >&2; exit 2; }
[[ -z "$WINDOW_ID" || "$WINDOW_ID" =~ ^[0-9]+$ ]] || { echo "非法 WINDOW_ID: $WINDOW_ID" >&2; exit 2; }
[[ "$DISPLAY_VALUE" =~ ^:[0-9]+$ ]] || { echo "非法 DISPLAY: $DISPLAY_VALUE" >&2; exit 2; }
[[ -z "$XAUTH_VALUE" || "$XAUTH_VALUE" =~ ^/[A-Za-z0-9._/-]+$ ]] || { echo "非法 XAUTHORITY: $XAUTH_VALUE" >&2; exit 2; }

LOG_DIR="$HOME/my-agent/logs"
LOG_FILE="$LOG_DIR/remote_opencode_retry.log"
mkdir -p "$LOG_DIR"

log() {
  echo "[$(date '+%F %T')] $*" >> "$LOG_FILE"
}

REMOTE_CMD="
set -e
export DISPLAY=$DISPLAY_VALUE
if [ -n '$XAUTH_VALUE' ]; then
  export XAUTHORITY='$XAUTH_VALUE'
else
  P=\$(pgrep -x pcmanfm-qt | head -1)
  if [ -n \"\$P\" ]; then
    export XAUTHORITY=\$(tr '\\0' '\\n' < /proc/\$P/environ | sed -n 's/^XAUTHORITY=//p' | head -1)
  fi
fi
WID='$WINDOW_ID'
if [ -z \"\$WID\" ]; then
  WID=\$(wmctrl -lx | awk 'tolower(\$0)~/qterminal/{print \$1; exit}')
fi
[ -n \"\$WID\" ] || { echo 'no qterminal window' >&2; exit 1; }
PREV=\$(xdotool getactivewindow 2>/dev/null || true)
xclip -selection clipboard -l 1
xdotool windowactivate --sync \"\$WID\"
eval \$(xdotool getwindowgeometry --shell \"\$WID\")
xdotool mousemove \$((X + $TAB_X)) \$((Y + $TAB_Y)) click 1
sleep 0.4
xdotool key --clearmodifiers ctrl+shift+v
sleep 0.4
xdotool key Return
TITLE=\$(xdotool getwindowname \"\$WID\" 2>/dev/null || true)
if [ -n \"\$PREV\" ]; then xdotool windowactivate \"\$PREV\" 2>/dev/null || true; fi
echo \"tab=\$TITLE\"
"

if OUT=$(printf '%s' "$PROMPT" | timeout 20 ssh -o BatchMode=yes -o ConnectTimeout=8 "$HOST" "$REMOTE_CMD" 2>/dev/null); then
  log "sent $PROMPT ($OUT)"
  echo "sent $PROMPT"
else
  log "send failed"
  echo "send failed" >&2
  exit 1
fi
