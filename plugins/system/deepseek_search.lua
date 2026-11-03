-- deepseek_search.lua — DeepSeek Search/Fetch（LuaJIT FFI: libcurl + libjson-c）
local DIR = (arg[0] or ""):match("^(.*)/") or "."
local ROOT = DIR .. "/../.."
package.path = DIR .. "/?.lua;" .. ROOT .. "/tools/?.lua;" .. ROOT .. "/lib/?.lua;" .. package.path
local http = require("http")
local J = require("jsonc")

local BASE = "https://api.deepseek.com"

local function json_escape(s)
    s = tostring(s)
    s = s:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t")
    s = s:gsub("[%z\1-\31]", function(c) return string.format("\\u%04x", c:byte()) end)
    return s
end

local function api_key()
    local k = os.getenv("DEEPSEEK_API_KEY")
    if k and k ~= "" then return k end
    local path = (os.getenv("HOME") or "") .. "/.local/share/opencode/auth.json"
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*a"); f:close()
    local o = J.parse(s)
    if not o then return nil end
    local key = J.str(o, "deepseek.key")
    J.free(o)
    return key
end

local function post(path, body)
    local key = api_key()
    if not key then return nil, "未找到 DEEPSEEK_API_KEY（~/.env 或 opencode auth.json）" end
    local res, status, err = http.request({
        url = BASE .. path,
        headers = {
            "Authorization: Bearer " .. key,
            "Content-Type: application/json",
        },
        body = body,
        timeout = 40,
    })
    if not res then return nil, err or "curl 失败" end
    if status < 200 or status >= 300 then
        local o = J.parse(res)
        local msg = o and J.str(o, "error.message") or (res:sub(1, 200))
        if o then J.free(o) end
        return nil, "DeepSeek API " .. tostring(status) .. ": " .. tostring(msg)
    end
    return res
end

local function usage()
    io.stderr:write([=[用法:
  plugins/system/deepseek_search.sh "查询" [--count N] [--content] [--json]
  plugins/system/deepseek_search.sh fetch <url> [--max-chars N] [--json]
]=])
    os.exit(2)
end

local mode = "search"
local args = {}
for i = 1, #arg do args[#args + 1] = arg[i] end
if args[1] == "fetch" then mode = "fetch"; table.remove(args, 1) end

local count, need_content, as_json, max_chars = 8, false, false, 6000
local query = {}
local i = 1
while i <= #args do
    local a = args[i]
    if a == "--help" or a == "-h" then
        print([=[用法:
  plugins/system/deepseek_search.sh "查询" [--count N] [--content] [--json]
  plugins/system/deepseek_search.sh fetch <url> [--max-chars N] [--json]
]=])
        os.exit(0)
    elseif a == "--count" and args[i + 1] then count = tonumber(args[i + 1]) or 8; i = i + 2
    elseif a == "--content" then need_content = true; i = i + 1
    elseif a == "--json" then as_json = true; i = i + 1
    elseif a == "--max-chars" and args[i + 1] then max_chars = tonumber(args[i + 1]) or 6000; i = i + 2
    else query[#query + 1] = a; i = i + 1
    end
end
local text = table.concat(query, " "):gsub("^%s+", ""):gsub("%s+$", "")
if text == "" then usage() end

if mode == "fetch" then
    local res, err = post("/v1/tools/fetch", '{"url":"' .. json_escape(text) .. '"}')
    if not res then io.stderr:write("[deepseek] " .. err .. "\n"); os.exit(1) end
    if as_json then print(res); os.exit(0) end
    local o = J.parse(res)
    if not o then io.stderr:write("[deepseek] 响应解析失败\n"); os.exit(1) end
    print("# " .. (J.str(o, "title") or ""))
    print()
    local c = J.str(o, "content") or ""
    if #c > max_chars then c = c:sub(1, max_chars) .. "\n...(截断)" end
    print(c)
    J.free(o)
    os.exit(0)
end

count = math.max(1, math.min(50, count))
local body = string.format('{"query":"%s","count":%d,"need_content":%s}',
    json_escape(text), count, need_content and "true" or "false")
local res, err = post("/v1/tools/search", body)
if not res then io.stderr:write("[deepseek] " .. err .. "\n"); os.exit(1) end
if as_json then print(res); os.exit(0) end

local o = J.parse(res)
if not o then io.stderr:write("[deepseek] 响应解析失败\n"); os.exit(1) end
local n = J.len(o, "results")
if n == 0 then print("无结果"); J.free(o); os.exit(0) end
for idx = 0, n - 1 do
    local p = "results." .. idx .. "."
    print(string.format("[%d] %s", idx + 1, J.str(o, p .. "title") or "(无标题)"))
    print("    " .. (J.str(o, p .. "url") or ""))
    local site = J.str(o, p .. "site_name")
    if site and site ~= "" then print("    来源: " .. site) end
    local date = J.str(o, p .. "date")
    if date and date ~= "" then print("    时间: " .. date) end
    local summary = J.str(o, p .. "summary") or J.str(o, p .. "snippet") or ""
    if summary ~= "" then print("    " .. summary:gsub("^%s+", ""):gsub("%s+$", "")) end
    if need_content then
        local c = J.str(o, p .. "content")
        if c and c ~= "" then
            if #c > max_chars then c = c:sub(1, max_chars) .. "\n...(截断)" end
            print("    --- 正文 ---")
            print("    " .. c:gsub("\n", "\n    "))
        end
    end
    print()
end
J.free(o)
