#!/usr/bin/env bash
# @desc phone play
# @usage plugins/phone/entry/play.sh
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/../music.sh" play "$@"
