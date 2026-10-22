#!/usr/bin/env bash
# @desc 调用远程 /opt/my-agent/operator/tools/<name>.sh
# @usage tools/remote.sh <name> [args...]
# @rule 本机做不了的能力统一走这里；工具名只允许 [a-z0-9_]+
set -euo pipefail

HOST="${REMOTE_HOST:-quqiufeng@192.168.1.10}"
[ $# -ge 1 ] || { echo "用法: $0 <tool> [args...]" >&2; exit 2; }

NAME="$1"
shift
[[ "$NAME" =~ ^[a-z0-9_]+$ ]] || { echo "非法工具名: $NAME" >&2; exit 2; }

CMD="/opt/my-agent/operator/tools/${NAME}.sh"
for a in "$@"; do
  CMD+=" $(printf '%q' "$a")"
done

exec ssh -o BatchMode=yes -o ConnectTimeout=10 "$HOST" "$CMD"
