#!/usr/bin/env luajit
-- tools/winctl.lua — 窗口操作（LuaJIT FFI + libxdo），替代 xdotool 命令行
-- 用法: winctl.lua focus <标题片段> | mirror-sync | mirror-hide | mirror-show | geom <标题片段|类名>
local DIR = (arg[0] or ""):match("^(.*)/") or "."
package.path = DIR .. "/?.lua;" .. package.path
local ffi = require("ffi")
ffi.cdef[[int usleep(unsigned int);]]
local Xdo = require("xdo")

local d = assert(Xdo.new())
local cmd = arg[1] or ""
local MIRROR_ID = "/tmp/myagent_mirror.id"

local function find_win(pat)
    local w
    for _, x in ipairs(d:windows()) do
        if x.name and x.name:find(pat, 1, true) then w = x end
    end
    if not w then
        for _, x in ipairs(d:find_class(pat)) do w = x end
    end
    return w
end

local function mirror_win()
    local w = find_win("scrcpy")
    if w then
        local f = io.open(MIRROR_ID, "w")
        if f then f:write(tostring(tonumber(w.id) or 0)); f:close() end
        return w
    end
    local f = io.open(MIRROR_ID, "r")
    if f then
        local id = f:read("*l"); f:close()
        if id and id ~= "" then
            id = id:gsub("ULL$", "")
            local n = tonumber(id)
            if n then return { id = n } end
        end
    end
    return nil
end

if cmd == "focus" then
    local w = find_win(arg[2] or "BRAIN TUI")
    if w then d:activate(w.id) end
elseif cmd == "mirror-sync" then
    local g = find_win("ai助手")
    local m = mirror_win()
    if g and m then d:move_window(m.id, g.geom.x + 480, g.geom.y) end
elseif cmd == "mirror-follow" then
    local lastx, lasty, lastw, lasth = -1, -1, -1, -1
    local miss = 0
    while true do
        local g
        for _, w in ipairs(d:windows()) do
            if w.name and w.name:find("ai助手", 1, true) and w.geom and w.geom.w >= 800 then g = w end
        end
        if not g then g = find_win("ai助手") end
        local m = mirror_win()
        if g and m and g.geom then
            local x, y = g.geom.x + 480, g.geom.y
            local w, h = 405, 900
            if x ~= lastx or y ~= lasty or w ~= lastw or h ~= lasth then
                d:unmaximize_resize(m.id, x, y, w, h)
                lastx, lasty, lastw, lasth = x, y, w, h
            end
            miss = 0
        else
            miss = miss + 1
            if miss > 20 then break end
        end
        ffi.C.usleep(300000)
    end
elseif cmd == "mirror-hide" then
    local m = mirror_win()
    if m then d:hide(m.id) end
elseif cmd == "mirror-show" then
    local m = mirror_win()
    if m then
        d:show(m.id)
        local g = find_win("ai助手")
        if g then d:move_window(m.id, g.geom.x + 480, g.geom.y) end
        d:raise(m.id)
    end
elseif cmd == "geom" then
    local w = find_win(arg[2] or "")
    if w and w.geom then print(w.geom.x, w.geom.y, w.geom.w, w.geom.h) end
else
    io.stderr:write("用法: winctl.lua focus <标题> | mirror-sync | mirror-hide | mirror-show | geom <标题|类>\n")
    os.exit(2)
end
