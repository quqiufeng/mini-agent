-- lib/device/lease.lua — 设备独占租约（KV 单一源，带 TTL + 事件）
local here = (debug.getinfo(1, "S").source:gsub("^@", "")):match("^(.*)/") or "."
package.path = here .. "/../?.lua;" .. here .. "/../ffi/?.lua;" .. here .. "/?.lua;" .. package.path
local ffi = require("ffi")
local cache = require("cache")
local state = require("state_core")
local events = require("events")
ffi.cdef[[
int open(const char *path, int flags, ...);
int close(int fd);
int flock(int fd, int operation);
]]
local function with_lock(fn)
    local fd = ffi.C.open(cache.dir() .. "/lease.lock", 0x42, 0x1A4)
    if fd < 0 then return fn() end
    ffi.C.flock(fd, 2)
    local ok, a, b = pcall(fn)
    ffi.C.flock(fd, 8); ffi.C.close(fd)
    if not ok then error(a, 0) end
    return a, b
end

local M = {}
local Lease = {}
Lease.__index = Lease
local key = function(id) return tostring(id) .. ".lease" end

local function current(id)
    local l = cache.get_json(key(id))
    if not l then return nil end
    if l.until_ts and l.until_ts <= os.time() then
        cache.del(key(id))
        state.del("lease." .. tostring(id))
        return nil
    end
    return l
end

function M.acquire(id, purpose, ttl, pid)
    return with_lock(function()
        local cur = current(id)
        pid = tonumber(pid) or require("core").getpid()
        if cur and cur.pid ~= pid and cur.owner ~= purpose then
            return nil, string.format("busy:%s:%s", tostring(cur.owner), tostring(cur.pid))
        end
        local lease = {
            id = id, pid = pid, owner = purpose or "unknown", purpose = purpose or "",
            until_ts = os.time() + tonumber(ttl or 30), since = os.time(),
        }
        cache.put(key(id), lease, tonumber(ttl or 30) * 1000)
        state.write("lease." .. tostring(id), "held", { pid, purpose or "unknown" })
        events.publish("lease_acquired", { id = id, owner = lease.owner, pid = pid, until_ts = lease.until_ts })
        return setmetatable(lease, Lease)
    end)
end

function Lease:release()
    local cur = current(self.id)
    if not cur then return true end
    if cur.pid ~= self.pid then return false, "not-owner" end
    cache.del(key(self.id))
    state.write("lease." .. tostring(self.id), "free", {})
    events.publish("lease_released", { id = self.id, owner = self.owner, pid = self.pid })
    return true
end

function M.release(id, pid)
    return with_lock(function()
        local cur = current(id)
        if not cur then return true end
        if pid and cur.pid ~= tonumber(pid) then return false, "not-owner" end
        cache.del(key(id))
        state.write("lease." .. tostring(id), "free", {})
        events.publish("lease_released", { id = id, owner = cur.owner, pid = cur.pid })
        return true
    end)
end

function M.get(id)
    local l = current(id)
    return l
end

function M.tidy()
    for _, id in ipairs({ "phone", "tv", "nas", "camera", "speaker", "microphone", "vlc", "mirror" }) do
        current(id)
    end
end

return M
