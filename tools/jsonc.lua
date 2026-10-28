local ffi = require("ffi")

ffi.cdef[[
typedef struct json_object json_object;
json_object *json_tokener_parse(const char *str);
void json_object_put(json_object *obj);
int json_object_get_type(json_object *obj);
const char *json_object_get_string(json_object *obj);
long long json_object_get_int64(json_object *obj);
int json_object_get_boolean(json_object *obj);
int json_object_array_length(json_object *obj);
json_object *json_object_array_get_idx(json_object *obj, int idx);
int json_object_object_get_ex(json_object *obj, const char *key, json_object **value);
int json_object_object_length(json_object *obj);
]]

local lib
for _, name in ipairs({ "json-c", "libjson-c.so.5", "libjson-c.so.4" }) do
    local ok, h = pcall(ffi.load, name)
    if ok then lib = h; break end
end
assert(lib, "无法加载 libjson-c")

local J = {}

J.NULL, J.BOOL, J.DOUBLE, J.INT, J.OBJECT, J.ARRAY, J.STRING = 0, 1, 2, 3, 4, 5, 6

function J.parse(s)
    if not s or s == "" then return nil end
    local o = lib.json_tokener_parse(s)
    if o == nil then return nil end
    return o
end

function J.free(o)
    if o ~= nil then lib.json_object_put(o) end
end

function J.type(o)
    if o == nil then return nil end
    return lib.json_object_get_type(o)
end

function J.get(o, path)
    local cur = o
    if cur == nil then return nil end
    for seg in tostring(path):gmatch("[^%.]+") do
        local t = lib.json_object_get_type(cur)
        if t == J.ARRAY then
            local idx = tonumber(seg)
            if not idx then return nil end
            cur = lib.json_object_array_get_idx(cur, idx)
        elseif t == J.OBJECT then
            local out = ffi.new("json_object*[1]")
            if lib.json_object_object_get_ex(cur, seg, out) == 0 then return nil end
            cur = out[0]
        else
            return nil
        end
        if cur == nil then return nil end
    end
    return cur
end

function J.str(o, path)
    local v = J.get(o, path)
    if v == nil then return nil end
    local t = lib.json_object_get_type(v)
    if t == J.STRING then
        local p = lib.json_object_get_string(v)
        return p ~= nil and ffi.string(p) or nil
    elseif t == J.INT then
        return tostring(lib.json_object_get_int64(v))
    elseif t == J.BOOL then
        return lib.json_object_get_boolean(v) ~= 0 and "true" or "false"
    end
    return nil
end

function J.int(o, path)
    local v = J.get(o, path)
    if v == nil then return nil end
    local t = lib.json_object_get_type(v)
    if t == J.INT or t == J.DOUBLE then return tonumber(lib.json_object_get_int64(v)) end
    return nil
end

function J.bool(o, path)
    local v = J.get(o, path)
    if v == nil then return nil end
    return lib.json_object_get_boolean(v) ~= 0
end

function J.len(o, path)
    local v = path and J.get(o, path) or o
    if v == nil then return 0 end
    local t = lib.json_object_get_type(v)
    if t == J.ARRAY then return lib.json_object_array_length(v) end
    if t == J.OBJECT then return lib.json_object_object_length(v) end
    return 0
end

return J
