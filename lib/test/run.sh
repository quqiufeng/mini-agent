#!/usr/bin/env bash
# @desc 本地回归：state/device/session/contract
set -euo pipefail
DIR="$(cd "$(dirname "$0")/../.." && pwd)"
for t in state device session contract e2e; do
    echo "== $t"
    "$DIR/tools/lua.sh" "$DIR/lib/test/${t}_test.lua" 2>/dev/null
done
"$DIR/tools/plugin.sh" validate
echo "all tests passed"
