-- lib/device.lua — 统一设备门面：注册/状态/租约/探活（KV 单一源）
local here = (arg and arg[0] or ""):match("^(.*)/") or "."
package.path = here .. "/?.lua;" .. here .. "/ffi/?.lua;" .. here .. "/device/?.lua;" .. package.path
local core = require("core")
local state = require("state_core")
local registry = require("registry")
local device_state = require("state_machine")
local lease = require("lease")
local probe = require("probe")
local health = require("health")

local D = {}

function D.dirs() end

function D.get(id) return registry.get(id) end
function D.list(filter) return registry.list(filter) end
function D.refresh() return registry.refresh(true) end

function D.acquire(id, purpose, ttl, pid)
    if not registry.get(id) then return nil, "unknown device" end
    local l, err = lease.acquire(id, purpose, ttl, pid)
    if not l then return nil, err end
    return l
end

function D.release(id, pid)
    return lease.release(id, pid)
end

function D.lease(id)
    local l = lease.get(id)
    return l
end

function D.probe(id)
    if id then
        local st = probe.get(id)
        if st then device_state.force(id, st, "probe") end
        return st
    end
    return probe.refresh({ force = true })
end

function D.probe_all() return probe.refresh({ force = true }) end
function D.tidy() lease.tidy() end

function D.state(id)
    local v = state.read("device." .. tostring(id))
    return v
end

function D.show()
    local seen = {}
    for _, d in ipairs(registry.list()) do
        seen[d.id] = true
        local v = state.read("device." .. d.id)
        local l = lease.get(d.id)
        local st = v and v.state or "-"
        local extra = l and (" lease=" .. tostring(l.owner) .. ":" .. tostring(l.pid)) or ""
        io.write(string.format("%-12s %-8s %-12s %s%s\n", d.id, st, d.type or "-", d.ip or "-", extra))
    end
    for _, k in ipairs(state.list()) do
        local id = k:match("^device%.(.+)$")
        if id and not seen[id] then
            local v = state.read(k)
            io.write(string.format("%-12s %-8s\n", id, v and v.state or "-"))
        end
    end
end

function D.health(id) return health.get(id) end

local cmd = arg and arg[1] or "show"
if cmd == "status" then
    D.probe_all()
    D.show()
elseif cmd == "probe" then
    if arg[2] then D.probe(arg[2]) else D.probe_all() end
    D.show()
elseif cmd == "show" then
    D.show()
elseif cmd == "ip" then
    local d = registry.get(arg[2] or "")
    if d and d.ip then io.write(d.ip .. "\n") else os.exit(1) end
elseif cmd == "serial" then
    local d = registry.get(arg[2] or "")
    if not d then os.exit(1) end
    if d.serial then io.write(d.serial .. "\n")
    elseif d.ip then io.write(d.ip .. ":5555\n")
    else os.exit(1) end
elseif cmd == "sink" then
    local d = registry.get(arg[2] or "speaker")
    local sink = d and d.sources and d.sources.audio and d.sources.audio.sink
    if sink then io.write(sink .. "\n") else os.exit(1) end
elseif cmd == "source" then
    local d = registry.get(arg[2] or "")
    if not d then os.exit(1) end
    local J = require("json")
    io.write((J.encode(d.sources or {}) or "{}") .. "\n")
elseif cmd == "json" then
    local d = registry.get(arg[2] or "")
    if not d then os.exit(1) end
    local J = require("json")
    io.write((J.encode(d) or "{}") .. "\n")
elseif cmd == "state" then
    local v = D.state(arg[2] or "")
    if v then io.write(v.raw .. "\n") else os.exit(1) end
elseif cmd == "acquire" then
    local id, purpose = arg[2], arg[3]
    if not id then os.exit(2) end
    local ttl = tonumber(arg[4] or "") or 30
    local pid = tonumber(arg[5] or "") or core.getpid()
    local l, err = D.acquire(id, purpose, ttl, pid)
    if not l then io.stderr:write(tostring(err) .. "\n"); os.exit(2) end
    io.write(string.format("%s %d %s %d\n", l.id, l.pid, l.owner, l.until_ts))
elseif cmd == "release" then
    local ok, err = D.release(arg[2], arg[3])
    if not ok then io.stderr:write(tostring(err) .. "\n"); os.exit(2) end
elseif cmd == "lease" then
    local l = D.lease(arg[2] or "")
    if l then io.write(string.format("%d %s %d\n", l.pid, l.owner, l.until_ts)) else os.exit(1) end
elseif cmd == "refresh" then
    local reg = D.refresh()
    io.write(string.format("devices=%d\n", #(reg.devices or {})))
elseif cmd == "tidy" then
    D.tidy()
else
    io.stderr:write("用法: device.sh status|refresh|probe|show|ip|serial|sink|source|json|state <id>|acquire <id> <purpose> [ttl] [pid]|release <id> [pid]|lease <id>|tidy\n")
    os.exit(2)
end
