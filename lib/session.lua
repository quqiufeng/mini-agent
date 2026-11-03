-- lib/session.lua — 会话模式（kvcache 单一源；插件 context/defaults 落 KV）
local here = (debug.getinfo(1, "S").source:gsub("^@", "")):match("^(.*)/") or "."
package.path = here .. "/?.lua;" .. here .. "/ffi/?.lua;" .. package.path
local core = require("core")
local JSON = require("json")
local KV = require("kv")
local manifests = require("plugin_manifest")

local HOME = os.getenv("HOME") or "/tmp"
local DB_DIR = os.getenv("MYAGENT_KV_DIR")
if not DB_DIR or DB_DIR == "" then
    local sd = os.getenv("MYAGENT_STATE_DIR")
    DB_DIR = (sd and sd ~= "") and (sd .. ".kv") or (HOME .. "/.myagent/kv")
end
local DEFAULT_TTL = tonumber(os.getenv("SESSION_TTL") or "1800")
local S = {}
local db, mem, mem_at = nil, {}, {}

local function open()
    if not db then
        core.mkdirp(DB_DIR)
        db = KV.open(DB_DIR, 64 * 1024 * 1024)
        assert(db, "session: cache_open failed: " .. DB_DIR)
    end
    return db
end

local function key(id) return "session." .. tostring(id) .. ".context" end
local function now() return os.time() end

function S.valid_id(id)
    return type(id) == "string" and #id > 0 and #id <= 128 and id:match("^[A-Za-z0-9_:.%%/%-]+$") ~= nil
end

local function deep_merge(dst, src)
    for k, v in pairs(src or {}) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            deep_merge(dst[k], v)
        else
            dst[k] = v
        end
    end
    return dst
end

local function decode(raw)
    if not raw or raw == "" then return nil end
    local v = JSON.decode(raw)
    if type(v) == "table" then return v end
    -- 兼容旧的 key=value 文本
    local o = { init = {}, context = {} }
    for line in raw:gmatch("[^\n]+") do
        local k, x = line:match("^([^=]+)=(.*)$")
        if k then
            if k:sub(1, 5) == "init." then o.init[k:sub(6)] = x
            elseif k:sub(1, 8) == "context." then o.context[k:sub(9)] = x
            elseif k == "since" then o.since = tonumber(x)
            elseif k == "until" then o.until_ts = tonumber(x)
            else o[k] = x end
        end
    end
    return o
end

local function text(o)
    local t = { "plugin=" .. tostring(o.plugin or ""), "source=" .. tostring(o.source or ""),
                "since=" .. tostring(o.since or now()), "until=" .. tostring(o.until_ts or (now() + DEFAULT_TTL)) }
    for k, v in pairs(o.init or {}) do t[#t + 1] = "init." .. k .. "=" .. tostring(v) end
    for k, v in pairs(o.context or {}) do
        if type(v) == "table" then v = JSON.encode(v) end
        t[#t + 1] = "context." .. k .. "=" .. tostring(v)
    end
    return table.concat(t, "\n")
end

local function save(id, rec)
    local ttl = math.max(1, (rec.until_ts or now()) - now())
    local raw = JSON.encode(rec)
    local ok = open():set(key(id), raw, ttl * 1000)
    if ok then open():sync() end
    mem[id], mem_at[id] = rec, now()
    return ok
end

function S.bootstrap()
    local n = 0
    for _, k in ipairs(open():keys("session.")) do
        local id = k:match("^session%.(.+)%.context$")
        if id then
            local rec = decode(open():get(k))
            if type(rec) == "table" then mem[id], mem_at[id] = rec, now(); n = n + 1 end
        end
    end
    return n
end

function S.enter(id, plugin, opts)
    opts = opts or {}
    if not S.valid_id(id) then return nil, "bad session id" end
    if not plugin or plugin == "" then return nil, "plugin required" end
    local spec = manifests.find(plugin) or {}
    local init = {}
    deep_merge(init, spec.session_defaults)
    deep_merge(init, opts.init)
    local ctx = {}
    deep_merge(ctx, spec.context)
    deep_merge(ctx, opts.context)
    local h = nil
    if spec.session_handler then
        local ok, mod = pcall(require, spec.session_handler)
        if ok and type(mod) == "table" then h = mod end
    end
    if h and type(h.on_enter) == "function" then
        local extra = h.on_enter({ session_id = id, init = init, source = opts.source })
        if type(extra) == "table" then deep_merge(init, extra) end
    end
    local ttl = tonumber(opts.ttl or DEFAULT_TTL)
    local rec = { plugin = plugin, source = opts.source or "", since = now(),
                  until_ts = now() + ttl, init = init, context = ctx }
    if not save(id, rec) then return nil, "kv set failed" end
    return rec
end

function S.get(id)
    if not S.valid_id(id) then return nil end
    local rec = mem[id]
    if not rec or (now() - (mem_at[id] or 0)) > 1 then
        rec = decode(open():get(key(id)))
        if type(rec) ~= "table" then mem[id] = nil; mem_at[id] = nil; return nil end
        mem[id], mem_at[id] = rec, now()
    end
    if rec.until_ts and rec.until_ts <= now() then
        mem[id], mem_at[id] = nil, nil
        open():del(key(id)); open():sync()
        return nil
    end
    return rec
end

function S.touch(id, ttl)
    local rec = S.get(id)
    if not rec then return nil end
    rec.until_ts = now() + tonumber(ttl or DEFAULT_TTL)
    if not save(id, rec) then return nil end
    return rec
end

function S.exit(id)
    if not S.valid_id(id) then return false end
    local rec = S.get(id)
    if rec then
        local spec = manifests.find(rec.plugin) or {}
        local ok, h = pcall(require, spec.session_handler or "")
        if ok and type(h) == "table" and type(h.on_exit) == "function" then
            pcall(h.on_exit, rec.init or {}, id)
        end
    end
    mem[id], mem_at[id] = nil, nil
    local ok = open():del(key(id))
    if ok then open():sync() end
    return ok, rec
end

function S.current(id) return S.get(id) end
function S.plugin(id) local r = S.get(id); return r and r.plugin end
function S.active(id, plugin)
    local p = S.plugin(id)
    return p ~= nil and (plugin == nil or p == plugin)
end

function S.route(text, mats, current_id)
    local plugin, args = text:match("^#([%w_%-]+)@?(.*)$")
    if plugin then return { plugin = plugin, args = args, explicit = true } end
    local cur = current_id and S.get(current_id) or nil
    if cur then
        local m = (mats and mats[cur.plugin]) or manifests.find(cur.plugin)
        for cmd, action in pairs(m and m.session_commands or {}) do
            if text:sub(1, #cmd) == cmd then
                return { plugin = cur.plugin, action = action, text = text, session = cur }
            end
        end
    end
    local list = mats and next(mats) and mats or nil
    local iter = list and pairs(mats) or nil
    if not list then
        for _, m in ipairs(manifests.scan()) do
            for _, intent in ipairs(m.intents or {}) do
                if text:find(intent, 1, true) then
                    return { plugin = m.name, intent = intent, text = text }
                end
            end
        end
    else
        for name, m in iter do
            for _, intent in ipairs(m.intents or {}) do
                if text:find(intent, 1, true) then
                    return { plugin = name, intent = intent, text = text }
                end
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
        io.write(text(o) .. "\n")
    elseif cmd == "get" then
        local o = S.get(id)
        if not o then os.exit(1) end
        io.write(text(o) .. "\n")
    elseif cmd == "touch" then
        local o = S.touch(id, tonumber(arg[3] or DEFAULT_TTL))
        if not o then os.exit(1) end
        io.write(text(o) .. "\n")
    elseif cmd == "exit" then
        S.exit(id)
    elseif cmd == "route" then
        local text_in = arg[3] or ""
        local r = S.route(text_in, nil, id)
        if not r then os.exit(1) end
        io.write(r.plugin .. "\n")
    else
        io.stderr:write("用法: session.sh enter|get|touch|exit|route ...\n"); os.exit(2)
    end
    S.close()
end

return S
