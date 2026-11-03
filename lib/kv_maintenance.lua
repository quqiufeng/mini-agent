-- lib/kv_maintenance.lua — kvcache 维护：check/compact/rebuild
local here = (arg and arg[0] or ""):match("^(.*)/") or "."
package.path = here .. "/?.lua;" .. here .. "/ffi/?.lua;" .. package.path
local core = require("core")
local KV = require("kv")
local J = require("json")
local HOME = os.getenv("HOME") or "/tmp"
local DIR = os.getenv("MYAGENT_KV_DIR")
if not DIR or DIR == "" then
    local sd = os.getenv("MYAGENT_STATE_DIR")
    DIR = (sd and sd ~= "") and (sd .. ".kv") or (HOME .. "/.myagent/kv")
end
local cmd = arg and arg[1] or "check"
core.mkdirp(DIR)

local function copy_ttl(k, v)
    if k:match("^event%.") and k ~= "event.seq" then return 3600 end
    if k:match("^session%.") then
        local rec = J.decode(v)
        if type(rec) == "table" and rec.until_ts then return math.max(1, rec.until_ts - os.time()) end
    end
    return 0
end

if cmd == "check" then
    local db = assert(KV.open(DIR))
    io.write("check=", tostring(KV.check(DIR)), " path=", DIR, " count=", tostring(db:count()), "\n")
    db:close()
elseif cmd == "compact" then
    local db = assert(KV.open(DIR))
    local before = db:count()
    local freed = db:compact()
    db:sync()
    io.write(string.format("compacted path=%s before=%d freed=%d after=%d\n", DIR, before, tonumber(freed) or 0, db:count()))
    db:close()
elseif cmd == "rebuild" then
    local old = assert(KV.open(DIR))
    local tmp = DIR .. ".new." .. tostring(core.getpid())
    local new = assert(KV.open(tmp))
    local n = 0
    for _, it in ipairs(old:items()) do
        local k, v = it[1], it[2]
        if k and v and new:set(k, v, copy_ttl(k, v) * 1000) then n = n + 1 end
    end
    new:sync(); old:sync()
    local backup = DIR .. ".bak." .. tostring(os.time())
    assert(os.rename(DIR, backup), "rename old failed")
    assert(os.rename(tmp, DIR), "rename new failed")
    io.write(string.format("rebuilt path=%s items=%d backup=%s\n", DIR, n, backup))
else
    io.stderr:write("用法: kv_maintenance.lua check|compact|rebuild\n"); os.exit(2)
end
