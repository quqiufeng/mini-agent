#!/usr/bin/env bash
# @desc 列出本地工具及说明
# @usage tools/list.sh
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
for f in "$DIR"/*.sh; do
  name="$(basename "$f")"
  case "$name" in list.sh|_*) continue ;; esac
  desc="$(sed -n 's/^# *@desc *//p' "$f" | head -1)"
  printf '%-20s %s\n' "$name" "${desc:-}"
done
