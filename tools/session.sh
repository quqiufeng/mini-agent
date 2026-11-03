#!/usr/bin/env bash
# @desc 会话模式薄入口：enter/get/touch/exit/route（kvcache + 插件 context/defaults）
# @usage tools/session.sh enter <id> <plugin> [--ttl N] [--source S] [--init k=v] | get <id> | touch <id> [ttl] | exit <id>
# @rule 实现见 lib/session.lua；存储用 lib/ffi/kv.lua（cache.bin）
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
KV_DIR="${MYAGENT_KV_DIR:-}"
if [ -z "$KV_DIR" ] && [ -n "${MYAGENT_STATE_DIR:-}" ]; then KV_DIR="${MYAGENT_STATE_DIR}.kv"; fi
KV_DIR="${KV_DIR:-$HOME/.myagent/kv}"
mkdir -p "$KV_DIR"
exec flock "$KV_DIR/.writer.lock" "$DIR/lua.sh" "$DIR/../lib/session.lua" "$@"
