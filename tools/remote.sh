#!/usr/bin/env bash
# @desc 调用远程 /opt/my-agent/operator/tools/<name>.sh
# @usage tools/remote.sh [--env K=V]... <name> [args...]
# @rule 本机做不了的能力统一走这里；工具名只允许 [a-z0-9_]+
set -euo pipefail

HOST="${REMOTE_HOST:-quqiufeng@192.168.1.10}"
ENV_ARGS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --env)
      [ $# -ge 2 ] || { echo "用法: $0 [--env K=V]... <tool> [args...]" >&2; exit 2; }
      [[ "$2" == *=* ]] || { echo "非法环境变量: $2" >&2; exit 2; }
      ENV_ARGS+=("$2")
      shift 2
      ;;
    --)
      shift
      break
      ;;
    *)
      break
      ;;
  esac
done

[ $# -ge 1 ] || { echo "用法: $0 [--env K=V]... <tool> [args...]" >&2; exit 2; }
NAME="$1"
shift
[[ "$NAME" =~ ^[a-z0-9_]+$ ]] || { echo "非法工具名: $NAME" >&2; exit 2; }

CMD=""
for e in "${ENV_ARGS[@]}"; do
  CMD+="$(printf '%q' "$e") "
done
CMD+="/opt/my-agent/operator/tools/${NAME}.sh"
for a in "$@"; do
  CMD+=" $(printf '%q' "$a")"
done

exec ssh -o BatchMode=yes -o ConnectTimeout=10 "$HOST" "$CMD"
