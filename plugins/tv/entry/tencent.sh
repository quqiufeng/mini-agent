#!/usr/bin/env bash
# @desc tv tencent
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/../tencent.sh" "$@"
