-- lib/state_core.lua — 状态读写模块（kvcache 单一来源 + 文件镜像兼容）
local here = (debug.getinfo(1, "S").source:gsub("^@", "")):match("^(.*)/") or "."
package.path = here .. "/?.lua;" .. here .. "/ffi/?.lua;" .. package.path
local core = require("core")
local KV = require("kv")

local HOME = os.getenv("HOME") or "/tmp"
local DIR = os.getenv("MYAGENT_STATE_DIR") or (HOME .. "/.myagent/state")
local KV_DIR = os.getenv("MYAGENT_KV_DIR")
if not KV_DIR or KV_DIR == "" then
    if DIR == HOME .. "/.myagent/state" then KV_DIR = HOME .. "/.myagent/kv"
    else KV_DIR = DIR .. ".kv" end
end
local PREFIX = "state."
local LEGACY = "/tmp/myagent_state"
local S = {}
local db
local migrated = false

local function open()
    if db then return db end
    core.mkdirp(KV_DIR)
    db = KV.open(KV_DIR, 64 * 1024 * 1024)
    return db
end

local function ensure()
    core.mkdirp(DIR)
end

local function parse(line)
    if not line then return nil end
    line = line:gsub("\n$", "")
    local fields = {}
    for f in line:gmatch("%S+") do fields[#fields + 1] = f end
    if #fields < 2 then return nil end
    local seq = nil
    if #fields >= 3 and fields[#fields]:sub(1, 1) == "@" then
        seq = tonumber(fields[#fields]:sub(2))
        fields[#fields] = nil
    end
    return {
        state = fields[1],
        ts = tonumber(fields[2]) or 0,
        pid = tonumber(fields[3]) or nil,
        seq = seq,
        fields = fields,
        raw = line,
    }
end

local function mirror_path(key) return DIR .. "/" .. key end

local function read_file(key)
    local s = core.read(mirror_path(key))
    if s then return s end
    return core.read(LEGACY .. "/" .. key)
end

local function migrate_key(key)
    local d = open()
    if not d then return nil end
    local raw = d:get(PREFIX .. key)
    if raw then return raw end
    local file = read_file(key)
    if file then d:set(PREFIX .. key, file, 0) end
    return file
end

local function migrate_all()
    if migrated then return end
    migrated = true
    local d = open()
    if not d then return end
    local seen = {}
    for _, base in ipairs({ DIR, LEGACY }) do
        for _, name in ipairs(core.list_dir(base)) do
            if not seen[name] and not name:match("^%.") and not name:match("%.tmp%.") then
                seen[name] = true
                local raw = d:get(PREFIX .. name)
                if not raw then
                    local file = core.read(base .. "/" .. name)
                    if file then d:set(PREFIX .. name, file, 0) end
                end
            end
        end
    end
    d:sync()
end

function S.dir() return DIR end
function S.kv_dir() return KV_DIR end

function S.read(key)
    local d = open()
    local raw = d and d:get(PREFIX .. key)
    if not raw then raw = migrate_key(key) end
    return parse(raw)
end

function S.write(key, value, extra)
    ensure()
    local line = tostring(value) .. " " .. tostring(os.time())
    if extra then
        for _, v in ipairs(extra) do line = line .. " " .. tostring(v) end
    end
    line = line .. " @" .. tostring(core.now_ms())
    local ok, err = core.write_atomic(mirror_path(key), line .. "\n")
    if not ok then error(err) end
    local d = open()
    if d then
        if not d:set(PREFIX .. key, line, 0) then
            io.stderr:write("[state] kv set failed: " .. key .. "\n")
        else
            d:sync()
        end
    end
    core.log("state." .. key, value)
end

function S.del(key)
    local d = open()
    if d then d:del(PREFIX .. key); d:sync() end
    os.remove(mirror_path(key))
end

function S.list()
    migrate_all()
    ensure()
    local set = {}
    local d = open()
    if d then
        for _, k in ipairs(d:keys(PREFIX)) do
            set[k:sub(#PREFIX + 1)] = true
        end
    end
    for _, name in ipairs(core.list_dir(DIR)) do
        if not name:match("^%.") and not name:match("%.tmp%.") then set[name] = true end
    end
    local out = {}
    for k in pairs(set) do out[#out + 1] = k end
    table.sort(out)
    return out
end

function S.snapshot(prefix)
    migrate_all()
    ensure()
    local out = {}
    local d = open()
    if d then
        for _, k in ipairs(d:keys(PREFIX .. (prefix or ""))) do
            local name = k:sub(#PREFIX + 1)
            out[name] = d:get(k)
        end
    end
    return out
end

local function pid_ok(key, pid)
    if not pid then return false end
    if key == "media.vlc" then return core.pid_matches(pid, "vlc") end
    if key == "media.phone" or key == "display.wechat" then return core.pid_matches(pid, "scrcpy") end
    return core.pid_alive(pid)
end

function S.active_media()
    local play, play_ts, pause, pause_ts
    for _, key in ipairs({ "media.phone", "media.vlc" }) do
        local v = S.read(key)
        if v and (v.state == "playing" or v.state == "paused") and pid_ok(key, v.pid) then
            local ord = v.seq or v.ts
            if v.state == "playing" then
                if not play_ts or ord > play_ts then play, play_ts = key, ord end
            else
                if not pause_ts or ord > pause_ts then pause, pause_ts = key, ord end
            end
        end
    end
    return play or pause
end

function S.any_playing()
    local out = {}
    for _, key in ipairs({ "media.phone", "media.vlc" }) do
        local v = S.read(key)
        if v and v.state == "playing" and pid_ok(key, v.pid) then out[#out + 1] = key end
    end
    return out
end

function S.tidy()
    for _, key in ipairs({ "media.vlc", "media.phone", "display.wechat" }) do
        local v = S.read(key)
        if v then
            local live = pid_ok(key, v.pid)
            if not live and (v.state == "playing" or v.state == "paused" or v.state == "on") then
                S.write(key, key == "display.wechat" and "off" or "stopped", { v.pid or 0 })
            end
        end
    end
end

function S.close()
    if db then db:close(); db = nil end
end

return S
