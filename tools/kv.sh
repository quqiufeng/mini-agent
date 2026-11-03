#!/usr/bin/env bash
# @desc kvcache 维护入口：check/compact/rebuild
# @usage tools/kv.sh check|compact|rebuild
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
KV_DIR="${MYAGENT_KV_DIR:-}"
if [ -z "$KV_DIR" ] && [ -n "${MYAGENT_STATE_DIR:-}" ]; then KV_DIR="${MYAGENT_STATE_DIR}.kv"; fi
KV_DIR="${KV_DIR:-$HOME/.myagent/kv}"
mkdir -p "$KV_DIR"
exec flock "$KV_DIR/.writer.lock" "$DIR/lua.sh" "$DIR/../lib/kv_maintenance.lua" "$@"
