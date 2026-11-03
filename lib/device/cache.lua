-- lib/device/cache.lua — 设备注册表/租约 KV 缓存（统一状态源）
local here = (debug.getinfo(1, "S").source:gsub("^@", "")):match("^(.*)/") or "."
package.path = here .. "/../?.lua;" .. here .. "/../ffi/?.lua;" .. package.path
local core = require("core")
local JSON = require("json")
local KV = require("kv")

local HOME = os.getenv("HOME") or "/tmp"
local DIR = os.getenv("MYAGENT_KV_DIR")
if not DIR or DIR == "" then
    local sd = os.getenv("MYAGENT_STATE_DIR")
    DIR = (sd and sd ~= "") and (sd .. ".kv") or (HOME .. "/.myagent/kv")
end
local M = {}
local db

local function open()
    if db then return db end
    core.mkdirp(DIR)
    db = KV.open(DIR, 64 * 1024 * 1024)
    return db
end

function M.dir() return DIR end

function M.put(key, value, ttl_ms)
    local d = open()
    if not d then return false end
    local raw = type(value) == "string" and value or JSON.encode(value)
    local ok = d:set("device." .. key, raw, ttl_ms or 0)
    if ok then d:sync() end
    return ok
end

function M.get_json(key)
    local d = open()
    if not d then return nil end
    local raw = d:get("device." .. key)
    if not raw then return nil end
    return JSON.decode(raw)
end

function M.get(key)
    local d = open()
    return d and d:get("device." .. key) or nil
end

function M.del(key)
    local d = open()
    if not d then return false end
    local ok = d:del("device." .. key)
    if ok then d:sync() end
    return ok
end

function M.save_registry(reg)
    return M.put("registry", reg)
end

function M.registry()
    return M.get_json("registry")
end

function M.put_topology(topo)
    return M.put("topology", topo)
end

function M.topology()
    return M.get_json("topology")
end

function M.close()
    if db then db:close(); db = nil end
end

return M
