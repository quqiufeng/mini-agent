local here = (arg and arg[0] or ""):match("^(.*)/") or "."
package.path = here .. "/../?.lua;" .. here .. "/?.lua;" .. package.path
local core = require("core")
local H = require("harness")
local root = os.getenv("MYAGENT_ROOT") or "/home/quqiufeng/my-agent"
local dir = "/tmp/myagent_session_test_" .. tostring(core.getpid())
local function run(args)
    local argv = { "/usr/bin/env", "MYAGENT_KV_DIR=" .. dir, root .. "/tools/session.sh" }
    for _, a in ipairs(args) do argv[#argv + 1] = a end
    local out, _, rc = core.exec_argv(argv, { timeout = 15 })
    return out or "", rc
end
local out, rc = run({ "enter", "voice:test", "phone", "--ttl", "3", "--init", "to=张三" })
H.eq(rc, 0, "enter")
H.ok(out:find("plugin=phone", 1, true) ~= nil, "enter value")
out, rc = run({ "get", "voice:test" })
H.eq(rc, 0, "get")
H.ok(out:find("init.to=张三", 1, true) ~= nil, "init")
H.ok(out:find("context.libs=", 1, true) ~= nil, "plugin context")
out, rc = run({ "touch", "voice:test", "3" })
H.eq(rc, 0, "touch")
run({ "enter", "voice:ttl", "camera", "--ttl", "1" })
core.sleep(1.3)
local _, rc2 = run({ "get", "voice:ttl" })
H.eq(rc2, 1, "ttl expired")
run({ "exit", "voice:test" })
local _, rc3 = run({ "get", "voice:test" })
H.eq(rc3, 1, "exit")
H.done()
