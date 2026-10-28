#!/usr/bin/env bash
# @desc 局域网探测：UDP 触发 ARP / TCP 端口扫描（LuaJIT FFI + libc socket）
# @usage tools/netscan.sh udp <prefix> | tcp <prefix> <port> [timeout_ms]
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/lua.sh" "$DIR/netscan.lua" "$@"
