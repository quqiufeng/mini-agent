#!/usr/bin/env bash
# @desc system alarm
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/../alarm.sh" ""
