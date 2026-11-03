#!/usr/bin/env bash
# @desc phone status
# @usage plugins/phone/entry/status.sh
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/../music.sh" status "$@"
