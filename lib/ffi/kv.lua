-- lib/ffi/kv.lua — kvcache FFI（/opt/my_db_src/include/cache.h）
local ffi = require("ffi")
ffi.cdef[[
int dup(int fd);
int dup2(int oldfd, int newfd);
int open(const char *path, int flags, ...);
int close(int fd);
int flock(int fd, int operation);
int fflush(void *stream);
]]
local src = debug.getinfo(1, "S").source:gsub("^@", "")
local here = src:match("^(.*)/") or "."
local ROOT = here:match("^(.*)/lib/ffi$") or (here .. "/../..")

ffi.cdef[[
typedef struct cache cache_t;
typedef struct cache_iter cache_iter_t;
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
size_t cache_compact(cache_t* cache);
cache_iter_t* cache_iter_create(cache_t* cache);
int cache_iter_next(cache_iter_t* iter, const char** key_out, const char** value_out);
void cache_iter_destroy(cache_iter_t* iter);
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
local opened = {}

local function with_lock(path, fn, ...)
    local fd = ffi.C.open(path, 0x42, 0x1A4) -- O_CREAT|O_RDWR
    if fd < 0 then return fn(...) end
    ffi.C.flock(fd, 2) -- LOCK_EX
    local ok, a, b = pcall(fn, ...)
    ffi.C.flock(fd, 8); ffi.C.close(fd) -- LOCK_UN
    if not ok then error(a, 0) end
    return a, b
end

local function quiet(fn, ...)
    local saved = ffi.C.dup(2)
    local nullfd = ffi.C.open("/dev/null", 1, 0)
    if saved < 0 or nullfd < 0 then return fn(...) end
    ffi.C.dup2(nullfd, 2)
    local ok, a, b = pcall(fn, ...)
    ffi.C.fflush(nil)
    ffi.C.dup2(saved, 2)
    ffi.C.close(saved)
    ffi.C.close(nullfd)
    if not ok then error(a, 0) end
    return a, b
end

function KV.open(dir, max_memory)
    dir = dir or ""
    if opened[dir] then return opened[dir] end
    max_memory = max_memory or 64 * 1024 * 1024
    local lock = dir .. "/.kv.lock"
    local h = with_lock(lock, quiet, lib.cache_open, dir, max_memory)
    if h == nil then return nil, "cache_open failed" end
    local obj = setmetatable({ h = h, lock = lock }, KV)
    opened[dir] = obj
    return obj
end

function KV:set(key, value, ttl_ms)
    return with_lock(self.lock, quiet, lib.cache_set, self.h, key, tostring(value), ttl_ms or 0) == 0
end
function KV:get(key)
    if lib.cache_exists(self.h, key) == 0 then return nil end
    local p = lib.cache_get(self.h, key)
    if p == nil then return nil end
    return ffi.string(p)
end
function KV:del(key) return with_lock(self.lock, quiet, lib.cache_del, self.h, key) == 0 end
function KV:exists(key) return lib.cache_exists(self.h, key) ~= 0 end
function KV:items(prefix)
    local out = {}
    local it = lib.cache_iter_create(self.h)
    if it == nil then return out end
    local kp, vp = ffi.new("const char*[1]"), ffi.new("const char*[1]")
    while lib.cache_iter_next(it, kp, vp) ~= 0 do
        local k = kp[0] ~= nil and ffi.string(kp[0]) or nil
        local v = vp[0] ~= nil and ffi.string(vp[0]) or nil
        if k and (not prefix or k:sub(1, #prefix) == prefix) then out[#out + 1] = { k, v } end
    end
    lib.cache_iter_destroy(it)
    return out
end

function KV:keys(prefix)
    local out = {}
    local it = lib.cache_iter_create(self.h)
    if it == nil then return out end
    local kp, vp = ffi.new("const char*[1]"), ffi.new("const char*[1]")
    while lib.cache_iter_next(it, kp, vp) ~= 0 do
        local k = kp[0] ~= nil and ffi.string(kp[0]) or nil
        if k and (not prefix or k:sub(1, #prefix) == prefix) then out[#out + 1] = k end
    end
    lib.cache_iter_destroy(it)
    table.sort(out)
    return out
end
function KV:touch(key) return lib.cache_touch(self.h, key) == 0 end
function KV:expire(key) return lib.cache_expire(self.h, key) == 0 end
function KV:sync() return with_lock(self.lock, quiet, lib.cache_sync, self.h) == 0 end
function KV:compact()
    return with_lock(self.lock, quiet, lib.cache_compact, self.h)
end
function KV:count() return tonumber(lib.cache_count(self.h)) end
function KV:close()
    -- 进程内单例：由 state/device/event 共享，不能提前关掉其他模块的句柄
    if self.h ~= nil then with_lock(self.lock, quiet, lib.cache_sync, self.h) end
end
function KV.check(dir) return lib.cache_check(dir) == 0 end
return KV
