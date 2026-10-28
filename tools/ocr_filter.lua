#!/usr/bin/env luajit
-- @desc 过滤 tools/ocr.sh 的 JSON 文本框：field=区域文本(大写字母数字) / flat=全文去空白
-- @usage tools/ocr.sh img.png | tools/lua.sh tools/ocr_filter.lua field <x1> <y1> <x2> <y2>
--        tools/ocr.sh img.png | tools/lua.sh tools/ocr_filter.lua flat
local DIR = (arg[0] or ""):match("^(.*)/") or "."
package.path = DIR .. "/?.lua;" .. package.path
local J = require("jsonc")

local mode = arg[1] or "flat"
local data = io.read("*a")
local o = J.parse(data)
if not o then print(""); os.exit(0) end
local n = J.len(o)
local parts = {}
if mode == "field" then
    local x1, y1, x2, y2 = tonumber(arg[2]), tonumber(arg[3]), tonumber(arg[4]), tonumber(arg[5])
    for i = 0, n - 1 do
        local p = i .. "."
        local x, y = J.int(o, p .. "x"), J.int(o, p .. "y")
        if x and y and x >= x1 and x <= x2 and y >= y1 and y <= y2 then
            local t = J.str(o, p .. "text") or ""
            parts[#parts + 1] = t
        end
    end
    local s = table.concat(parts):gsub("[^%w]", ""):upper()
    print(s)
else
    for i = 0, n - 1 do parts[#parts + 1] = J.str(o, i .. ".text") or "" end
    print((table.concat(parts):gsub("%s+", "")))
end
J.free(o)
