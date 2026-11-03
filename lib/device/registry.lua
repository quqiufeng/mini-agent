-- lib/device/registry.lua — 统一设备注册表（静态定义 + netmap 发现 + KV 缓存）
local here = (debug.getinfo(1, "S").source:gsub("^@", "")):match("^(.*)/") or "."
package.path = here .. "/../?.lua;" .. here .. "/../ffi/?.lua;" .. here .. "/?.lua;" .. package.path
local core = require("core")
local JSON = require("json")
local cache = require("cache")

local ROOT = here:match("^(.*)/lib/device$") or (here .. "/../..")
local HOME = os.getenv("HOME") or "/tmp"
local M = {}

local function env_host(name)
    local raw = core.read(HOME .. "/.env")
    if not raw then return nil end
    local line = raw:match("\n?" .. name .. "=([^\n]+)") or raw:match("^" .. name .. "=([^\n]+)")
    if not line then return nil end
    local host = line:match("@([^/:]+)") or line:match("//([^/:]+)")
    return host
end

local CAMERA_IP = env_host("TPLINK_RTSP") or "192.168.1.119"

local STATIC = {
    { id = "gateway",  name = "网关/光猫", type = "gateway", ip = "192.168.1.1",   transports = { "ethernet" }, capabilities = { "network" } },
    { id = "computer", name = "主电脑",   type = "computer", ip = "192.168.1.10", transports = { "ethernet", "ssh" }, capabilities = { "compute", "ssh" } },
    { id = "nas",      name = "极空间 NAS", type = "nas",     ip = "192.168.1.53", transports = { "ethernet", "webdav" }, capabilities = { "storage", "webdav" } },
    { id = "tv",       name = "Sony 电视", type = "tv",       ip = "192.168.1.110", transports = { "ethernet", "adb" }, capabilities = { "display", "adb" } },
    { id = "camera",   name = "TP-Link 摄像头", type = "camera", ip = CAMERA_IP, transports = { "rtsp" }, capabilities = { "video", "snapshot" } },
    { id = "phone",    name = "Redmi 手机", type = "phone",    ip = os.getenv("PHONE2_IP") or "192.168.1.59", transports = { "wifi", "adb" }, capabilities = { "adb", "display", "audio" } },
    { id = "speaker",  name = "USB 小音箱", type = "speaker", transports = { "alsa" }, capabilities = { "audio" },
      sources = { audio = { kind = "alsa", sink = os.getenv("SPEAKER_SINK") or "alsa_output.usb-DUNU_DTC_480_DTC_480-00.analog-stereo" } } },
    { id = "microphone", name = "Comica 麦克风", type = "microphone", transports = { "alsa" }, capabilities = { "audio" },
      sources = { audio = { kind = "alsa", card = "Comica_EJoy" } } },
    { id = "vlc",      name = "本机播放器", type = "player", transports = { "x11" }, capabilities = { "media" } },
    { id = "mirror",   name = "手机镜像", type = "display", transports = { "adb", "x11" }, capabilities = { "display" } },
    { id = "this",     name = "客厅小机箱", type = "computer", transports = { "ethernet" }, capabilities = { "compute" } },
}

local ROLE = {
    { key = "摄像",  id = "camera" },
    { key = "电视",  id = "tv" },
    { key = "NAS",   id = "nas" },
    { key = "极空间", id = "nas" },
    { key = "主电脑", id = "computer" },
    { key = "网关",  id = "gateway" },
    { key = "本机",  id = "this" },
    { key = "小机箱", id = "this" },
}

local function role_id(d)
    local r = tostring(d.role or "")
    for _, m in ipairs(ROLE) do
        if r:find(m.key, 1, true) then return m.id end
    end
    return nil
end

local function discover()
    local raw = core.read(ROOT .. "/devices.local.json")
    local j = raw and JSON.decode(raw) or nil
    return type(j) == "table" and j.devices or {}, j and j.self or nil, j and j.network or nil
end

local function copy(d)
    local o = {}
    for k, v in pairs(d) do o[k] = v end
    o.transports = o.transports and { unpack(o.transports) } or {}
    o.capabilities = o.capabilities and { unpack(o.capabilities) } or {}
    return o
end

local function merge_found(d, f)
    if not f then return d end
    d.ip = f.ip or d.ip
    d.mac = f.mac or d.mac
    d.ports = f.ports or d.ports
    d.vendor = f.vendor or d.vendor
    d.hostname = f.hostname or d.hostname
    d.role = f.role or d.role
    d.online = f.online
    return d
end

function M.build()
    local found, self_ip, network = discover()
    local by_ip, used = {}, {}
    for _, f in ipairs(found) do by_ip[f.ip] = f end
    local devices = {}
    for _, s in ipairs(STATIC) do
        local d = copy(s)
        local f = by_ip[d.ip]
        if d.id == "this" and self_ip then d.ip = self_ip; f = by_ip[self_ip] end
        for _, x in ipairs(found) do
            local rid = role_id(x)
            if rid == d.id and not f then f = x end
        end
        merge_found(d, f)
        used[d.id] = true
        devices[#devices + 1] = d
    end
    for _, f in ipairs(found) do
        local matched = false
        for _, d in ipairs(devices) do
            if d.ip == f.ip then matched = true; break end
        end
        if not matched and f.ip and f.ip ~= self_ip then
            local id = "net." .. f.ip:gsub("%.", "_")
            devices[#devices + 1] = {
                id = id, name = f.hostname ~= "" and f.hostname or f.ip,
                type = role_id(f) or "network", ip = f.ip, mac = f.mac,
                ports = f.ports or {}, vendor = f.vendor, role = f.role,
                transports = { "ethernet" }, capabilities = { "network" },
            }
        end
    end
    local links = {}
    for _, d in ipairs(devices) do
        if d.id ~= "gateway" and d.ip then
            links[#links + 1] = { from = "gateway", to = d.id, via = "ethernet" }
        end
    end
    return {
        version = 2,
        generated = os.date("%Y-%m-%d %H:%M:%S"),
        network = network or {},
        devices = devices,
        edges = links,
    }
end

function M.refresh(force)
    local old = cache.registry()
    if old and not force then return old end
    local reg = M.build()
    local function sig(r)
        return JSON.encode({ devices = r.devices or {}, edges = r.edges or {}, network = r.network or {} })
    end
    if old and sig(old) == sig(reg) then return old end
    cache.save_registry(reg)
    cache.put_topology({ generated = reg.generated, nodes = reg.devices, edges = reg.edges })
    return reg
end

function M.list(filter)
    local reg = M.refresh()
    local out = {}
    for _, d in ipairs(reg.devices or {}) do
        local ok = true
        if filter then
            if filter.type and d.type ~= filter.type then ok = false end
            if filter.id and d.id ~= filter.id then ok = false end
        end
        if ok then out[#out + 1] = d end
    end
    return out
end

function M.get(id)
    for _, d in ipairs(M.list()) do
        if d.id == id then return d end
    end
    return nil
end

function M.role(name) return name end
function M.device(role) return M.get(role) end
function M.network() return (M.refresh().network) end
function M.path() return ROOT .. "/devices.local.json" end
function M.cache_path() return cache.dir() end
function M.topology() return cache.topology() end

return M
