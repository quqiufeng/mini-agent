-- lib/json.lua — 轻量 JSON 编解码（Lua 实现，不依赖 Python）
local M = {}

local function utf8_char(cp)
    if cp < 0x80 then return string.char(cp) end
    if cp < 0x800 then
        return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + cp % 0x40)
    end
    if cp < 0x10000 then
        return string.char(0xE0 + math.floor(cp / 0x1000),
                           0x80 + math.floor(cp / 0x40) % 0x40,
                           0x80 + cp % 0x40)
    end
    return string.char(0xF0 + math.floor(cp / 0x40000),
                       0x80 + math.floor(cp / 0x1000) % 0x40,
                       0x80 + math.floor(cp / 0x40) % 0x40,
                       0x80 + cp % 0x40)
end

function M.decode(s)
    if type(s) ~= "string" then return nil end
    local i, n = 1, #s
    local function fail(msg)
        error(string.format("json: %s at %d", msg, i), 0)
    end
    local function skip()
        while i <= n and s:sub(i, i):match("%s") do i = i + 1 end
    end
    local parse_value
    local function parse_string()
        i = i + 1
        local out = {}
        while i <= n do
            local c = s:sub(i, i)
            if c == '"' then
                i = i + 1
                return table.concat(out)
            elseif c == "\\" then
                local e = s:sub(i + 1, i + 1)
                i = i + 2
                if e == '"' or e == "\\" or e == "/" then out[#out + 1] = e
                elseif e == "b" then out[#out + 1] = "\b"
                elseif e == "f" then out[#out + 1] = "\f"
                elseif e == "n" then out[#out + 1] = "\n"
                elseif e == "r" then out[#out + 1] = "\r"
                elseif e == "t" then out[#out + 1] = "\t"
                elseif e == "u" then
                    local hex = s:sub(i, i + 3)
                    if #hex < 4 or not hex:match("^%x%x%x%x$") then fail("bad unicode") end
                    local cp = tonumber(hex, 16)
                    i = i + 4
                    if cp >= 0xD800 and cp <= 0xDBFF then
                        if s:sub(i, i + 1) ~= "\\u" then fail("bad surrogate") end
                        local lo = tonumber(s:sub(i + 2, i + 5), 16)
                        if not lo or lo < 0xDC00 or lo > 0xDFFF then fail("bad surrogate") end
                        i = i + 6
                        cp = 0x10000 + (cp - 0xD800) * 0x400 + (lo - 0xDC00)
                    end
                    out[#out + 1] = utf8_char(cp)
                else
                    fail("bad escape")
                end
            else
                out[#out + 1] = c
                i = i + 1
            end
        end
        fail("unterminated string")
    end
    local function parse_number()
        local start = i
        if s:sub(i, i) == "-" then i = i + 1 end
        while i <= n and s:sub(i, i):match("%d") do i = i + 1 end
        if s:sub(i, i) == "." then
            i = i + 1
            while i <= n and s:sub(i, i):match("%d") do i = i + 1 end
        end
        local e = s:sub(i, i)
        if e == "e" or e == "E" then
            i = i + 1
            if s:sub(i, i) == "+" or s:sub(i, i) == "-" then i = i + 1 end
            while i <= n and s:sub(i, i):match("%d") do i = i + 1 end
        end
        local num = tonumber(s:sub(start, i - 1))
        if not num then fail("bad number") end
        return num
    end
    function parse_value()
        skip()
        local c = s:sub(i, i)
        if c == "{" then
            i = i + 1
            local obj = {}
            skip()
            if s:sub(i, i) == "}" then i = i + 1; return obj end
            while true do
                skip()
                if s:sub(i, i) ~= '"' then fail("expected key") end
                local k = parse_string()
                skip()
                if s:sub(i, i) ~= ":" then fail("expected colon") end
                i = i + 1
                obj[k] = parse_value()
                skip()
                local d = s:sub(i, i)
                if d == "," then i = i + 1
                elseif d == "}" then i = i + 1; return obj
                else fail("expected comma or }") end
            end
        elseif c == "[" then
            i = i + 1
            local arr = {}
            skip()
            if s:sub(i, i) == "]" then i = i + 1; return arr end
            while true do
                arr[#arr + 1] = parse_value()
                skip()
                local d = s:sub(i, i)
                if d == "," then i = i + 1
                elseif d == "]" then i = i + 1; return arr
                else fail("expected comma or ]") end
            end
        elseif c == '"' then
            return parse_string()
        elseif s:sub(i, i + 3) == "true" then i = i + 4; return true
        elseif s:sub(i, i + 4) == "false" then i = i + 5; return false
        elseif s:sub(i, i + 3) == "null" then i = i + 4; return nil
        else
            return parse_number()
        end
    end
    local ok, v = pcall(parse_value)
    if not ok then return nil, v end
    skip()
    if i <= n then return nil, "trailing data" end
    return v
end

local ESC = { ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b",
              ["\f"] = "\\f", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }

local function quote(s)
    return '"' .. s:gsub('[%z\1-\31"\\]', function(c)
        return ESC[c] or string.format("\\u%04x", c:byte())
    end) .. '"'
end

local function is_array(t)
    local n = 0
    for k in pairs(t) do
        if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then return false end
        n = n + 1
    end
    for k in pairs(t) do if k > n then return false end end
    return n > 0
end

local function enc(v, stack)
    local tv = type(v)
    if v == nil then return "null"
    elseif tv == "boolean" then return v and "true" or "false"
    elseif tv == "number" then
        if v ~= v or v == math.huge or v == -math.huge then return "null" end
        return string.format("%.17g", v)
    elseif tv == "string" then return quote(v)
    elseif tv == "table" then
        if stack[v] then error("json: circular reference") end
        stack[v] = true
        local out = {}
        if is_array(v) then
            for i = 1, #v do out[#out + 1] = enc(v[i], stack) end
            stack[v] = nil
            return "[" .. table.concat(out, ",") .. "]"
        end
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        for _, k in ipairs(keys) do
            out[#out + 1] = quote(tostring(k)) .. ":" .. enc(v[k], stack)
        end
        stack[v] = nil
        return "{" .. table.concat(out, ",") .. "}"
    end
    return "null"
end

function M.encode(v)
    local ok, out = pcall(enc, v, {})
    if not ok then return nil, out end
    return out
end

return M
