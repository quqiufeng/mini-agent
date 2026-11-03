-- lib/ffi/kv.lua — kvcache FFI（/opt/my_db_src/include/cache.h）
local ffi = require("ffi")
local src = debug.getinfo(1, "S").source:gsub("^@", "")
local here = src:match("^(.*)/") or "."
local ROOT = here:match("^(.*)/lib/ffi$") or (here .. "/../..")

ffi.cdef[[
typedef struct cache cache_t;
cache_t* cache_open(const char* db_dir, size_t max_memory);
void cache_close(cache_t* cache);
int cache_sync(cache_t* cache);
int cache_set(cache_t* cache, const char* key, const char* value, uint64_t ttl_ms);
const char* cache_get(cache_t* cache, const char* key);
int cache_del(cache_t* cache, const char* key);
int cache_exists(cache_t* cache, const char* key);
int cache_expire(cache_t* cache, const char* key);
int cache_touch(cache_t* cache, const char* key);
size_t cache_count(cache_t* cache);
size_t cache_memory_used(cache_t* cache);
int cache_check(const char* db_dir);
]]

local lib
local cands = {
    "/home/quqiufeng/my-agent/lib/native/libmydb.so",
    ROOT .. "/lib/native/libmydb.so",
    "libmydb.so",
}
local _env = os.getenv("LIBMYDB")
if _env and _env ~= "" then table.insert(cands, 1, _env) end
for _, p in ipairs(cands) do
    if p and p ~= "" then
        local ok, h = pcall(ffi.load, p)
        if ok then lib = h; break end
    end
end
assert(lib, "无法加载 libmydb.so（先 make libmydb.so 并放到 lib/native/）")

local KV = {}
KV.__index = KV

function KV.open(dir, max_memory)
    max_memory = max_memory or 64 * 1024 * 1024
    local h = lib.cache_open(dir, max_memory)
    if h == nil then return nil, "cache_open failed" end
    return setmetatable({ h = h }, KV)
end

function KV:set(key, value, ttl_ms)
    return lib.cache_set(self.h, key, tostring(value), ttl_ms or 0) == 0
end
function KV:get(key)
    local p = lib.cache_get(self.h, key)
    if p == nil then return nil end
    return ffi.string(p)
end
function KV:del(key) return lib.cache_del(self.h, key) == 0 end
function KV:exists(key) return lib.cache_exists(self.h, key) ~= 0 end
function KV:touch(key) return lib.cache_touch(self.h, key) == 0 end
function KV:expire(key) return lib.cache_expire(self.h, key) == 0 end
function KV:sync() return lib.cache_sync(self.h) == 0 end
function KV:count() return tonumber(lib.cache_count(self.h)) end
function KV:close() if self.h ~= nil then lib.cache_close(self.h); self.h = nil end end
function KV.check(dir) return lib.cache_check(dir) == 0 end
return KV
