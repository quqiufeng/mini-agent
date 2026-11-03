#!/usr/bin/env bash
# @desc 设备层薄入口：注册/探测/lease/状态（实现见 lib/device.lua）
# @usage tools/device.sh status|probe|show|state <id>|acquire <id> <purpose> [ttl] [pid]|release <id> [pid]|lease <id>|tidy
# @rule 设备归属用 lease，不再直接依赖 /tmp pid 文件
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/lua.sh" "$DIR/../lib/device.lua" "$@"
