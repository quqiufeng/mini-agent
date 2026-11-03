#!/usr/bin/env bash
# @desc 设备层薄入口：注册/探测/lease/状态（实现见 lib/device.lua）
# @usage tools/device.sh status|refresh|probe|show|ip|serial|sink|source|json|state <id>|acquire <id> <purpose> [ttl] [pid]|release <id> [pid]|lease <id>|tidy
# @rule 设备归属用 lease，不再直接依赖 /tmp pid 文件
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
KV_DIR="${MYAGENT_KV_DIR:-}"
if [ -z "$KV_DIR" ] && [ -n "${MYAGENT_STATE_DIR:-}" ]; then KV_DIR="${MYAGENT_STATE_DIR}.kv"; fi
KV_DIR="${KV_DIR:-$HOME/.myagent/kv}"
mkdir -p "$KV_DIR"
exec flock "$KV_DIR/.writer.lock" "$DIR/lua.sh" "$DIR/../lib/device.lua" "$@"
