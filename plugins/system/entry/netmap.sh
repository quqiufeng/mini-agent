#!/usr/bin/env bash
# @desc system netmap
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/../netmap.sh" ""
