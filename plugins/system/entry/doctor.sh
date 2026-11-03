#!/usr/bin/env bash
# @desc system doctor
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/../doctor.sh" ""
