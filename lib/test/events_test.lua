local here = (arg and arg[0] or ""):match("^(.*)/") or "."
package.path = here .. "/../?.lua;" .. here .. "/../device/?.lua;" .. here .. "/?.lua;" .. package.path
local root = os.getenv("MYAGENT_ROOT") or "/home/quqiufeng/my-agent"
local tmp = "/tmp/myagent_events_" .. tostring(require("core").getpid())
local ffi = require("ffi")
ffi.cdef[[int setenv(const char *name, const char *value, int overwrite);]]
ffi.C.setenv("MYAGENT_KV_DIR", tmp, 1)
local H = require("harness")
local bus = require("events.bus")
local a = bus.publish("device.test", { n = 1 })
local b = bus.publish("device.test", { n = 2 })
H.eq(a.seq + 1, b.seq, "event seq")
local r = bus.recent(2)
H.eq(#r, 2, "event recent")
H.eq(r[1].data.n, 1, "event data 1")
H.eq(#bus.since(a.seq), 1, "event since")
H.done()
