#!/usr/bin/env bash
# @desc 检查本地 my-agent 依赖、大脑、远程工具、手机和 Chrome CDP
# @usage plugins/system/doctor.sh
# @rule 只读检查，不做修改；缺依赖时给出失败原因
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
PORT="${AGENT_PORT:-4097}"
CDP="${CDP_PORT:-9222}"
fail=0

check_cmd() {
  if command -v "$1" >/dev/null 2>&1; then
    echo "OK   cmd  $1"
  else
    echo "FAIL cmd  $1"
    fail=1
  fi
}

check_lib() {
  local out
  out=$(ldconfig -p 2>/dev/null || true)
  case "$out" in
    *"$1"*) echo "OK   lib  $1" ;;
    *) echo "FAIL lib  $1"; fail=1 ;;
  esac
}

echo "== 命令 =="
for c in tmux opencode curl adb scrcpy google-chrome xclip scrot ffmpeg parec; do
  check_cmd "$c"
done

echo
echo "== LuaJIT FFI 库 =="
for l in libcurl.so libjson-c.so libX11.so libfftw3.so; do
  check_lib "$l"
done

echo
echo "== 本地大脑 =="
if curl --max-time 2 -sf "http://127.0.0.1:$PORT/global/health" >/dev/null 2>&1; then
  echo "OK   brain :$PORT"
else
  echo "FAIL brain :$PORT（先运行 ./start.sh --bg）"
  fail=1
fi
if pgrep -f "opencode[ ]attach http://127.0.0.1:$PORT" >/dev/null 2>&1; then
  echo "OK   tui attach"
else
  echo "WARN tui attach 未运行"
fi

echo
echo "== 远程 =="
_host=$("$DIR/../../tools/device.sh" ip computer 2>/dev/null || true)
HOST="${REMOTE_HOST:-quqiufeng@${_host:-192.168.1.10}}"
if ssh -o BatchMode=yes -o ConnectTimeout=5 "$HOST" 'test -x /opt/my-agent/operator/plugins/system/netmap.sh' >/dev/null 2>&1; then
  echo "OK   ssh $HOST + 远程工具存在"
else
  echo "FAIL 远程（检查 SSH/REMOTE_HOST）"
  fail=1
fi

echo
echo "== 手机 / ADB =="
adb devices -l 2>/dev/null | sed 's/^/     /'

echo
echo "== Chrome CDP =="
if curl --max-time 2 -sf "http://127.0.0.1:$CDP/json/version" >/dev/null 2>&1; then
  echo "OK   CDP :$CDP"
else
  echo "WARN CDP :$CDP 未启动（google_search.sh 会按需启动）"
fi

echo
if [ "$fail" -eq 0 ]; then
  echo "doctor: OK"
else
  echo "doctor: FAIL"
fi
exit "$fail"
