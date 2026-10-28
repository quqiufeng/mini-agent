#!/usr/bin/env bash
# @desc 用 ICU uconv 生成 sherpa-onnx 拼音 KWS 关键词（无需 Python）
# @usage tools/kws_keywords.sh "你好星期五,程序员,退出程序员"
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/lua.sh" "$DIR/kws_keywords.lua" "$@"
