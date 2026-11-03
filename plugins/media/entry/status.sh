#!/usr/bin/env bash
# @desc media status
# @usage plugins/media/entry/status.sh ...
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/../media.sh" status "$@"
