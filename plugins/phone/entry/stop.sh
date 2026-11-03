#!/usr/bin/env bash
# @desc phone stop
# @usage plugins/phone/entry/stop.sh
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/../music.sh" stop "$@"
