#!/usr/bin/env bash
# @desc wechat stop
# @usage plugins/wechat/entry/stop.sh
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/../wechat.sh" stop "$@"
