#!/usr/bin/env bash
# @desc voice kws
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/../kws_keywords.sh" "$@"
