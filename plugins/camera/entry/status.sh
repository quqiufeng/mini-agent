#!/usr/bin/env bash
# @desc camera status
# @usage plugins/camera/entry/status.sh
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/../camera_block.sh" status "$@"
