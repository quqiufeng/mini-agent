-- lib/device/probe.lua — 设备可用性探活（结果写 KV 状态 + 事件）
local here = (debug.getinfo(1, "S").source:gsub("^@", "")):match("^(.*)/") or "."
package.path = here .. "/../?.lua;" .. here .. "/?.lua;" .. package.path
local core = require("core")
local registry = require("registry")
local state = require("state_machine")

local M = {}
local TTL = 3
local last_run = 0

local function adb_devices()
    local out = core.exec_argv({ "adb", "devices", "-l" }, { timeout = 5 }) or ""
    local set = {}
    for line in out:gmatch("[^\n]+") do
        local serial, st = line:match("^(%S+)%s+(%S+)")
        if serial and st == "device" then set[serial] = true end
    end
    return set
end

local function sinks()
    local out = core.exec_argv({ "pactl", "list", "short", "sinks" }, { timeout = 5 }) or ""
    local set = {}
    for line in out:gmatch("[^\n]+") do
        local name = line:match("^%d+%s+(%S+)")
        if name then set[name] = true end
    end
    return set
end

local function cards()
    local raw = core.read("/proc/asound/cards") or ""
    local set = {}
    for line in raw:gmatch("[^\n]+") do
        local id = line:match("^%s*%d+%s+%[([^%]]+)%]")
        if id then set[id] = true end
    end
    return set
end

local function neighbor(ip)
    if not ip or ip == "" then return nil end
    local out = core.exec_argv({ "ip", "neigh", "show", ip }, { timeout = 3 }) or ""
    if out:match("REACHABLE") or out:match("STALE") or out:match("DELAY") or out:match("PROBE") then return true end
    if out:match("FAILED") or out:match("INCOMPLETE") then return false end
    return nil
end

local function probe(d)
    local adb = nil
    local function adb_has()
        if adb == nil then adb = adb_devices() end
        return adb[d.ip] or adb[d.serial or ""] or false
    end
    if d.type == "speaker" then
        local sink = d.sources and d.sources.audio and d.sources.audio.sink
        return sink and sinks()[sink] and "online" or "offline"
    end
    if d.type == "microphone" then
        local card = d.sources and d.sources.audio and d.sources.audio.card
        if not card then return nil end
        local raw = core.read("/proc/asound/cards") or ""
        if raw:find(card, 1, true) then return "online" end
        for name in pairs(cards()) do if name:find(card, 1, true) then return "online" end end
        return "offline"
    end
    if d.type == "phone" or d.type == "tv" then
        if adb_has() then return "online" end
        local n = neighbor(d.ip)
        if n ~= nil then return n and "online" or "offline" end
        return "offline"
    end
    if d.type == "camera" then
        if d.sources and d.sources.video and d.sources.video.kind == "rtsp" then
            local n = neighbor(d.sources.video.host or d.ip)
            if n ~= nil then return n and "online" or "offline" end
        end
        local n = neighbor(d.ip)
        if n ~= nil then return n and "online" or "offline" end
        return nil
    end
    if d.type == "vlc" or d.type == "player" then
        local v = require("state_core").read("media.vlc")
        if v and (v.state == "playing" or v.state == "paused") then return "busy" end
        return "idle"
    end
    if d.type == "display" and d.id == "mirror" then
        local v = require("state_core").read("display.wechat")
        if v and v.state == "on" then return "busy" end
        return "idle"
    end
    if d.type == "network" or d.type == "gateway" or d.type == "computer" or d.type == "nas" then
        local n = neighbor(d.ip)
        if n ~= nil then return n and "online" or "offline" end
        return nil
    end
    return nil
end

function M.get(id)
    local d = registry.get(id)
    if not d then return nil, "not found" end
    return probe(d)
end

function M.refresh(opts)
    opts = opts or {}
    local now = os.time()
    if not opts.force and now - last_run < (opts.ttl or TTL) then return { cached = true } end
    last_run = now
    local checked, online, offline = 0, 0, 0
    for _, d in ipairs(registry.list()) do
        local st = probe(d)
        if st then
            state.force(d.id, st, "probe")
            checked = checked + 1
            if st == "offline" then offline = offline + 1 else online = online + 1 end
        else
            local last = state.last_seen(d.id)
            if last and now - last > 15 then
                state.force(d.id, "offline", "timeout")
                checked = checked + 1
                offline = offline + 1
            end
        end
    end
    return { checked = checked, online = online, offline = offline }
end

return M
