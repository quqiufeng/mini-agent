#!/usr/bin/env bash
# @desc 自主开发插件：新建/校验/列表/索引/测试（plugins/<group>/<name>）
# @usage tools/plugin.sh new <name> [group] | validate [name] | list | index | test <name>
# @rule 新插件必须 plugin.json + entry/*.sh + 实现 + test；entry 只透传
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cmd="${1:-list}"; shift || true

list_plugins() {
    for d in "$ROOT"/plugins/*/ "$ROOT"/plugins/*/*/; do
        [ -f "$d/plugin.json" ] || continue
        id=$(sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$d/plugin.json" | head -1)
        ver=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$d/plugin.json" | head -1)
        entry=$(sed -n 's/.*"entry"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$d/plugin.json" | head -1)
        printf '%-16s %-8s %s\n' "${id:-?}" "$ver" "$entry"
    done
}

validate_one() {
    local d="$1" id ver entry ok=1
    [ -f "$d/plugin.json" ] || { echo "缺 plugin.json: $d"; return 1; }
    id=$(sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$d/plugin.json" | head -1)
    ver=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$d/plugin.json" | head -1)
    entry=$(sed -n 's/.*"entry"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$d/plugin.json" | head -1)
    [ -n "$id" ] || { echo "缺 id: $d"; ok=0; }
    [ -n "$ver" ] || { echo "缺 version: $d"; ok=0; }
    [ -n "$entry" ] || { echo "缺 entry: $d"; ok=0; }
    if [ -n "$entry" ]; then
        if [[ "$entry" == */ ]]; then
            [ -d "$d/$entry" ] || { echo "entry 目录不存在: $d/$entry"; ok=0; }
            local n=0
            for e in "$d/$entry"/*.sh; do
                [ -f "$e" ] || continue
                n=$((n+1))
                [ -x "$e" ] || { echo "entry 不可执行: $e"; ok=0; }
                grep -q '@desc' "$e" || { echo "entry 缺 @desc: $e"; ok=0; }
            done
            [ "$n" -gt 0 ] || { echo "entry 目录为空: $d/$entry"; ok=0; }
        else
            [ -x "$d/$entry" ] || { echo "entry 不存在/不可执行: $d/$entry"; ok=0; }
            grep -q '@desc' "$d/$entry" || { echo "entry 缺 @desc: $d/$entry"; ok=0; }
        fi
    fi
    [ -d "$d/test" ] || { echo "缺 test/: $d"; ok=0; }
    [ "$ok" = 1 ] && echo "OK  $id $ver"
    return $((1-ok))
}

case "$cmd" in
    new)
        name="${1:-}"; group="${2:-system}"
        [ -n "$name" ] || { echo "用法: $0 new <name> [group]" >&2; exit 2; }
        [[ "$name" =~ ^[a-z0-9_]+$ ]] || { echo "name 只允许 [a-z0-9_]" >&2; exit 2; }
        d="$ROOT/plugins/$group/$name"
        [ -e "$d/plugin.json" ] && { echo "已存在: $d" >&2; exit 1; }
        mkdir -p "$d/entry" "$d/test"
        cat > "$d/plugin.json" <<JSON
{
  "id": "$name",
  "version": "0.1.0",
  "apiVersion": "1",
  "type": "tool",
  "entry": "entry/",
  "capabilities": [],
  "permissions": ["process"],
  "dependencies": ["lib.core"]
}
JSON
        cat > "$d/entry/$name.sh" <<SH
#!/usr/bin/env bash
# @desc $group $name
# @usage plugins/$group/$name/entry/$name.sh
set -uo pipefail
DIR="\$(cd "\$(dirname "\$0")" && pwd)"
exec "\$DIR/../../../../tools/lua.sh" "\$DIR/../$name.lua" "\$@"
SH
        cat > "$d/$name.lua" <<LUA
local here = (arg and arg[0] or ""):match("^(.*)/") or "."
local ROOT = here .. "/../.."
package.path = ROOT .. "/lib/?.lua;" .. package.path
local core = require("core")
local args = {}
for i = 1, #arg do args[#args + 1] = arg[i] end
core.log("plugin.$name", table.concat(args, " "))
print("TODO: $group/$name")
LUA
        cat > "$d/test/${name}_test.lua" <<LUA
local here = (arg and arg[0] or ""):match("^(.*)/") or "."
package.path = here .. "/../../../../lib/?.lua;" .. here .. "/../../../../lib/test/?.lua;" .. package.path
local H = require("harness")
H.ok(true, "$name loads")
H.done()
LUA
        chmod +x "$d/entry/$name.sh"
        echo "已创建 $d"
        ;;
    validate)
        if [ $# -gt 0 ]; then
            found=0
            for d in "$ROOT"/plugins/*/ "$ROOT"/plugins/*/*/; do
                id=$(sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$d/plugin.json" 2>/dev/null | head -1)
                [ "$id" = "$1" ] && { found=1; validate_one "$d"; }
            done
            [ "$found" = 1 ] || { echo "未找到插件: $1" >&2; exit 1; }
        else
            rc=0
            for d in "$ROOT"/plugins/*/ "$ROOT"/plugins/*/*/; do
                [ -f "$d/plugin.json" ] || continue
                validate_one "$d" || rc=1
            done
            exit "$rc"
        fi
        ;;
    list) list_plugins ;;
    index) exec "$ROOT/tools/plugin_index.sh" ;;
    test)
        name="${1:-}"
        [ -n "$name" ] || { echo "用法: $0 test <name>" >&2; exit 2; }
        found=0
        for d in "$ROOT"/plugins/*/ "$ROOT"/plugins/*/*/; do
            id=$(sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$d/plugin.json" 2>/dev/null | head -1)
            if [ "$id" = "$name" ]; then
                found=1
                for t in "$d"/test/*_test.lua; do
                    [ -f "$t" ] || continue
                    "$ROOT/tools/lua.sh" "$t"
                done
            fi
        done
        [ "$found" = 1 ] || { echo "未找到插件: $name" >&2; exit 1; }
        ;;
    *) echo "用法: $0 new <name> [group] | validate [name] | list | index | test <name>" >&2; exit 2 ;;
esac
