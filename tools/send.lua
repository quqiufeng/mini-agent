-- send.lua — 把文本提交给本地大脑（LuaJIT FFI: libcurl）
local DIR = (arg[0] or ""):match("^(.*)/") or "."
package.path = DIR .. "/?.lua;" .. package.path
local http = require("http")

local port = os.getenv("AGENT_PORT") or "4097"
local text = arg[1] or ""
if text == "" then
    io.stderr:write("usage: send.lua <text>\n")
    os.exit(2)
end
local base = "http://127.0.0.1:" .. port

local function esc(s)
    s = s:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t")
    return (s:gsub("[%z\1-\31]", function(c) return string.format("\\u%04x", c:byte()) end))
end

local function post(path, body)
    local res, status, err = http.request({
        url = base .. path,
        headers = { "Content-Type: application/json" },
        body = body,
        timeout = 10,
    })
    if not res or status < 200 or status >= 300 then
        io.stderr:write(string.format("[send] %s failed: status=%s err=%s %s\n",
            path, tostring(status), tostring(err), tostring(res and res:sub(1, 200) or "")))
        return false
    end
    return true
end

if not post("/tui/append-prompt", '{"text":"' .. esc(text) .. '"}') then os.exit(1) end
if not post("/tui/submit-prompt", "{}") then os.exit(1) end
print("sent")
