#!/usr/bin/env bash
# @desc tv play
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/../tv_play.sh" "$@"
