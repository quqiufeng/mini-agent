local here = (arg and arg[0] or ""):match("^(.*)/") or "."
package.path = here .. "/../?.lua;" .. here .. "/../device/?.lua;" .. here .. "/?.lua;" .. package.path
local root = os.getenv("MYAGENT_ROOT") or "/home/quqiufeng/my-agent"
local tmp = "/tmp/myagent_unified_" .. tostring(require("core").getpid())
local ffi = require("ffi")
ffi.cdef[[int setenv(const char *name, const char *value, int overwrite);]]
ffi.C.setenv("MYAGENT_STATE_DIR", tmp .. "/state", 1)
ffi.C.setenv("MYAGENT_KV_DIR", tmp .. "/kv", 1)
local H = require("harness")
local core = require("core")
local registry = require("registry")
local devstate = require("state_machine")
local lease = require("lease")
local session = require("session")

local list = registry.list()
H.ok(#list >= 8, "registry lists devices")
local ids = {}
for _, d in ipairs(list) do ids[d.id] = true end
H.ok(ids.camera and ids.nas and ids.tv and ids.speaker, "network devices registered")

devstate.force("camera", "online", "test")
H.eq(devstate.get("camera"), "online", "device state")

local l = lease.acquire("camera", "unified", 5, core.getpid())
H.ok(l ~= nil, "device lease")
H.eq(lease.get("camera").owner, "unified", "lease owner")
lease.release("camera", core.getpid())
H.ok(lease.get("camera") == nil, "lease released")

local rec = session.enter("voice:unified", "phone", { init = { to = "张三" } })
H.ok(rec ~= nil and rec.context and rec.context.libs ~= nil, "plugin context")
H.eq(session.get("voice:unified").init.to, "张三", "session init")
local s2 = session.enter("voice:unified2", "phone", {})
H.ok(s2 ~= nil and s2.context.libs[1] == "adb", "plugin context copied")
s2.context.libs[1] = "mutated"
H.eq(session.get("voice:unified").context.libs[1], "adb", "context isolation")
session.exit("voice:unified")
H.ok(session.get("voice:unified") == nil, "session exit")

H.done()
