#!/usr/bin/env bash
# @desc 检查本地 my-agent 依赖、大脑、远程工具、手机和 Chrome CDP
# @usage tools/doctor.sh
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

check_py() {
  if python3 -c "import $1" >/dev/null 2>&1; then
    echo "OK   py   $1"
  else
    echo "FAIL py   $1"
    fail=1
  fi
}

echo "== 命令 =="
for c in tmux opencode curl python3 adb scrcpy google-chrome xclip scrot; do
  check_cmd "$c"
done

echo
echo "== Python 模块 =="
for m in requests numpy websocket; do
  check_py "$m"
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
HOST="${REMOTE_HOST:-quqiufeng@192.168.1.10}"
if ssh -o BatchMode=yes -o ConnectTimeout=5 "$HOST" 'test -x /opt/my-agent/operator/tools/netmap.sh' >/dev/null 2>&1; then
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
