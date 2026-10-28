#!/usr/bin/env bash
# @desc 音量控制兼容入口：统一交给 devctl volume
# @usage tools/volume_ctl.sh up | down | mute | set <0-153> | status
# @rule GUI/旧脚本用这里；具体实现仍在 volume.sh
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/devctl.sh" volume "$@"
