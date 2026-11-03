#!/usr/bin/env bash
# @desc wechat start
# @usage plugins/wechat/entry/start.sh
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/../wechat.sh" start "$@"
