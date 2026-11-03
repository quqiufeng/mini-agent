#!/usr/bin/env bash
# @desc wechat status
# @usage plugins/wechat/entry/status.sh
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/../wechat.sh" status "$@"
