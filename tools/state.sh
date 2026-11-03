#!/usr/bin/env bash
# @desc 统一状态层薄入口：读写 ~/.myagent/state/<key>
# @usage tools/state.sh set <key> <value> [extra...] | get <key> | show | active-media | any-playing | playing <key> | tidy | stale <key> <秒>
# @rule 实现见 lib/state.lua；状态唯一来源
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/lua.sh" "$DIR/../lib/state.lua" "$@"
