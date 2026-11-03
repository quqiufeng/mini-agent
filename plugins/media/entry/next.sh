#!/usr/bin/env bash
# @desc media next
# @usage plugins/media/entry/next.sh ...
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/../media.sh" next "$@"
