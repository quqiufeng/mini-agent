#!/usr/bin/env bash
# @desc 本地联网搜索：调用 DeepSeek Search API，输出标题/链接/摘要
# @usage tools/deepseek_search.sh "关键词" [count]
# @rule 本地自带搜索；count 默认 5
set -euo pipefail

[ $# -ge 1 ] || { echo "用法: $0 \"关键词\" [count]" >&2; exit 2; }
QUERY="$1"
COUNT="${2:-5}"

python3 - "$QUERY" "$COUNT" <<'PY'
import json
import os
import sys

import requests

query, count = sys.argv[1], int(sys.argv[2])
key_path = os.path.expanduser("~/.local/share/opencode/auth.json")
with open(key_path, encoding="utf-8") as f:
    key = json.load(f)["deepseek"]["key"]

r = requests.post(
    "https://api.deepseek.com/v1/tools/search",
    headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
    json={"query": query, "count": max(1, min(count, 50)), "need_content": False},
    timeout=30,
)
r.raise_for_status()
for x in r.json().get("results", []):
    print(f"[{x.get('rerank_score', 0):.2f}] {x.get('title', '')}")
    print(x.get("url", ""))
    print(x.get("summary", "").strip())
    print()
PY
