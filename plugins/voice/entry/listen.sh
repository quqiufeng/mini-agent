#!/usr/bin/env bash
# @desc voice listen
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/../asr.sh" "$@"
