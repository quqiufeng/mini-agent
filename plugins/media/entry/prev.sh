#!/usr/bin/env bash
# @desc media prev
# @usage plugins/media/entry/prev.sh ...
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/../media.sh" prev "$@"
