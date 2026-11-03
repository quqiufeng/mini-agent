local here = (arg and arg[0] or ""):match("^(.*)/") or "."
package.path = here .. "/../?.lua;" .. here .. "/?.lua;" .. package.path
local core = require("core")
local H = require("harness")

local root = os.getenv("MYAGENT_ROOT") or "/home/quqiufeng/my-agent"
local dir = "/tmp/myagent_state_test_" .. tostring(core.getpid())
os.execute = nil
core.mkdirp(dir)

local function run(args)
    local argv = { "/usr/bin/env", "MYAGENT_STATE_DIR=" .. dir, "MYAGENT_SKIP_PID_MATCH=1",
                   root .. "/tools/lua.sh", root .. "/lib/state.lua" }
    for _, a in ipairs(args) do argv[#argv + 1] = a end
    local out, _, rc = core.exec_argv(argv, { timeout = 10 })
    return out, rc
end

local pid = core.getpid()
H.eq(select(2, run({ "set", "media.phone", "playing", tostring(pid), "redmi" })), 0, "set phone")
H.eq((run({ "get", "media.phone" })):match("^playing"), "playing", "get phone")
H.eq((run({ "active-media" })):match("^media%.phone"), "media.phone", "active phone")
H.eq(select(2, run({ "set", "media.vlc", "playing", tostring(pid) })), 0, "set vlc")
H.eq((run({ "active-media" })):match("^media%.vlc"), "media.vlc", "latest playing wins")
H.eq(select(2, run({ "set", "media.vlc", "playing", "999999" })), 0, "set dead vlc")
run({ "tidy" })
H.eq((run({ "get", "media.vlc" })):match("^stopped"), "stopped", "tidy dead pid")
H.eq(select(2, run({ "playing", "media.vlc" })), 1, "playing predicate false")
local shown = run({ "show" })
H.ok(shown:find("media.phone", 1, true) ~= nil, "show contains phone")
H.done()
