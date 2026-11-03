-- lib/state.lua — CLI 薄入口，读写 lib/state_core.lua
local here = (arg and arg[0] or ""):match("^(.*)/") or "."
package.path = here .. "/?.lua;" .. package.path
local core = require("core")
local S = require("state_core")

local cmd = arg and arg[1] or "show"
if cmd == "set" then
    local key, value = arg[2], arg[3]
    if not key or not value then io.stderr:write("用法: state.sh set <key> <value> [extra...]\n"); os.exit(2) end
    local extra = {}
    for i = 4, #arg do extra[#extra + 1] = arg[i] end
    S.write(key, value, extra)
elseif cmd == "get" then
    if not arg[2] then os.exit(2) end
    local v = core.read(S.dir() .. "/" .. arg[2])
    if v then io.write(v) end
elseif cmd == "show" then
    for _, key in ipairs(S.list()) do
        io.write(string.format("%-16s %s\n", key, (core.read(S.dir() .. "/" .. key) or ""):gsub("\n$", "")))
    end
elseif cmd == "active-media" then
    local k = S.active_media()
    if k then io.write(k .. "\n") else os.exit(1) end
elseif cmd == "any-playing" then
    local list = S.any_playing()
    for _, k in ipairs(list) do io.write(k .. "\n") end
    if #list == 0 then os.exit(1) end
elseif cmd == "playing" then
    local v = S.read(arg[2] or "")
    os.exit(v and v.state == "playing" and 0 or 1)
elseif cmd == "tidy" then
    S.tidy()
elseif cmd == "stale" then
    local v = S.read(arg[2] or "")
    local max = tonumber(arg[3] or 5) or 5
    if not v then os.exit(1) end
    os.exit(os.time() - v.ts > max and 0 or 1)
else
    io.stderr:write("用法: state.sh set|get|show|active-media|any-playing|playing|tidy|stale\n")
    os.exit(2)
end
