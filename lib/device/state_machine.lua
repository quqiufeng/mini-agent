-- lib/device/state_machine.lua — 设备状态机（单一状态源 + 事件）
local here = (debug.getinfo(1, "S").source:gsub("^@", "")):match("^(.*)/") or "."
package.path = here .. "/../?.lua;" .. package.path
local state = require("state_core")
local events = require("events")

local M = {}
local STATES = { "discovered", "online", "ready", "busy", "idle", "degraded", "offline", "error" }
local SET = {}
for _, s in ipairs(STATES) do SET[s] = true end
local TRANS = {
    discovered = { online = true, offline = true, error = true },
    online = { ready = true, degraded = true, offline = true, error = true },
    ready = { busy = true, idle = true, degraded = true, offline = true, error = true },
    busy = { ready = true, idle = true, degraded = true, offline = true, error = true },
    idle = { busy = true, ready = true, degraded = true, offline = true, error = true },
    degraded = { ready = true, idle = true, offline = true, error = true },
    offline = { online = true, discovered = true },
    error = { online = true, offline = true, discovered = true },
}

local key = function(id) return "device." .. tostring(id) end

function M.states() return STATES end

function M.get(id)
    local v = state.read(key(id))
    return v and v.state or "unknown"
end

function M.detail(id)
    local v = state.read(key(id))
    if not v then return nil end
    return v.raw:match("^%S+ %S+ [^ ]* ?(.*) @%d+$")
end

function M.last_seen(id)
    local v = state.read(key(id))
    return v and v.ts or nil
end

function M.touch(id)
    local v = state.read(key(id))
    if v then state.write(key(id), v.state, { v.pid or 0 }) end
end

function M.transition(id, to, detail)
    if not SET[to] then return false, "unknown state: " .. tostring(to) end
    local from = M.get(id)
    if from ~= "unknown" and from ~= to and not (TRANS[from] and TRANS[from][to]) then
        return false, string.format("invalid transition %s: %s -> %s", tostring(id), from, to)
    end
    state.write(key(id), to, { detail or "" })
    if from ~= to then
        events.publish(to, { id = id, state = to, from = from, detail = detail })
    end
    return true, { from = from, to = to }
end

function M.set(id, to, detail) return M.transition(id, to, detail) end

function M.force(id, to, detail)
    local from = M.get(id)
    state.write(key(id), to, { detail or "" })
    if from ~= to then
        events.publish(to, { id = id, state = to, from = from, detail = detail, forced = true })
    end
    return true
end

return M
