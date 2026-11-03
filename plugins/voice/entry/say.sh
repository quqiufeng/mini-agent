#!/usr/bin/env bash
# @desc voice say
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/../tts.sh" "$@"
