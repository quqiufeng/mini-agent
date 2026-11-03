#!/usr/bin/env bash
# @desc phone resume
# @usage plugins/phone/entry/resume.sh
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/../music.sh" resume "$@"
