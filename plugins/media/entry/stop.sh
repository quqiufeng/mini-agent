#!/usr/bin/env bash
# @desc media stop
# @usage plugins/media/entry/stop.sh ...
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/../media.sh" stop "$@"
