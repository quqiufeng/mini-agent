#!/usr/bin/env luajit
-- @desc 电视直连 NAS 播放：本机拼 WebDAV 直链 + adb 唤起电视 VLC（LuaJIT FFI: libcurl）
-- @usage tv_play.lua <关键词> | <NAS相对路径> | --find <关键词> | stop
local DIR = (arg[0] or ""):match("^(.*)/") or "."
local ROOT = DIR .. "/../.."
package.path = DIR .. "/?.lua;" .. ROOT .. "/tools/?.lua;" .. ROOT .. "/lib/?.lua;" .. ROOT .. "/lib/device/?.lua;" .. package.path
local core = require("core")
local http = require("http")
local U = require("util")
local ffi = require("ffi")
ffi.cdef[[int usleep(unsigned int usec);]]

local function tv_serial()
    local ok, reg = pcall(require, "registry")
    if ok then
        local d = reg.get("tv")
        if d and d.ip then return d.ip .. ":5555" end
    end
    return "192.168.1.110:5555"
end
local TV = os.getenv("TV_SERIAL") or tv_serial()
local VLC = "org.videolan.vlc/.StartActivity"
local VIDEO_EXT = { [".mkv"] = true, [".mp4"] = true, [".avi"] = true, [".ts"] = true,
    [".m2ts"] = true, [".mov"] = true, [".wmv"] = true, [".flv"] = true,
    [".webm"] = true, [".rmvb"] = true, [".iso"] = true }
local SKIP = { [".bt"] = true, [".lyricdownload"] = true, [".subtitledownload"] = true,
    ["Pictures"] = true, ["DCIM"] = true, ["微博图"] = true, ["book"] = true, ["手机备份"] = true }

local function load_env()
    local e = {}
    local f = io.open((os.getenv("HOME") or "") .. "/.env", "r")
    if not f then return e end
    for line in f:lines() do
        line = line:gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" and line:sub(1, 1) ~= "#" then
            local k, v = line:match("^([^=]+)=(.*)$")
            if k then e[k] = v:gsub('^"', ""):gsub('"$', ""):gsub("^'", ""):gsub("'$", "") end
        end
    end
    f:close()
    return e
end

local function propfind(url, auth)
    local body = '<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop>' ..
        '<d:resourcetype/><d:getcontentlength/></d:prop></d:propfind>'
    local b, s = http.request({
        url = url, method = "PROPFIND",
        headers = { "Depth: 1", "Content-Type: application/xml" },
        body = body, auth = auth, timeout = 20,
    })
    if not b or (s ~= 207 and s ~= 200) then return nil end
    local out = {}
    for block in b:gmatch("<[^>]*response[^>]*>(.-)</[^>]*response>") do
        local href = block:match("<[^>]*href[^>]*>(.-)</[^>]*href>")
        if href then
            href = U.xml_unescape(href)
            local coll = block:find("<[^>]*collection") ~= nil or href:sub(-1) == "/"
            local len = tonumber(block:match("<[^>]*getcontentlength[^>]*>(%d+)<")) or 0
            out[#out + 1] = { href = href, coll = coll, len = len }
        end
    end
    return out
end

local function q(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end

local function replace_plain(s, needle, repl)
    if needle == "" then return s end
    local out, i = {}, 1
    while true do
        local a, b = s:find(needle, i, true)
        if not a then out[#out + 1] = s:sub(i); break end
        out[#out + 1] = s:sub(i, a - 1)
        out[#out + 1] = repl
        i = b + 1
    end
    return table.concat(out)
end

local function propfind_many(dirs)
    local entries = {}
    for _, d in ipairs(dirs) do
        local out = core.exec_argv({ DIR .. "/../../tools/lua.sh", DIR .. "/tv_propfind.lua", d }, { timeout = 20 })
        if out then
            for line in out:gmatch("[^\n]+") do
                local kind, len, href = line:match("^([CF])\t(%d+)\t(.+)$")
                if href then entries[#entries + 1] = { coll = kind == "C", len = tonumber(len), href = href } end
            end
        end
    end
    return entries
end

local function search(root, kw, auth, origin)
    kw = kw:lower()
    local frontier = { root .. "/" }
    local seen = { [root .. "/"] = true }
    local found, total = {}, 0
    local deadline = os.time() + 30
    while #frontier > 0 and os.time() < deadline do
        total = total + #frontier
        local entries = propfind_many(frontier)
        local nxt = {}
        for _, e in ipairs(entries) do
            local name = U.urldecode((e.href:gsub("/+$", ""):match("([^/]+)$") or ""))
            if e.coll then
                if not SKIP[name] and not (name:sub(1, 1) == "." and name ~= ".") then
                    local full = e.href:match("^https?://") and e.href or (origin .. e.href)
                    local dd = full:gsub("/+$", "") .. "/"
                    if not seen[dd] then seen[dd] = true; nxt[#nxt + 1] = dd end
                end
            else
                local ext = name:match("%.([^.]+)$")
                ext = ext and ("." .. ext:lower())
                if ext and VIDEO_EXT[ext] and name:lower():find(kw, 1, true) then
                    found[#found + 1] = { len = e.len, href = e.href }
                end
            end
        end
        io.stderr:write(string.format("\r搜索中… %d 目录, 命中 %d ", total, #found))
        if #found > 0 then break end
        table.sort(nxt, function(a, b)
            local am = U.urldecode(a):lower():find(kw, 1, true) and 1 or 0
            local bm = U.urldecode(b):lower():find(kw, 1, true) and 1 or 0
            if am ~= bm then return am > bm end
            return a < b
        end)
        frontier = nxt
    end
    io.stderr:write("\n")
    table.sort(found, function(a, b) return a.len > b.len end)
    return found
end

local function adb(args, timeout)
    local argv = { "adb", "-s", TV }
    for _, a in ipairs(args) do argv[#argv + 1] = a end
    local out, _, rc = core.exec_argv(argv, { timeout = timeout or 20 })
    if rc ~= 0 and not out then return "" end
    return out or ""
end

local args = {}
for i = 1, #arg do args[#args + 1] = arg[i] end
if #args == 0 or args[1] == "-h" or args[1] == "--help" then
    io.stderr:write("用法: tv_play.sh <关键词> | <NAS相对路径> | --find <关键词> | stop\n")
    os.exit(2)
end
local find_only = args[1] == "--find"
local arg1 = find_only and (args[2] or "") or args[1]
if arg1 == "stop" then adb({"shell","input","keyevent","4"}); print("已发送返回键"); os.exit(0) end
if arg1 == "" then io.stderr:write("用法: tv_play.sh --find <关键词>\n"); os.exit(2) end

local e = load_env()
local base = (e.WEBDAV_URL or ""):gsub("/+$", "")
local share = e.WEBDAV_SHARE or "sata11-18072858035"
local user, pass = e.WEBDAV_USER or "", e.WEBDAV_PASS or ""
local root = base .. "/" .. U.urlencode(share)
local auth = user .. ":" .. pass
local url

if arg1:match("^https?://") then
    url = arg1
else
    local rel, found
    if arg1:find("/", 1, true) or arg1:match("%.[A-Za-z0-9]+$") then
        rel = arg1:gsub("^/+", ""):gsub("/+$", "")
    else
        found = search(root, arg1, auth, base)
        if #found == 0 then io.stderr:write("没找到包含「" .. arg1 .. "」的视频\n"); os.exit(1) end
        local href = U.urldecode(found[1].href)
        rel = href:match("/" .. share:gsub("([^%w])", "%%%1") .. "/(.*)$") or href:gsub("^/+", "")
        if #found > 1 then
            io.stderr:write(string.format("命中 %d 个，选最大：%s\n", #found, rel:match("([^/]+)$") or rel))
        end
        if find_only then
            for i = 1, math.min(10, #found) do
                print(string.format("%8.1f MB  %s", found[i].len / 1048576, U.urldecode(found[i].href)))
            end
            os.exit(0)
        end
    end
    if find_only then
        print(rel)
        os.exit(0)
    end
    local enc = {}
    for part in rel:gmatch("[^/]+") do enc[#enc + 1] = U.urlencode(part) end
    local scheme, host = base:match("^(https?://)(.*)$")
    local cred = U.urlencode(user) .. ":" .. U.urlencode(pass)
    url = scheme .. cred .. "@" .. host .. "/" .. U.urlencode(share) .. "/" .. table.concat(enc, "/")
end

local disp = replace_plain(replace_plain(url, U.urlencode(pass), "***"), pass, "***")
if os.getenv("TV_PLAY_DRY") == "1" then print("URL " .. disp); os.exit(0) end
adb({"connect",TV})
adb({"shell","input","keyevent","224"})
ffi.C.usleep(500000)
local out = adb({"shell","am","start","-a","android.intent.action.VIEW","-d",url,
    "-t","video/x-matroska","-n",VLC}, 25)
if out:find("Error") or out:find("Exception") then
    io.stderr:write("adb 启动失败：\n" .. out)
    os.exit(1)
end
print("已在电视播放：" .. disp)
