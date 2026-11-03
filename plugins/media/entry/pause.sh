#!/usr/bin/env bash
# @desc media pause
# @usage plugins/media/entry/pause.sh ...
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/../media.sh" pause "$@"
