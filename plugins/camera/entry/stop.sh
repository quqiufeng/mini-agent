#!/usr/bin/env bash
# @desc camera stop
# @usage plugins/camera/entry/stop.sh
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/../camera_block.sh" stop "$@"
