#!/usr/bin/env bash
# @desc media toggle
# @usage plugins/media/entry/toggle.sh ...
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/../media.sh" toggle "$@"
