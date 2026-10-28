local ffi = require("ffi")

ffi.cdef[[
typedef void CURL;
struct curl_slist;
CURL *curl_easy_init(void);
int curl_easy_setopt(CURL *curl, int option, ...);
int curl_easy_perform(CURL *curl);
void curl_easy_cleanup(CURL *curl);
const char *curl_easy_strerror(int code);
int curl_easy_getinfo(CURL *curl, int info, ...);
struct curl_slist *curl_slist_append(struct curl_slist *list, const char *s);
void curl_slist_free_all(struct curl_slist *list);
]]

local lib
for _, name in ipairs({ "curl", "libcurl.so.4" }) do
    local ok, h = pcall(ffi.load, name)
    if ok then lib = h; break end
end
assert(lib, "无法加载 libcurl")

local M = {}
local chunks = nil
local writer = ffi.cast("unsigned long (*)(char *, unsigned long, unsigned long, void *)",
    function(ptr, size, nmemb, ud)
        local n = tonumber(size) * tonumber(nmemb)
        if chunks then chunks[#chunks + 1] = ffi.string(ptr, n) end
        return n
    end)

local CURLOPT_URL = 10002
local CURLOPT_WRITEFUNCTION = 20011
local CURLOPT_POST = 47
local CURLOPT_POSTFIELDS = 10015
local CURLOPT_POSTFIELDSIZE = 60
local CURLOPT_HTTPHEADER = 10023
local CURLOPT_TIMEOUT = 13
local CURLOPT_CONNECTTIMEOUT = 78
local CURLOPT_FOLLOWLOCATION = 52
local CURLOPT_USERAGENT = 10018
local CURLOPT_SSL_VERIFYPEER = 64
local CURLOPT_SSL_VERIFYHOST = 81
local CURLOPT_NOSIGNAL = 99
local CURLOPT_ACCEPT_ENCODING = 10102
local CURLOPT_CUSTOMREQUEST = 10036
local CURLOPT_USERPWD = 10005
local CURLOPT_HTTPAUTH = 107
local CURLINFO_RESPONSE_CODE = 0x200002

-- opts: url, method("GET"/"POST"), headers{table}, body, timeout, connect_timeout,
--       follow(bool), user_agent
-- 返回: body, status, err
function M.request(opts)
    local url = opts.url
    if not url or url == "" then return nil, 0, "missing url" end
    local h = lib.curl_easy_init()
    if h == nil then return nil, 0, "curl_easy_init failed" end

    chunks = {}

    local slist = nil
    if opts.headers then
        for _, hdr in ipairs(opts.headers) do
            slist = lib.curl_slist_append(slist, ffi.cast("const char *", hdr))
        end
    end

    lib.curl_easy_setopt(h, CURLOPT_URL, ffi.cast("const char *", url))
    lib.curl_easy_setopt(h, CURLOPT_WRITEFUNCTION, writer)
    lib.curl_easy_setopt(h, CURLOPT_TIMEOUT, ffi.new("long", opts.timeout or 40))
    lib.curl_easy_setopt(h, CURLOPT_CONNECTTIMEOUT, ffi.new("long", opts.connect_timeout or 10))
    lib.curl_easy_setopt(h, CURLOPT_NOSIGNAL, ffi.new("long", 1))
    lib.curl_easy_setopt(h, CURLOPT_SSL_VERIFYPEER, ffi.new("long", 1))
    lib.curl_easy_setopt(h, CURLOPT_SSL_VERIFYHOST, ffi.new("long", 2))
    lib.curl_easy_setopt(h, CURLOPT_ACCEPT_ENCODING, ffi.cast("const char *", ""))
    if opts.user_agent then
        lib.curl_easy_setopt(h, CURLOPT_USERAGENT, ffi.cast("const char *", opts.user_agent))
    end
    if opts.follow then
        lib.curl_easy_setopt(h, CURLOPT_FOLLOWLOCATION, ffi.new("long", 1))
    end
    if slist ~= nil then
        lib.curl_easy_setopt(h, CURLOPT_HTTPHEADER, slist)
    end
    if opts.auth then
        lib.curl_easy_setopt(h, CURLOPT_USERPWD, ffi.cast("const char *", opts.auth))
        lib.curl_easy_setopt(h, CURLOPT_HTTPAUTH, ffi.new("long", 1))
    end
    if opts.method and opts.method ~= "GET" and opts.method ~= "POST" then
        lib.curl_easy_setopt(h, CURLOPT_CUSTOMREQUEST, ffi.cast("const char *", opts.method))
    end
    if opts.body ~= nil then
        lib.curl_easy_setopt(h, CURLOPT_POSTFIELDS, ffi.cast("const char *", opts.body))
        lib.curl_easy_setopt(h, CURLOPT_POSTFIELDSIZE, ffi.new("long", #opts.body))
    end

    local rc = lib.curl_easy_perform(h)
    local code = ffi.new("long[1]")
    lib.curl_easy_getinfo(h, CURLINFO_RESPONSE_CODE, code)
    local body = table.concat(chunks)
    chunks = nil
    local status = tonumber(code[0])
    local err = nil
    if rc ~= 0 then
        local p = lib.curl_easy_strerror(rc)
        err = p ~= nil and ffi.string(p) or ("curl error " .. tostring(rc))
    end

    if slist ~= nil then lib.curl_slist_free_all(slist) end
    lib.curl_easy_cleanup(h)
    return body, status, err
end

return M
