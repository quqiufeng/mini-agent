#!/usr/bin/env bash
# @desc system deepseek
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/../deepseek_search.sh" ""
