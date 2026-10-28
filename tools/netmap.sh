#!/usr/bin/env bash
# @desc 扫描局域网：UDP 触发 ARP + 端口探测，生成 NETWORK.local.md / devices.local.json / devices.local.env
# @usage tools/netmap.sh scan [CIDR] | show | sources
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
export NETMAP_OUT_DIR="${NETMAP_OUT_DIR:-$(cd "$DIR/.." && pwd)}"
exec "$DIR/lua.sh" "$DIR/netmap.lua" "$@"
