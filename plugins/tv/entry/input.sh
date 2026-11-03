#!/usr/bin/env bash
# @desc tv input
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/../tv_on.sh" --input "$@"
