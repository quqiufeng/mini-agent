#!/usr/bin/env bash
# @desc [已停用] 远程 /opt/my-agent 已移除 phone_music.sh（汽水音乐+音频转发）
# @usage tools/phone_music.sh play|stop
set -uo pipefail
echo "[phone_music] 远程已无此能力（phone_music.sh 不存在）；手机操作改用 tools/remote.sh phone ..." >&2
exit 1
