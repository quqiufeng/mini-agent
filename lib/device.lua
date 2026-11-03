-- lib/device.lua — 轻量设备层：注册/探测/lease/状态
local here = (arg and arg[0] or ""):match("^(.*)/") or "."
package.path = here .. "/?.lua;" .. package.path
local core = require("core")
local state = require("state_core")

local HOME = os.getenv("HOME") or "/tmp"
local LEASE_DIR = os.getenv("MYAGENT_LEASE_DIR") or (HOME .. "/.myagent/lease")

local DEVICES = {
    phone = { type = "phone", transport = "adb", serial = os.getenv("PHONE2_SERIAL") or "192.168.1.59:5555" },
    tv = { type = "tv", transport = "adb", serial = "192.168.1.110:5555" },
    speaker = { type = "audio", transport = "alsa", sink = "alsa_output.usb-DUNU_DTC_480_DTC_480-00.analog-stereo" },
    camera = { type = "camera", transport = "rtsp" },
    vlc = { type = "player", transport = "x11" },
    mirror = { type = "display", transport = "adb" },
}

local D = {}

local function sset(id, value, extra)
    state.write("device." .. id, value, extra)
end

local function lease_path(id)
    return LEASE_DIR .. "/" .. id
end

local function lease_read(id)
    local s = core.read(lease_path(id))
    if not s then return nil end
    local f = {}
    for x in s:gmatch("%S+") do f[#f + 1] = x end
    if #f < 3 then return nil end
    return { pid = tonumber(f[1]) or 0, owner = f[2], until_ts = tonumber(f[3]) or 0, purpose = f[4] }
end

local function lease_valid(l)
    return l and l.until_ts > os.time() and core.pid_alive(l.pid)
end

function D.dirs()
    core.mkdirp(LEASE_DIR)
end

function D.acquire(id, purpose, ttl, pid)
    if not DEVICES[id] then return nil, "unknown device" end
    D.dirs()
    local cur = lease_read(id)
    if lease_valid(cur) then
        if cur.pid ~= pid then return nil, "busy:" .. tostring(cur.owner) .. ":" .. tostring(cur.pid) end
    end
    local line = string.format("%d %s %d %s\n", pid or core.getpid(), purpose or "unknown",
                               os.time() + (ttl or 30), purpose or "")
    local ok, err = core.write_atomic(lease_path(id), line)
    if not ok then return nil, err end
    state.write("lease." .. id, "held", { pid or core.getpid(), purpose or "unknown" })
    return { id = id, pid = pid or core.getpid(), owner = purpose or "unknown",
             until_ts = os.time() + (ttl or 30) }
end

function D.release(id, pid)
    local cur = lease_read(id)
    if not cur then return true end
    if pid and cur.pid ~= tonumber(pid) then return false, "not-owner" end
    os.remove(lease_path(id))
    state.write("lease." .. id, "free", {})
    return true
end

function D.lease(id)
    local l = lease_read(id)
    if not lease_valid(l) then return nil end
    return l
end

local function probe_adb(id)
    local out = core.exec_argv({ "adb", "devices", "-l" }, { timeout = 5 }) or ""
    local serial = DEVICES[id].serial
    for line in out:gmatch("[^\n]+") do
        if line:find(serial, 1, true) and line:find("%sdevice") then
            sset(id, "ready", { serial })
            return "ready"
        end
    end
    sset(id, "offline", { serial })
    return "offline"
end

local function probe_speaker()
    local out = core.exec_argv({ "pactl", "list", "short", "sinks" }, { timeout = 5 }) or ""
    local sink = DEVICES.speaker.sink
    for line in out:gmatch("[^\n]+") do
        if line:find(sink, 1, true) then
            sset("speaker", "ready", { sink })
            return "ready"
        end
    end
    sset("speaker", "offline", { sink })
    return "offline"
end

local function probe_vlc()
    local v = state.read("media.vlc")
    if v and (v.state == "playing" or v.state == "paused") and v.pid and core.pid_matches(v.pid, "vlc") then
        sset("vlc", v.state == "playing" and "busy" or "ready", { v.pid })
        return v.state == "playing" and "busy" or "ready"
    end
    sset("vlc", "idle", {})
    return "idle"
end

function D.probe(id)
    local dev = DEVICES[id]
    if not dev then return nil, "unknown device" end
    if id == "mirror" then
        local v = state.read("display.wechat")
        if v and v.state == "on" and v.pid and core.pid_matches(v.pid, "scrcpy") then
            sset("mirror", "busy", { v.pid }); return "busy"
        end
        sset("mirror", "idle", {}); return "idle"
    end
    if dev.transport == "adb" and dev.serial then return probe_adb(id) end
    if id == "speaker" then return probe_speaker() end
    if id == "vlc" then return probe_vlc() end
    if id == "camera" then sset("camera", "ready", { "rtsp" }); return "ready" end
    sset(id, "ready", {})
    return "ready"
end

function D.probe_all()
    for id in pairs(DEVICES) do D.probe(id) end
    D.tidy()
end

function D.tidy()
    D.dirs()
    for _, f in ipairs(core.list_dir(LEASE_DIR)) do
        local l = lease_read(f)
        if not lease_valid(l) then os.remove(LEASE_DIR .. "/" .. f); state.write("lease." .. f, "free", {}) end
    end
end

function D.show()
    local keys = state.list()
    local seen = {}
    for _, k in ipairs(keys) do
        local id = k:match("^device%.(.+)$")
        if id then
            local v = state.read(k)
            local l = D.lease(id)
            io.write(string.format("%-10s %-8s %s%s\n", id, v.state,
                v.raw:gsub("^%S+ %S+ %S* ?", ""),
                l and (" lease=" .. l.owner .. ":" .. l.pid) or ""))
            seen[id] = true
        end
    end
    for id in pairs(DEVICES) do
        if not seen[id] then io.write(string.format("%-10s %-8s\n", id, "-")) end
    end
end

local cmd = arg and arg[1] or "show"
if cmd == "status" then
    D.probe_all()
    D.show()
elseif cmd == "probe" then
    if arg[2] then D.probe(arg[2]) else D.probe_all() end
    D.show()
elseif cmd == "show" then
    D.show()
elseif cmd == "state" then
    local v = state.read("device." .. (arg[2] or ""))
    if v then io.write(v.raw .. "\n") else os.exit(1) end
elseif cmd == "acquire" then
    local id, purpose = arg[2], arg[3]
    if not id then os.exit(2) end
    local pid = tonumber(arg[5] or "") or core.getpid()
    local ttl = tonumber(arg[4] or "") or 30
    local l, err = D.acquire(id, purpose, ttl, pid)
    if not l then io.stderr:write(tostring(err) .. "\n"); os.exit(2) end
    io.write(string.format("%s %d %s %d\n", l.id, l.pid, l.owner, l.until_ts))
elseif cmd == "release" then
    local ok = D.release(arg[2], arg[3])
    if not ok then os.exit(2) end
elseif cmd == "lease" then
    local l = D.lease(arg[2] or "")
    if l then io.write(string.format("%d %s %d\n", l.pid, l.owner, l.until_ts)) else os.exit(1) end
elseif cmd == "tidy" then
    D.tidy()
else
    io.stderr:write("用法: device.sh status|probe|show|state <id>|acquire <id> <purpose> [ttl] [pid]|release <id> [pid]|lease <id>|tidy\n")
    os.exit(2)
end
