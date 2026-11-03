-- lib/events/bus.lua — 跨进程事件总线（KV 追加事件 + 进程内订阅）
local here = (debug.getinfo(1, "S").source:gsub("^@", "")):match("^(.*)/") or "."
package.path = here .. "/../?.lua;" .. here .. "/../ffi/?.lua;" .. package.path
local ffi = require("ffi")
local core = require("core")
local JSON = require("json")
local KV = require("kv")
ffi.cdef[[
int open(const char *path, int flags, ...);
int close(int fd);
int flock(int fd, int operation);
]]
local HOME = os.getenv("HOME") or "/tmp"
local DIR = os.getenv("MYAGENT_KV_DIR")
if not DIR or DIR == "" then
    local sd = os.getenv("MYAGENT_STATE_DIR")
    DIR = (sd and sd ~= "") and (sd .. ".kv") or (HOME .. "/.myagent/kv")
end
local TTL = tonumber(os.getenv("EVENT_TTL") or "3600")
local M = {}
local listeners = {}
local db

local function open()
    if db then return db end
    core.mkdirp(DIR)
    db = KV.open(DIR, 64 * 1024 * 1024)
    return db
end

local function lock_fd()
    return ffi.C.open(DIR .. "/event.lock", 0x42, 0x1A4) -- O_CREAT|O_RDWR
end

function M.publish(typ, data, opts)
    opts = opts or {}
    local seq, ev, raw
    local fd = lock_fd()
    if fd >= 0 then ffi.C.flock(fd, 2) end -- LOCK_EX
    local d = open()
    if d then
        seq = tonumber(d:get("event.seq") or "0") + 1
        ev = { seq = seq, type = typ, source = opts.source or "device",
               ts = os.time(), correlation_id = opts.correlation_id, data = data or {} }
        raw = JSON.encode(ev)
        d:set("event.seq", tostring(seq), 0)
        d:set(string.format("event.%012d", seq), raw or "{}", TTL * 1000)
        d:sync()
    end
    if fd >= 0 then ffi.C.flock(fd, 8); ffi.C.close(fd) end -- LOCK_UN
    ev = ev or { seq = 0, type = typ, source = opts.source or "device", ts = os.time(), data = data or {} }
    core.log(typ, raw or "")
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

function M.recent(n)
    n = tonumber(n or 20)
    local d = open()
    if not d then return {} end
    local keys = {}
    for _, k in ipairs(d:keys("event.")) do
        if k ~= "event.seq" and k:match("^event%.%d+$") then keys[#keys + 1] = k end
    end
    local out = {}
    for i = math.max(1, #keys - n + 1), #keys do
        local ev = JSON.decode(d:get(keys[i]) or "")
        if type(ev) == "table" then out[#out + 1] = ev end
    end
    return out
end

function M.since(seq)
    seq = tonumber(seq or 0)
    local d = open()
    if not d then return {} end
    local out = {}
    for _, k in ipairs(d:keys("event.")) do
        local n = tonumber(k:match("event%.(%d+)$") or "")
        if n and n > seq then
            local ev = JSON.decode(d:get(k) or "")
            if type(ev) == "table" then out[#out + 1] = ev end
        end
    end
    return out
end

function M.close()
    if db then db:close(); db = nil end
end

return M
