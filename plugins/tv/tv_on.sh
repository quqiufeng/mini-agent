#!/usr/bin/env bash
# @desc 打开电视：ADB 唤醒并切到 Android 电视界面（默认）；也可切 HDMI 输入
# @usage plugins/tv/tv_on.sh                 # 唤醒 + Android 首页
#        plugins/tv/tv_on.sh --off           # 待机/关闭电视
#        plugins/tv/tv_on.sh --desktop       # 电视开机 + 切 HDMI3（显示本机桌面）
#        plugins/tv/tv_on.sh --input hdmi3   # 切 HDMI3（本机桌面）
#        plugins/tv/tv_on.sh --input tv      # 回 Android 首页
# @rule 用户说“打开电视/开电视”→ plugins/tv/tv_on.sh；说“切回 HDMI3”→ plugins/tv/tv_on.sh --input hdmi3
set -uo pipefail
SERIAL="${TV_SERIAL:-192.168.1.110:5555}"
ADB=(adb -s "$SERIAL")

"${ADB[@]}" connect "$SERIAL" >/dev/null 2>&1 || true

if [ "${1:-}" = "--desktop" ]; then
  # 打开桌面：唤醒电视 + 切 HDMI3（本机桌面）
  "${ADB[@]}" shell input keyevent 224
  sleep 1
  "${ADB[@]}" shell input keyevent 245
  sleep 1
  export DISPLAY="${DISPLAY:-:0}" XAUTHORITY="${XAUTHORITY:-/tmp/xauth_pLarOv}"
  xset dpms force on >/dev/null 2>&1 || true
  echo "已打开桌面：电视开机 + HDMI3"
  exit 0
fi
if [ "${1:-}" = "--off" ]; then
  "${ADB[@]}" shell input keyevent 26
  sleep 1
  echo "已发送待机键（电视进入待机/假关机）"
  exit 0
fi
if [ "${1:-}" = "--input" ]; then
  case "${2:-}" in
    tv)    "${ADB[@]}" shell input keyevent 3 ;;
    hdmi1) "${ADB[@]}" shell input keyevent 243 ;;
    hdmi2) "${ADB[@]}" shell input keyevent 244 ;;
    hdmi3) "${ADB[@]}" shell input keyevent 245 ;;
    *) echo "用法: $0 --input tv|hdmi1|hdmi2|hdmi3" >&2; exit 2 ;;
  esac
  exit 0
fi

"${ADB[@]}" shell input keyevent 224
sleep 1
"${ADB[@]}" shell input keyevent 3
sleep 1.5
if ! "${ADB[@]}" exec-out screencap -p > /tmp/tv_on_check.png 2>/dev/null; then
  echo "[tv_on] 截屏失败（ADB 未连接？）" >&2; exit 1
fi
size=$(stat -c%s /tmp/tv_on_check.png 2>/dev/null || echo 0)
if [ "$size" -lt 1000 ]; then
  # 仍在 HDMI 输入，再发一次 HOME
  "${ADB[@]}" shell input keyevent 3
  sleep 1.5
  "${ADB[@]}" exec-out screencap -p > /tmp/tv_on_check.png 2>/dev/null || true
fi
echo "电视已唤醒（截图 /tmp/tv_on_check.png，$(stat -c%s /tmp/tv_on_check.png 2>/dev/null || echo 0) 字节）"
