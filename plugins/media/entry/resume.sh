#!/usr/bin/env bash
# @desc media resume
# @usage plugins/media/entry/resume.sh ...
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/../media.sh" resume "$@"
