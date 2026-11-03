#!/usr/bin/env bash
# @desc 局域网探测：UDP 触发 ARP / TCP 端口扫描（LuaJIT FFI + libc socket）
# @usage plugins/system/netscan.sh udp <prefix> | tcp <prefix> <port> [timeout_ms]
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/../.." && pwd)"
exec "$ROOT/tools/lua.sh" "$DIR/netscan.lua" "$@"
