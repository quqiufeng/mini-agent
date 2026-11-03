-- lib/device/events.lua — 设备事件出口（日志 + 进程内订阅）
local here = (debug.getinfo(1, "S").source:gsub("^@", "")):match("^(.*)/") or "."
package.path = here .. "/../?.lua;" .. package.path
local bus = require("events.bus")

local M = {}
local listeners = {}

local T = {
    discovered = "device.discovered", online = "device.online", offline = "device.offline",
    ready = "device.ready", busy = "device.busy", idle = "device.idle",
    degraded = "device.degraded", error = "device.error",
    lease_acquired = "device.lease.acquired", lease_released = "device.lease.released",
}

function M.publish(kind, data)
    local ev = {
        type = T[kind] or ("device." .. tostring(kind)),
        source = "device",
        ts = os.time(),
        data = data or {},
    }
    local full = bus.publish(ev.type, ev.data, { source = "device" })
    ev.seq = full.seq
    ev.ts = full.ts
    for _, fn in ipairs(listeners) do pcall(fn, ev) end
    return ev
end

function M.subscribe(prefix, fn)
    local l = function(ev)
        if not prefix or ev.type:sub(1, #prefix) == prefix then pcall(fn, ev) end
    end
    listeners[#listeners + 1] = l
    return function()
        for i, x in ipairs(listeners) do if x == l then table.remove(listeners, i); break end end
    end
end

return M
