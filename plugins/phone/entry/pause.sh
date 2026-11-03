#!/usr/bin/env bash
# @desc phone pause
# @usage plugins/phone/entry/pause.sh
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/../music.sh" pause "$@"
