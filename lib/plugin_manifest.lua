-- lib/plugin_manifest.lua — 插件清单（intents / session_commands / context）
local here = (debug.getinfo(1, "S").source:gsub("^@", "")):match("^(.*)/") or "."
package.path = here .. "/?.lua;" .. package.path
local core = require("core")
local JSON = require("json")

local ROOT = here:match("^(.*)/lib$") or (here .. "/..")
local M = {}
local cache

function M.scan(force)
    if cache and not force then return cache end
    local out, seen = {}, {}
    for _, group in ipairs(core.list_dir(ROOT .. "/plugins")) do
        local path = ROOT .. "/plugins/" .. group .. "/plugin.json"
        local raw = core.read(path)
        local spec = raw and JSON.decode(raw) or nil
        if type(spec) == "table" then
            local name = spec.id or spec.name or group
            spec.name = name
            spec.group = group
            spec.path = path
            spec.intents = spec.intents or {}
            spec.session_commands = spec.session_commands or {}
            spec.context = spec.context or {}
            spec.session_defaults = spec.session_defaults or {}
            if not seen[name] then
                out[#out + 1] = spec
                seen[name] = true
            end
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    cache = out
    return out
end

function M.find(name)
    for _, p in ipairs(M.scan()) do if p.name == name or p.id == name then return p end end
    return nil
end

function M.get(name) return M.find(name) end
function M.list() return M.scan() end
function M.reload() cache = nil; return M.scan(true) end

return M
