#!/usr/bin/env luajit
-- @desc 局域网设备与拓扑扫描（LuaJIT FFI sockets）：UDP 触发 ARP + 端口探测，生成 NETWORK.local.md/devices.local.json/devices.local.env
-- @usage plugins/system/netmap.sh scan [CIDR] | show | sources
local DIR = (arg[0] or ""):match("^(.*)/") or "."
local ROOT = DIR .. "/../.."
package.path = DIR .. "/?.lua;" .. ROOT .. "/lib/?.lua;" .. package.path
local core = require("core")

local OUT_DIR = os.getenv("NETMAP_OUT_DIR") or ROOT
local PORTS = { 22, 80, 443, 554, 5005, 5555, 8000, 8080, 9000, 9222 }
local PHONE_MAC = (os.getenv("PHONE_MAC") or "76:d0:b4:67:89:a9"):lower()
local PHONE_LABEL = os.getenv("PHONE_LABEL") or "手机 Z18"
local VENDORS = {
    ["a0:36:79"] = "中国电信", ["00:d8:61"] = "Micro-Star(MSI)", ["24:97:ed"] = "极空间",
    ["b8:27:eb"] = "Raspberry Pi", ["dc:a6:32"] = "Raspberry Pi", ["e4:5f:01"] = "Raspberry Pi",
    ["f0:9f:c2"] = "Ubiquiti", ["00:1d:7e"] = "Cisco-Linksys", ["3c:84:6a"] = "TP-Link",
    ["50:c7:bf"] = "TP-Link", ["b0:be:76"] = "TP-Link", ["00:0c:29"] = "VMware",
    ["ac:84:c6"] = "TP-Link", ["c4:e9:84"] = "TP-Link", ["f4:f2:6d"] = "TP-Link",
    ["2c:f0:5d"] = "Micro-Star(MSI)", ["00:1b:21"] = "Intel", ["3c:7c:3f"] = "Intel",
    ["8c:16:45"] = "Intel", ["a4:bb:6d"] = "Intel", ["e4:54:e8"] = "Intel", ["00:1e:64"] = "Intel",
    ["d8:3a:dd"] = "Intel", ["1c:69:7a"] = "Intel", ["58:11:22"] = "H3C", ["00:23:89"] = "H3C",
    ["70:3a:cb"] = "H3C", ["00:0f:e2"] = "Huawei", ["48:46:fb"] = "Huawei", ["e0:24:7f"] = "Huawei",
    ["00:26:66"] = "Sony", ["30:f9:ed"] = "Sony", ["78:84:3c"] = "Sony", ["fc:0f:e6"] = "Sony",
    ["18:59:36"] = "Xiaomi", ["64:09:80"] = "Xiaomi", ["8c:be:be"] = "Xiaomi",
    ["dc:2c:26"] = "Espressif", ["24:0a:c4"] = "Espressif", ["84:0d:8e"] = "Espressif",
    ["00:1a:11"] = "Google", ["f4:f5:d8"] = "Google", ["00:17:88"] = "Philips Hue",
}
local KNOWN = {
    ["192.168.1.1"] = "网关/光猫", ["192.168.1.8"] = "学习机",
    ["192.168.1.10"] = "主电脑(能力主机)", ["192.168.1.53"] = "极空间 NAS",
    ["192.168.1.68"] = "客厅小机箱(本机)", ["192.168.1.59"] = "手机2 Redmi Note 14 5G（微信）",
    ["192.168.1.110"] = "Sony 电视", ["192.168.1.111"] = "TP-Link 摄像头", ["192.168.1.52"] = "H3C AP",
}
local ALIAS = {
    ["192.168.1.1"] = "GATEWAY", ["192.168.1.8"] = "STUDY", ["192.168.1.10"] = "MAINPC",
    ["192.168.1.53"] = "NAS", ["192.168.1.68"] = "MINIPC", ["192.168.1.59"] = "PHONE2",
    ["192.168.1.110"] = "TV", ["192.168.1.111"] = "CAMERA", ["192.168.1.52"] = "AP",
}

local function sh(argv)
    local out, _, rc = core.exec_argv(argv, { timeout = 30 })
    if rc ~= 0 then return "" end
    return out or ""
end
local function lines(s) local t = {}; for l in s:gmatch("[^\n]+") do t[#t + 1] = l end; return t end
local function jstr(s)
    s = tostring(s or "")
    return '"' .. s:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r") .. '"'
end
local function vendor(mac) return VENDORS[(mac or ""):sub(1, 8):lower()] or "" end

local function lan()
    for _, line in ipairs(lines(sh({"ip","-4","-o","addr","show","scope","global"}))) do
        local dev, ip, mask = line:match("^%d+:%s+(%S+)%s+inet%s+(%d+%.%d+%.%d+%.%d+)/(%d+)")
        if dev and ip and not ip:match("^198%.18%.") then
            return dev, ip, tonumber(mask), ip:match("^(%d+%.%d+%.%d+)%.")
        end
    end
    io.stderr:write("找不到局域网地址\n"); os.exit(1)
end

local function neigh(dev)
    local t = {}
    for _, line in ipairs(lines(sh({"ip","-4","neigh","show","dev",dev}))) do
        local ip, mac, state = line:match("^(%d+%.%d+%.%d+%.%d+)%s+.*lladdr%s+(%x%x:%x%x:%x%x:%x%x:%x%x:%x%x)%s+(%w+)")
        if ip then t[ip] = { mac = mac, state = state } end
    end
    return t
end

local function scan_ports(prefix, port, timeout)
    local t = {}
    for _, ip in ipairs(lines(sh({DIR .. "/netscan.sh","tcp",prefix,tostring(port),tostring(timeout or 300)}))) do
        t[ip] = true
    end
    return t
end

local function hostname(ip)
    for _, line in ipairs(lines(sh({"getent","hosts",ip}))) do
        local name = line:match("^%S+%s+(%S+)")
        if name then return name end
    end
    return ""
end

local function ipkey(ip)
    local a, b, c, d = ip:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
    return (tonumber(a) or 0) * 16777216 + (tonumber(b) or 0) * 65536 + (tonumber(c) or 0) * 256 + (tonumber(d) or 0)
end

local mode = arg[1] or "scan"
if mode == "show" then
    local f = io.open(OUT_DIR .. "/NETWORK.local.md")
    print(f and f:read("*a") or "还没有结果，先运行 netmap.sh scan")
    if f then f:close() end
    os.exit(0)
elseif mode == "sources" then
    local f = io.open(OUT_DIR .. "/devices.local.env")
    print(f and f:read("*a") or "还没有结果，先运行 netmap.sh scan")
    if f then f:close() end
    os.exit(0)
end

local dev, me, mask, prefix = lan()
local net = prefix .. ".0/" .. tostring(mask)
local cidr = arg[2]
if cidr then
    local a, b, c, m = cidr:match("^(%d+)%.(%d+)%.(%d+)%.%d+/(%d+)$")
    if a then prefix = a .. "." .. b .. "." .. c; mask = tonumber(m); net = prefix .. ".0/" .. tostring(mask) end
end
print(string.format("扫描 %s (%s)，本机 %s …", net, dev, me))

sh({DIR .. "/netscan.sh","udp",prefix})
core.sleep(1.5)
local table_ = neigh(dev)
local alive, ports = {}, {}
alive[me] = true
for ip in pairs(table_) do alive[ip] = true end
for _, port in ipairs(PORTS) do
    for ip in pairs(scan_ports(prefix, port, 350)) do
        alive[ip] = true
        ports[ip] = ports[ip] or {}
        table.insert(ports[ip], port)
    end
end

local devices = {}
for ip in pairs(alive) do
    local info = table_[ip] or {}
    local p = ports[ip] or {}
    if ip == me or info.mac or #p > 0 then
        local d = {
            ip = ip, mac = info.mac or "", vendor = vendor(info.mac or ""),
            hostname = hostname(ip), ports = p, self = (ip == me),
        }
        devices[#devices + 1] = d
    end
end
table.sort(devices, function(a, b) return ipkey(a.ip) < ipkey(b.ip) end)

for _, d in ipairs(devices) do
    d.role = KNOWN[d.ip] or ""
    if d.role == "" then
        if d.mac:lower() == PHONE_MAC then d.role = PHONE_LABEL
        elseif #d.ports > 0 then
            local has = {}
            for _, p in ipairs(d.ports) do has[p] = true end
            if has[5005] then d.role = "NAS/WebDAV"
            elseif has[554] then d.role = "摄像头/RTSP"
            elseif has[5555] then d.role = "Android/TV(adb)"
            elseif has[9222] then d.role = "Chrome 调试"
            elseif has[22] then d.role = "SSH 主机"
            end
        end
    end
end

local ts = os.date("%Y-%m-%d %H:%M:%S")
local md = { "# 局域网拓扑（本机扫描）", "", string.format("> 生成：%s；网段：%s；本机：%s（%s）", ts, net, me, dev), "", "```text" }
md[#md + 1] = (KNOWN["192.168.1.1"] or "网关") .. "  192.168.1.1"
for _, d in ipairs(devices) do
    if d.ip ~= "192.168.1.1" then
        local label = d.role ~= "" and d.role or (d.hostname ~= "" and d.hostname or (d.vendor ~= "" and d.vendor or "未识别设备"))
        local detail = d.ip
        if d.hostname ~= "" and d.hostname ~= label then detail = detail .. " " .. d.hostname end
        if d.vendor ~= "" and d.vendor ~= label then detail = detail .. " [" .. d.vendor .. "]" end
        if d.mac ~= "" then detail = detail .. " mac=" .. d.mac end
        if #d.ports > 0 then detail = detail .. " ports=" .. table.concat(d.ports, ",") end
        md[#md + 1] = "  ├─ " .. label .. "  " .. detail
    end
end
md[#md + 1] = "```"; md[#md + 1] = ""
local md_s = table.concat(md, "\n")
local f = assert(io.open(OUT_DIR .. "/NETWORK.local.md", "w")); f:write(md_s); f:close()

local objs = {}
for _, d in ipairs(devices) do
    local ps = {}
    for i, p in ipairs(d.ports) do ps[i] = tostring(p) end
    objs[#objs + 1] = string.format('{"ip":%s,"mac":%s,"vendor":%s,"hostname":%s,"ports":[%s],"self":%s,"role":%s}',
        jstr(d.ip), jstr(d.mac), jstr(d.vendor), jstr(d.hostname), table.concat(ps, ","),
        d.self and "true" or "false", jstr(d.role))
end
local json = string.format('{"generated":%s,"network":%s,"self":%s,"devices":[%s]}',
    jstr(ts), jstr(net), jstr(me), table.concat(objs, ","))
f = assert(io.open(OUT_DIR .. "/devices.local.json", "w")); f:write(json); f:close()

local env = { 'NETMAP_SELF="' .. me .. '"', 'NETMAP_NET="' .. net .. '"' }
local used = {}
for _, d in ipairs(devices) do
    local key = ALIAS[d.ip]
    if not key and d.role == PHONE_LABEL then key = "PHONE" end
    if not key then
        key = (d.hostname ~= "" and d.hostname or d.role):upper():gsub("[^A-Z0-9]+", "_"):gsub("^_+", ""):gsub("_+$", "")
    end
    if key == "" then key = "DEV_" .. d.ip:match("(%d+)$") end
    if used[key] then key = key .. "_" .. d.ip:match("(%d+)$") end
    used[key] = true
    env[#env + 1] = 'NETMAP_' .. key .. '_IP="' .. d.ip .. '"'
end
f = assert(io.open(OUT_DIR .. "/devices.local.env", "w")); f:write(table.concat(env, "\n") .. "\n"); f:close()
print(md_s)
print(string.format("已写入 %s/NETWORK.local.md, devices.local.json, devices.local.env", OUT_DIR))
