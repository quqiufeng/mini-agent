#!/usr/bin/env luajit
-- @desc 本地 Google 搜索：Chrome CDP（LuaJIT FFI WebSocket），提取正文和外部链接
-- @usage tools/google_search.lua "关键词" [count] [port]
local DIR = (arg[0] or ""):match("^(.*)/") or "."
local ROOT = DIR .. "/../.."
package.path = DIR .. "/?.lua;" .. ROOT .. "/tools/?.lua;" .. ROOT .. "/lib/?.lua;" .. package.path
local http = require("http")
local J = require("jsonc")
local U = require("util")
local ws = require("ws")
local ffi = require("ffi")
ffi.cdef[[int usleep(unsigned int usec);]]

local query = arg[1] or ""
local count = tonumber(arg[2] or "10") or 10
local port = arg[3] or os.getenv("CDP_PORT") or "9222"
if query == "" then io.stderr:write("用法: google_search.sh \"关键词\" [count]\n"); os.exit(2) end
local url = "https://www.google.com/search?q=" .. U.urlencode(query) ..
    "&num=" .. math.max(1, math.min(30, count)) .. "&hl=zh-CN"

local body, status = http.request({ url = "http://127.0.0.1:" .. port .. "/json/new?about:blank", method = "PUT", timeout = 10 })
if not body or status ~= 200 then io.stderr:write("[google] 创建 target 失败\n"); os.exit(1) end
local target = J.parse(body)
local tid = target and J.str(target, "id") or nil
local wsurl = target and J.str(target, "webSocketDebuggerUrl") or nil
if not tid or not wsurl then io.stderr:write("[google] target 无 ws url\n"); os.exit(1) end

local conn, cerr = ws.connect(wsurl, 10000)
if not conn then io.stderr:write("[google] WebSocket 失败: " .. tostring(cerr) .. "\n"); os.exit(1) end

local function call(id, method, params)
    local msg = string.format('{"id":%d,"method":"%s","params":%s}', id, method, params or "{}")
    conn:send_text(msg)
    local deadline = os.time() + 20
    while os.time() < deadline do
        local reply, err = conn:recv_text(20000)
        if not reply then return nil, err end
        local o = J.parse(reply)
        if o then
            if J.int(o, "id") == id then return o end
            J.free(o)
        end
    end
    return nil, "timeout"
end

local function evaluate(expr, id)
    local o = call(id, "Runtime.evaluate", '{"expression":"' .. U.json_escape(expr) .. '","returnByValue":true}')
    if not o then return nil end
    local v = J.str(o, "result.result.value")
    J.free(o)
    return v
end

local nav = call(1, "Page.navigate", '{"url":"' .. U.json_escape(url) .. '"}')
if not nav then conn:close(); io.stderr:write("[google] 导航失败/超时\n"); os.exit(3) end
J.free(nav)

local ready = false
for _ = 1, 40 do
    ffi.C.usleep(500000)
    local state = evaluate("document.readyState", 100)
    if state == "complete" then
        local n = tonumber(evaluate("document.body ? document.body.innerText.length : 0", 101) or "0")
        if n and n > 300 then ready = true; break end
    end
end

local expr = [==[
(() => {
  const txt = document.body ? document.body.innerText : '';
  const links = Array.from(document.querySelectorAll('a[href^="http"]'))
    .map(a => ({t: (a.innerText || '').trim(), h: a.href}))
    .filter(x => {
      if (!x.t) return false;
      try {
        const h = new URL(x.h).hostname;
        return !/google\.(com|com\.hk)|accounts\.google|support\.google|policies\.google/.test(h);
      } catch (e) { return false; }
    });
  return JSON.stringify({txt, links});
})()
]==]
local data = evaluate(expr, 102)
local txt, links = "", {}
if data then
    local o = J.parse(data)
    if o then
        txt = J.str(o, "txt") or ""
        links = J.get(o, "links") or {}
        -- keep parsed object alive for links; copy strings below
        local n = J.len(links)
        local copy = {}
        for i = 0, n - 1 do
            copy[#copy + 1] = { t = J.str(links, i .. ".t") or "", h = J.str(links, i .. ".h") or "" }
        end
        links = copy
        J.free(o)
    end
end

conn:close()
http.request({ url = "http://127.0.0.1:" .. port .. "/json/close/" .. tid, timeout = 5 })
if target then J.free(target) end

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
txt = trim(txt)
for _, marker in ipairs({ "搜索结果", "AI 概览" }) do
    local i = txt:find(marker, 1, true)
    if i then txt = txt:sub(i); break end
end
txt = trim(txt)
local blocked = false
for _, m in ipairs({ "reCAPTCHA", "unusual traffic", "enablejs", "consent.google", "我们的系统检测到" }) do
    if txt:find(m, 1, true) then blocked = true; break end
end
if blocked then io.stderr:write("[google] Google 拦截/CAPTCHA\n"); os.exit(3) end
if txt == "" then io.stderr:write("[google] 没有提取到结果\n"); os.exit(3) end

print("[Google] " .. query .. "\n")
print(U.utf8_truncate(txt, 3500))
if #links > 0 then
    print("\nLinks:")
    local seen, n = {}, 0
    for _, x in ipairs(links) do
        local key = x.t .. "\t" .. x.h
        if not seen[key] then
            seen[key] = true
            print("- " .. x.t .. " | " .. x.h)
            n = n + 1
            if n >= 10 then break end
        end
    end
end
