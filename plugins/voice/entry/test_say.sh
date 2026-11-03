#!/usr/bin/env bash
# @desc voice test_say
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/../test_say.sh" "$@"
