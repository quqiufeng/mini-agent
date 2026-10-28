#!/usr/bin/env luajit
-- @desc WebDAV PROPFIND 单目录（tv_play 并行搜索用）；输出 C/F <len> <href>
local DIR = (arg[0] or ""):match("^(.*)/") or "."
package.path = DIR .. "/?.lua;" .. package.path
local http = require("http")
local U = require("util")
local url = arg[1]
if not url then os.exit(2) end
local e = {}
local f = io.open((os.getenv("HOME") or "") .. "/.env", "r")
if f then
    for line in f:lines() do
        local k, v = line:match("^%s*([^#=]+)=(.*)$")
        if k then
            v = v:gsub('^"', ""):gsub('"$', ""):gsub("^'", ""):gsub("'$", "")
            e[k:gsub("%s+$", "")] = v
        end
    end
    f:close()
end
local auth = (e.WEBDAV_USER or "") .. ":" .. (e.WEBDAV_PASS or "")
local body = '<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/><d:getcontentlength/></d:prop></d:propfind>'
local b, s = http.request({ url = url, method = "PROPFIND",
    headers = { "Depth: 1", "Content-Type: application/xml" },
    body = body, auth = auth, timeout = 20 })
if not b or (s ~= 207 and s ~= 200) then os.exit(1) end
for block in b:gmatch("<[^>]*response[^>]*>(.-)</[^>]*response>") do
    local href = block:match("<[^>]*href[^>]*>(.-)</[^>]*href>")
    if href then
        href = U.xml_unescape(href)
        local coll = block:find("<[^>]*collection") ~= nil or href:sub(-1) == "/"
        local len = tonumber(block:match("<[^>]*getcontentlength[^>]*>(%d+)<")) or 0
        print((coll and "C" or "F") .. "\t" .. len .. "\t" .. href)
    end
end
