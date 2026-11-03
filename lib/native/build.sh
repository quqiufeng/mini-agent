#!/usr/bin/env bash
# @desc 从 /opt/my_db_src 构建 libmydb.so（kvcache）并放到 lib/native/
# @usage lib/native/build.sh
# @rule 只构建 libmydb.so；源码在 MYDB_SRC（默认 /opt/my_db_src）
set -euo pipefail
SRC="${MYDB_SRC:-/opt/my_db_src}"
DIR="$(cd "$(dirname "$0")" && pwd)"
make -C "$SRC" libmydb.so
cp "$SRC/libmydb.so" "$DIR/libmydb.so"
echo "built $DIR/libmydb.so"
