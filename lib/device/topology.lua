-- lib/device/topology.lua — 设备拓扑（注册表 links/edges 的只读视图）
local here = (debug.getinfo(1, "S").source:gsub("^@", "")):match("^(.*)/") or "."
package.path = here .. "/?.lua;" .. here .. "/../?.lua;" .. package.path
local cache = require("cache")
local M = {}
function M.get() return cache.topology() end
function M.nodes() local t=M.get(); return t and t.nodes or {} end
function M.edges() local t=M.get(); return t and t.edges or {} end
function M.refresh()
    local registry = require("registry")
    local reg = registry.refresh(true)
    local t = { generated = reg.generated, nodes = reg.devices, edges = reg.edges }
    cache.put_topology(t)
    return t
end
return M
