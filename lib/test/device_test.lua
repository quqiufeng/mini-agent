local here = (arg and arg[0] or ""):match("^(.*)/") or "."
package.path = here .. "/../?.lua;" .. here .. "/?.lua;" .. package.path
local core = require("core")
local H = require("harness")
local root = os.getenv("MYAGENT_ROOT") or "/home/quqiufeng/my-agent"
local sd = "/tmp/myagent_dev_state_" .. tostring(core.getpid())
local ld = "/tmp/myagent_dev_lease_" .. tostring(core.getpid())
core.mkdirp(sd); core.mkdirp(ld)

local function run(args)
    local argv = { "/usr/bin/env", "MYAGENT_STATE_DIR=" .. sd, "MYAGENT_LEASE_DIR=" .. ld,
                   root .. "/tools/lua.sh", root .. "/lib/device.lua" }
    for _, a in ipairs(args) do argv[#argv + 1] = a end
    local out, _, rc = core.exec_argv(argv, { timeout = 10 })
    return out, rc
end
local pid = core.getpid()
H.eq(select(2, run({ "acquire", "vlc", "test", "30", tostring(pid) })), 0, "acquire vlc")
H.eq((run({ "lease", "vlc" })):match("^" .. pid), tostring(pid), "lease vlc")
H.eq(select(2, run({ "acquire", "vlc", "other", "30", "999999" })), 2, "busy vlc")
H.eq(select(2, run({ "release", "vlc", tostring(pid) })), 0, "release vlc")
H.eq(select(2, run({ "lease", "vlc" })), 1, "lease gone")
H.done()
