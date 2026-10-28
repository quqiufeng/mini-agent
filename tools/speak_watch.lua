#!/usr/bin/env luajit
-- @desc 监听本地大脑会话，把新完成的助手回复用本地 TTS 念出来（语音/文字输入都覆盖）
-- @usage tools/speak_watch.sh   （start.sh/launch.sh 自动后台启动；单实例由 flock 保证）
local DIR = (arg[0] or ""):match("^(.*)/") or "."
package.path = DIR .. "/?.lua;" .. package.path
local ffi = require("ffi")
local http = require("http")
local J = require("jsonc")

ffi.cdef[[
int open(const char *pathname, int flags, ...);
int flock(int fd, int operation);
int close(int fd);
int usleep(unsigned int usec);
struct timespec { long tv_sec; long tv_nsec; };
int clock_gettime(int clk_id, struct timespec *tp);
]]

local PORT = os.getenv("AGENT_PORT") or "4097"
local BASE = "http://127.0.0.1:" .. PORT
local MAXLEN = tonumber(os.getenv("SPEAK_MAX") or "240")
local SENT_MAX = tonumber(os.getenv("SPEAK_SENTENCE_MAX") or "90")
local STABLE_MS = tonumber(os.getenv("SPEAK_STABLE") or "1.5") * 1000
local LOCK = "/tmp/myagent-speak-watch.lock"
local WANT = "/tmp/myagent_speak_want"
local WANT_SEC = tonumber(os.getenv("SPEAK_WANT_SEC") or "180")
local TTS = DIR .. "/tts.sh"

local function now_ms()
    local ts = ffi.new("struct timespec")
    ffi.C.clock_gettime(0, ts)
    return tonumber(ts.tv_sec) * 1000 + math.floor(tonumber(ts.tv_nsec) / 1e6)
end

local function shquote(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function trunc_utf8(s, n)
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
    return s:sub(1, math.max(1, i)) .. "……"
end

local function norm(s)
    s = (s or ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    return s
end

local function clean(s)
    s = s:gsub("```.-```", "")
    s = s:gsub("`[^`]*`", "")
    s = s:gsub("%[([^%]]+)%]%([^%)]+%)", "%1")
    s = s:gsub("https?://%S+", "")
    s = s:gsub("[*_#>|]+", "")
    s = norm(s)
    s = s:gsub("^[Aa]ssistant[:：]%s*", ""):gsub("^回复[:：]%s*", "")
    return s
end

local function speakable(text)
    text = norm(text)
    if text == "" then return "" end
    local cut = text:match("^([^。！？!?\n]*)") or text
    cut = cut:gsub("[：:]%s*[-*・•].*$", "")
    cut = norm(cut)
    if cut == "" then return "" end
    if #cut > SENT_MAX then
        cut = trunc_utf8(cut:gsub("[，、,;；:：%-— ]+$", ""), SENT_MAX)
    end
    return cut
end

local function speak(text)
    text = speakable(text)
    if text == "" then return end
    if #text > MAXLEN then text = trunc_utf8(text, MAXLEN) end
    print("[speak-watch] " .. text); io.stdout:flush()
    local rc = os.execute(TTS .. " " .. shquote(text))
    if rc ~= 0 and rc ~= true then
        print("[speak-watch] tts rc=" .. tostring(rc)); io.stdout:flush()
    end
end

local function want_fresh()
    local f = io.open(WANT, "r")
    if not f then return false end
    local s = f:read("*l"); f:close()
    local t = tonumber(s or "")
    if not t then return false end
    return (os.time() - t) <= WANT_SEC
end

local function drop_want()
    os.remove(WANT)
end

local fd = ffi.C.open(LOCK, 2 + 64, 384) -- O_RDWR|O_CREAT, 0600
if fd < 0 then
    io.stderr:write("[speak-watch] cannot open lock\n"); os.exit(1)
end
if ffi.C.flock(fd, 6) ~= 0 then
    print("[speak-watch] already running"); os.exit(0)
end

local function get(path)
    local body, status, err = http.request({ url = BASE .. path, timeout = 5, connect_timeout = 3 })
    if not body or status ~= 200 then return nil end
    return J.parse(body)
end

local function read_want()
    local f = io.open(WANT, "r")
    if not f then return nil end
    local s = f:read("*a"); f:close()
    local first, rest = s:match("^(%d+)\n(.*)$")
    if not first then first = s:match("^(%d+)%s*$"); rest = "" end
    local t = tonumber(first)
    if not t then return nil end
    if os.time() - t > WANT_SEC then return nil end
    return t * 1000, norm(rest or "")
end

local function msg_text(msgs, idx)
    local pn = J.len(msgs, idx .. ".parts")
    local out = {}
    for pi = 0, pn - 1 do
        if J.str(msgs, idx .. ".parts." .. pi .. ".type") == "text" then
            local tx = J.str(msgs, idx .. ".parts." .. pi .. ".text")
            if tx and tx ~= "" then out[#out + 1] = tx end
        end
    end
    return table.concat(out, " ")
end

local function msg_role(msgs, idx)
    return J.str(msgs, idx .. ".info.role") or J.str(msgs, idx .. ".role")
end
local function msg_id(msgs, idx)
    return J.str(msgs, idx .. ".info.id") or J.str(msgs, idx .. ".id")
end
local function msg_done(msgs, idx)
    return J.int(msgs, idx .. ".info.time.completed") or J.int(msgs, idx .. ".time.completed") or 0
end
local function msg_created(msgs, idx)
    return J.int(msgs, idx .. ".info.time.created") or J.int(msgs, idx .. ".time.created") or 0
end

local function find_target(want_text, start_ms)
    local sessions = get("/session")
    if not sessions then return nil end
    local list = {}
    for i = 0, J.len(sessions) - 1 do
        list[#list + 1] = { id = J.str(sessions, i .. ".id"),
                            u = J.int(sessions, i .. ".time.updated") or 0 }
    end
    J.free(sessions)
    table.sort(list, function(a, b) return a.u > b.u end)
    for n = 1, math.min(#list, 12) do
        local sid = list[n].id
        local msgs = get("/session/" .. sid .. "/message?limit=50")
        if msgs then
            for i = J.len(msgs) - 1, 0, -1 do
                if msg_role(msgs, i) == "user" and msg_created(msgs, i) >= start_ms - 10000 then
                    local utext = norm(clean(msg_text(msgs, i)))
                    if utext ~= "" and (utext == want_text or utext:find(want_text, 1, true) or
                                        want_text:find(utext, 1, true)) then
                        J.free(msgs)
                        return sid, i
                    end
                end
            end
            J.free(msgs)
        end
    end
    return nil
end

local pending_key, pending_text, pending_since, spoken_key = nil, "", 0, nil
local target_sid, target_user = nil, nil
local last_want_ms, last_want_text = 0, ""

while true do
    local want_ms, want_text = read_want()
    if want_ms and want_text ~= "" then
        if want_ms ~= last_want_ms or want_text ~= last_want_text then
            target_sid, target_user = nil, nil
            pending_key, pending_text = nil, ""
            last_want_ms, last_want_text = want_ms, want_text
        end
        if not target_sid then
            target_sid, target_user = find_target(want_text, want_ms)
        end
        if target_sid then
            local msgs = get("/session/" .. target_sid .. "/message?limit=50")
            if msgs then
                local reply_text, reply_key, reply_done = "", nil, 0
                for i = (target_user or 0) + 1, J.len(msgs) - 1 do
                    if msg_role(msgs, i) == "assistant" then
                        local t = norm(clean(msg_text(msgs, i)))
                        if t ~= "" then
                            reply_text, reply_key, reply_done = t, msg_id(msgs, i), msg_done(msgs, i)
                        end
                    end
                end
                J.free(msgs)
                if reply_key and reply_text ~= "" and reply_done and reply_done >= want_ms and reply_key ~= spoken_key then
                    local now = now_ms()
                    if reply_key ~= pending_key or reply_text ~= pending_text then
                        pending_key, pending_text, pending_since = reply_key, reply_text, now
                    elseif now - pending_since >= STABLE_MS then
                        speak(reply_text)
                        spoken_key = reply_key
                        pending_key, pending_text = nil, ""
                        target_sid, target_user = nil, nil
                        last_want_ms, last_want_text = 0, ""
                        drop_want()
                    end
                else
                    pending_key = nil
                end
            end
        end
    else
        pending_key, pending_text = nil, ""
    end
    ffi.C.usleep(800000)
end
