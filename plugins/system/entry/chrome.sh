#!/usr/bin/env bash
# @desc system chrome
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/../chrome.sh" ""
