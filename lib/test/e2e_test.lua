local here = (arg and arg[0] or ""):match("^(.*)/") or "."
package.path = here .. "/../?.lua;" .. here .. "/?.lua;" .. package.path
local core = require("core")
local H = require("harness")
local root = os.getenv("MYAGENT_ROOT") or "/home/quqiufeng/my-agent"
local sd = "/tmp/e2e_state_" .. tostring(core.getpid())
local kd = "/tmp/e2e_kv_" .. tostring(core.getpid())
local ld = "/tmp/e2e_lease_" .. tostring(core.getpid())
local function run(argv)
    local out, _, rc = core.exec_argv(argv, { timeout = 15 })
    return out or "", rc
end
local function envrun(extra, argv)
    local a = { "/usr/bin/env" }
    for _, e in ipairs(extra) do a[#a + 1] = e end
    for _, x in ipairs(argv) do a[#a + 1] = x end
    return run(a)
end
local _, rc = envrun({ "MYAGENT_STATE_DIR=" .. sd }, { root .. "/tools/state.sh", "show" })
H.eq(rc, 0, "state layer")
local out, rc2 = envrun({ "MYAGENT_STATE_DIR=" .. sd, "MYAGENT_LEASE_DIR=" .. ld },
    { root .. "/tools/lua.sh", root .. "/lib/device.lua", "acquire", "vlc", "e2e", "30", tostring(core.getpid()) })
H.eq(rc2, 0, "device lease")
H.ok(out:find("vlc", 1, true) ~= nil, "lease output")
envrun({ "MYAGENT_LEASE_DIR=" .. ld }, { root .. "/tools/lua.sh", root .. "/lib/device.lua", "release", "vlc", tostring(core.getpid()) })
local out3, rc3 = envrun({ "MYAGENT_KV_DIR=" .. kd }, { root .. "/tools/session.sh", "enter", "voice:e2e", "phone", "--ttl", "5", "--init", "to=张三" })
H.eq(rc3, 0, "session enter")
H.ok(out3:find("plugin=phone", 1, true) ~= nil, "session value")
local out4, rc4 = envrun({ "MYAGENT_KV_DIR=" .. kd }, { root .. "/tools/session.sh", "get", "voice:e2e" })
H.eq(rc4, 0, "session get")
H.ok(out4:find("init.to=张三", 1, true) ~= nil, "session init")
envrun({ "MYAGENT_KV_DIR=" .. kd }, { root .. "/tools/session.sh", "exit", "voice:e2e" })
H.done()
