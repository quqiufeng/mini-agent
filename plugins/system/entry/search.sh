#!/usr/bin/env bash
# @desc system search
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/../google_search.sh" ""
