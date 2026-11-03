#!/usr/bin/env bash
# @desc camera start <media_pid>
# @usage plugins/camera/entry/start.sh <media_pid>
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/../camera_block.sh" start "$@"
