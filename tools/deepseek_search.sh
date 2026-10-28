#!/usr/bin/env bash
# @desc DeepSeek 搜索/抓取（Search & Fetch API）：实时资料检索、抓单页 Markdown
# @usage tools/deepseek_search.sh "查询" [--count N] [--content] [--json]
#        tools/deepseek_search.sh fetch <url> [--max-chars N] [--json]
# @rule 用户说“ai搜索/智能搜索/搜索/搜一下/查一下/最新资料/网上搜/找资料 + 查询词”→ 用本工具；纯常识/算数不要搜；结果附来源 URL。
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/lua.sh" "$DIR/deepseek_search.lua" "$@"
