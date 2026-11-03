#!/usr/bin/env bash
# @desc 会话模式薄入口：enter/get/touch/exit/route（kvcache 后端）
# @usage tools/session.sh enter <id> <plugin> [--ttl N] [--source S] [--init k=v] | get <id> | touch <id> [ttl] | exit <id>
# @rule 实现见 lib/session.lua；存储用 lib/ffi/kv.lua（cache.bin）
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/lua.sh" "$DIR/../lib/session.lua" "$@"
