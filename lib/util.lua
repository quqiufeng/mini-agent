-- util.lua — URL 编解码 / base64 / XML 反转义（无外部依赖）
local M = {}

function M.urlencode(s, safe)
    safe = safe or ""
    return (tostring(s):gsub("([^%w%-_%.~])", function(c)
        if safe:find(c, 1, true) then return c end
        return string.format("%%%02X", c:byte())
    end))
end

function M.urldecode(s)
    s = tostring(s):gsub("+", " ")
    return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

local b64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
function M.base64(s)
    local out = {}
    for i = 1, #s, 3 do
        local a, b, c = s:byte(i), s:byte(i + 1), s:byte(i + 2)
        local n = (a or 0) * 65536 + (b or 0) * 256 + (c or 0)
        local c1 = math.floor(n / 262144) % 64
        local c2 = math.floor(n / 4096) % 64
        local c3 = math.floor(n / 64) % 64
        local c4 = n % 64
        out[#out + 1] = b64:sub(c1 + 1, c1 + 1) .. b64:sub(c2 + 1, c2 + 1)
        out[#out + 1] = b and b64:sub(c3 + 1, c3 + 1) or "="
        out[#out + 1] = c and b64:sub(c4 + 1, c4 + 1) or "="
    end
    return table.concat(out)
end

function M.json_escape(s)
    s = tostring(s or "")
    s = s:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t")
    return (s:gsub("[%z\1-\31]", function(c) return string.format("\\u%04x", c:byte()) end))
end

function M.utf8_truncate(s, n)
    if #s <= n then return s end
    local i = n
    while i > 0 do
        local b = s:byte(i)
        if b and b >= 0x80 and b < 0xC0 then i = i - 1 else break end
    end
    if i > 0 then
        local b = s:byte(i)
        if b and b >= 0xC0 then i = i - 1 end
    end
    return s:sub(1, math.max(1, i))
end

function M.xml_unescape(s)
    return (tostring(s):gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&quot;", '"')
        :gsub("&apos;", "'"):gsub("&#(%d+);", function(n) return string.char(tonumber(n)) end)
        :gsub("&amp;", "&"))
end

return M
