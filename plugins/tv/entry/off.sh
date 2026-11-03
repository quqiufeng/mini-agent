#!/usr/bin/env bash
# @desc tv off
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/../tv_on.sh" --off "$@"
