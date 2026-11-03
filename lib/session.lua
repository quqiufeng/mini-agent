-- lib/session.lua — 会话模式（kvcache 后端，TTL + 单写）
local here = (arg and arg[0] or ""):match("^(.*)/") or "."
package.path = here .. "/?.lua;" .. here .. "/ffi/?.lua;" .. package.path
local KV = require("kv")

local HOME = os.getenv("HOME") or "/tmp"
local DB_DIR = os.getenv("MYAGENT_KV_DIR") or (HOME .. "/.myagent/kv")
local DEFAULT_TTL = tonumber(os.getenv("SESSION_TTL") or "1800")
local S = {}
local db

local function open()
    if not db then
        db = KV.open(DB_DIR, 64 * 1024 * 1024)
        assert(db, "session: cache_open failed: " .. DB_DIR)
    end
    return db
end

local function key(id) return "session." .. id end

function S.valid_id(id)
    return type(id) == "string" and #id > 0 and #id <= 128 and id:match("^[A-Za-z0-9_:.%%/%-]+$") ~= nil
end

local function parse(text)
    if not text then return nil end
    local o = { init = {}, context = {} }
    for line in text:gmatch("[^\n]+") do
        local k, v = line:match("^([^=]+)=(.*)$")
        if k then
            if k:sub(1, 5) == "init." then o.init[k:sub(6)] = v
            elseif k:sub(1, 8) == "context." then o.context[k:sub(9)] = v
            elseif k == "since" then o.since = tonumber(v)
            elseif k == "until" then o.until_ts = tonumber(v)
            else o[k] = v end
        end
    end
    return o
end

local function encode(o)
    local t = { "plugin=" .. tostring(o.plugin or ""), "source=" .. tostring(o.source or "") }
    t[#t + 1] = "since=" .. tostring(o.since or os.time())
    t[#t + 1] = "until=" .. tostring(o.until_ts or (os.time() + DEFAULT_TTL))
    for k, v in pairs(o.init or {}) do t[#t + 1] = "init." .. k .. "=" .. tostring(v) end
    for k, v in pairs(o.context or {}) do t[#t + 1] = "context." .. k .. "=" .. tostring(v) end
    return table.concat(t, "\n")
end

function S.enter(id, plugin, opts)
    opts = opts or {}
    if not S.valid_id(id) then return nil, "bad session id" end
    local ttl = tonumber(opts.ttl or DEFAULT_TTL)
    local o = {
        plugin = plugin,
        source = opts.source or "",
        since = os.time(),
        until_ts = os.time() + ttl,
        init = opts.init or {},
        context = opts.context or {},
    }
    local ok = open():set(key(id), encode(o), ttl * 1000)
    return ok and o or nil
end

function S.get(id)
    if not S.valid_id(id) then return nil end
    local o = parse(open():get(key(id)))
    if not o then return nil end
    if o.until_ts and o.until_ts <= os.time() then
        open():del(key(id))
        return nil
    end
    return o
end

function S.touch(id, ttl)
    local o = S.get(id)
    if not o then return nil end
    ttl = tonumber(ttl or DEFAULT_TTL)
    o.until_ts = os.time() + ttl
    open():set(key(id), encode(o), ttl * 1000)
    return o
end

function S.exit(id)
    if not S.valid_id(id) then return false end
    return open():del(key(id))
end

function S.route(text, manifests, current_id)
    local plugin, args = text:match("^#([%w_%-]+)@?(.*)$")
    if plugin then return { plugin = plugin, args = args, explicit = true } end
    if current_id then
        local cur = S.get(current_id)
        if cur then
            local m = manifests and manifests[cur.plugin]
            if m and m.session_commands then
                for cmd, action in pairs(m.session_commands) do
                    if text:sub(1, #cmd) == cmd then
                        return { plugin = cur.plugin, action = action, text = text, session = cur }
                    end
                end
            end
        end
    end
    for name, m in pairs(manifests or {}) do
        for _, intent in ipairs(m.intents or {}) do
            if text:find(intent, 1, true) then
                return { plugin = name, intent = intent, text = text }
            end
        end
    end
    return nil
end

function S.close()
    if db then db:close(); db = nil end
end

local cmd = arg and arg[1]
if cmd then
    local id = arg[2]
    if cmd == "enter" then
        local plugin = arg[3]
        local opts = { init = {}, context = {} }
        local i = 4
        while i <= #arg do
            local a = arg[i]
            if a == "--ttl" then opts.ttl = tonumber(arg[i + 1]); i = i + 2
            elseif a == "--source" then opts.source = arg[i + 1]; i = i + 2
            elseif a == "--init" then
                local k, v = (arg[i + 1] or ""):match("^([^=]+)=(.*)$")
                if k then opts.init[k] = v end
                i = i + 2
            elseif a == "--context" then
                local k, v = (arg[i + 1] or ""):match("^([^=]+)=(.*)$")
                if k then opts.context[k] = v end
                i = i + 2
            else i = i + 1 end
        end
        local o, err = S.enter(id, plugin, opts)
        if not o then io.stderr:write(tostring(err) .. "\n"); os.exit(2) end
        io.write(encode(o) .. "\n")
    elseif cmd == "get" then
        local o = S.get(id)
        if not o then os.exit(1) end
        io.write(encode(o) .. "\n")
    elseif cmd == "touch" then
        local o = S.touch(id, tonumber(arg[3] or DEFAULT_TTL))
        if not o then os.exit(1) end
        io.write(encode(o) .. "\n")
    elseif cmd == "exit" then
        S.exit(id)
    elseif cmd == "route" then
        local text = arg[3] or ""
        -- 简化：只演示当前 session 的插件
        local cur = S.get(id)
        if not cur then os.exit(1) end
        io.write(cur.plugin .. "\n")
    else
        io.stderr:write("用法: session.sh enter|get|touch|exit|route ...\n"); os.exit(2)
    end
    S.close()
end

return S
