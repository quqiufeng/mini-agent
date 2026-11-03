#!/usr/bin/env luajit
-- @desc 取消窗口最大化并调整大小/位置（LuaJIT + Xlib FFI）
-- @usage tools/win_resize.lua <window_id> <width> <height> [x] [y]
local DIR = (arg[0] or ""):match("^(.*)/") or "."
local ROOT = DIR .. "/../.."
package.path = DIR .. "/?.lua;" .. ROOT .. "/tools/?.lua;" .. package.path
local Xdo = require("xdo")

local win = tonumber(arg[1] or "")
local w = tonumber(arg[2] or "")
local h = tonumber(arg[3] or "")
if not win or not w or not h then
    io.stderr:write("usage: win_resize.lua <window_id> <width> <height> [x] [y]\n")
    os.exit(2)
end

local d, err = Xdo.new()
if not d then io.stderr:write(tostring(err or "Xdo.new failed") .. "\n"); os.exit(1) end
local g = d:geometry(win)
local x = tonumber(arg[4] or "") or (g and g.x) or 0
local y = tonumber(arg[5] or "") or (g and g.y) or 0
d:unmaximize_resize(win, x, y, w, h)
d:close()
