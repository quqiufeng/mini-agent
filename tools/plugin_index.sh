#!/usr/bin/env bash
# @desc 扫描 plugins/*/plugin.json + entry，生成 plugins/TOOLS.md
# @usage tools/plugin_index.sh
# @rule 只读 manifest，不改插件
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/plugins/TOOLS.md"
{
    echo "# Plugins"
    echo
    echo "> 由 tools/plugin_index.sh 生成；不要手改。"
    echo
    for d in "$ROOT"/plugins/*/; do
        [ -f "$d/plugin.json" ] || continue
        id=$(sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$d/plugin.json" | head -1)
        ver=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$d/plugin.json" | head -1)
        caps=$(grep -o '"capabilities"[^]]*]' "$d/plugin.json" 2>/dev/null | sed 's/.*\[//; s/\]//; s/"//g; s/,/ /g')
        echo "## $id $ver"
        echo
        echo "- capabilities: $(echo "$caps" | tr -s ' ')"
        if [ -d "$d/entry" ]; then
            for e in "$d"/entry/*.sh; do
                [ -f "$e" ] || continue
                desc=$(sed -n 's/^# @desc[[:space:]]*//p' "$e" | head -1)
                rel="${e#$ROOT/}"; rel=$(printf '%s' "$rel" | sed 's#//#/#g')
                echo "- \`$rel\` — ${desc:-entry}"
            done
        fi
        echo
    done
} > "$OUT"
sed -i 's/[[:space:]]*$//' "$OUT"
sed -i '${/^$/d;}' "$OUT"
echo "wrote $OUT"
