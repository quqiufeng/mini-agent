-- lib/device/health.lua — 设备健康状态（状态机统一出口）
local here = (debug.getinfo(1, "S").source:gsub("^@", "")):match("^(.*)/") or "."
package.path = here .. "/?.lua;" .. package.path
local state = require("state_machine")
local registry = require("registry")

local M = {}

function M.get(id)
    local st = state.get(id)
    if st ~= "unknown" then return st end
    local d = registry.get(id)
    return d and d.health or "unknown"
end

function M.mark(id, status, detail)
    local ok = state.transition(id, status, detail)
    if not ok and state.get(id) ~= status then
        state.set(id, status, detail)
    end
    return status
end

function M.check(id)
    local st = M.get(id)
    return st == "online" or st == "ready" or st == "idle" or st == "busy", st
end

function M.all()
    local out = {}
    for _, d in ipairs(registry.list()) do
        out[d.id] = { ok = M.check(d.id), health = M.get(d.id) }
    end
    return out
end

return M
