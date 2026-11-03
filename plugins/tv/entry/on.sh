#!/usr/bin/env bash
# @desc tv on
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/../tv_on.sh" "$@"
