#!/usr/bin/env bash
# @desc media list
# @usage plugins/media/entry/list.sh ...
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/../media.sh" list "$@"
