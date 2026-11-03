local here = (arg and arg[0] or ""):match("^(.*)/") or "."
package.path = here .. "/../?.lua;" .. here .. "/?.lua;" .. package.path
local core = require("core")
local H = require("harness")
local root = os.getenv("MYAGENT_ROOT") or "/home/quqiufeng/my-agent"

local function run(argv, timeout)
    return core.exec_argv(argv, { timeout = timeout or 10 })
end

local out, _, rc = run({ root .. "/tools/devctl.sh", "status" })
H.eq(rc, 0, "devctl status rc")
H.ok(out:find("devices", 1, true) ~= nil, "devctl status lists devices")

out, _, rc = run({ root .. "/tools/state.sh", "show" })
H.eq(rc, 0, "state show rc")

out, _, rc = run({ root .. "/plugins/media/media.sh" })
H.eq(rc, 2, "media bad args rc")

out, _, rc = run({ root .. "/plugins/phone/music.sh", "status" })
H.eq(rc, 0, "phone_music status rc")

out, _, rc = run({ root .. "/plugins/camera/camera_block.sh", "status" })
H.eq(rc, 0, "camera_block status rc")

H.done()
