#!/usr/bin/env bash
# @desc system volume
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/../volume.sh" ""
