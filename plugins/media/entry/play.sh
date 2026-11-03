#!/usr/bin/env bash
# @desc media play
# @usage plugins/media/entry/play.sh ...
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/../media.sh" play "$@"
