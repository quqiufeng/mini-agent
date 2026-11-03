local here = (arg and arg[0] or ""):match("^(.*)/") or "."
package.path = here .. "/../?.lua;" .. here .. "/../device/?.lua;" .. here .. "/?.lua;" .. package.path
local root = os.getenv("MYAGENT_ROOT") or "/home/quqiufeng/my-agent"
local tmp = "/tmp/myagent_registry_" .. tostring(require("core").getpid())
local ffi = require("ffi")
ffi.cdef[[int setenv(const char *name, const char *value, int overwrite);]]
ffi.C.setenv("MYAGENT_KV_DIR", tmp, 1)
ffi.C.setenv("MYAGENT_STATE_DIR", tmp .. "/state", 1)
local H = require("harness")
local registry = require("registry")
local a = registry.refresh(true)
local b = registry.refresh(true)
H.ok(#a.devices >= 8, "registry devices")
H.eq(#a.devices, #b.devices, "registry stable count")
local ids = {}
for _, d in ipairs(a.devices) do ids[d.id] = true end
H.ok(ids.camera and ids.nas and ids.tv and ids.speaker, "core device ids")
H.done()
