#!/usr/bin/env bash
# @desc system ocr
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/../ocr.sh" ""
