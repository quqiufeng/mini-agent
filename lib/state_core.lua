-- lib/state_core.lua — 状态读写模块（单一来源）
local here = (arg and arg[0] or ""):match("^(.*)/") or "."
package.path = here .. "/?.lua;" .. package.path
local core = require("core")

local HOME = os.getenv("HOME") or "/tmp"
local DIR = os.getenv("MYAGENT_STATE_DIR") or (HOME .. "/.myagent/state")
local LEGACY = "/tmp/myagent_state"
local S = {}

local function ensure()
    core.mkdirp(DIR)
end

local function migrate()
    if not core.exists(LEGACY) then return end
    local names = core.list_dir(LEGACY)
    if #names == 0 then return end
    ensure()
    for _, name in ipairs(names) do
        if not name:match("^%.") then
            local dst = DIR .. "/" .. name
            if not core.exists(dst) then
                local data = core.read(LEGACY .. "/" .. name)
                if data then core.write_atomic(dst, data) end
            end
        end
    end
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

function S.dir()
    return DIR
end

function S.read(key)
    return parse(core.read(DIR .. "/" .. key))
end

function S.write(key, value, extra)
    ensure()
    local line = tostring(value) .. " " .. tostring(os.time())
    if extra then
        for _, v in ipairs(extra) do line = line .. " " .. tostring(v) end
    end
    line = line .. " @" .. tostring(core.now_ms())
    local ok, err = core.write_atomic(DIR .. "/" .. key, line .. "\n")
    if not ok then error(err) end
    core.log("state." .. key, value)
end

function S.del(key)
    os.remove(DIR .. "/" .. key)
end

function S.list()
    ensure()
    local names = core.list_dir(DIR)
    table.sort(names)
    return names
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


return S
