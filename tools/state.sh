#!/usr/bin/env bash
# @desc 统一状态层薄入口：KV 单一源，镜像 ~/.myagent/state/<key>
# @usage tools/state.sh set <key> <value> [extra...] | get <key> | show | active-media | any-playing | playing <key> | tidy | stale <key> <秒>
# @rule 实现见 lib/state.lua；状态唯一来源
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
KV_DIR="${MYAGENT_KV_DIR:-}"
if [ -z "$KV_DIR" ] && [ -n "${MYAGENT_STATE_DIR:-}" ]; then KV_DIR="${MYAGENT_STATE_DIR}.kv"; fi
KV_DIR="${KV_DIR:-$HOME/.myagent/kv}"
mkdir -p "$KV_DIR"
exec flock "$KV_DIR/.writer.lock" "$DIR/lua.sh" "$DIR/../lib/state.lua" "$@"
