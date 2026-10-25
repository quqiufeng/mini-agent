#!/usr/bin/env luajit
-- tools/start_gui.lua — 用 LuaJIT FFI 打开一个终端 tab，在里面键入 tmux 命令
-- tmux 提供两个窗口（标签）：serve 与 tui；destroy-unattached 让关掉终端即停。
local DIR = (arg[0] or ""):match("^(.*)/") or "."
package.path = DIR .. "/?.lua;" .. package.path
local Xdo = require("xdo")

local SESSION = os.getenv("AGENT_SESSION") or "local-my-agent"
local PORT = os.getenv("AGENT_PORT") or "4097"
local WORKDIR = os.getenv("AGENT_WORKDIR") or (DIR:match("^(.*)/tools$") or DIR)
local URL = "http://127.0.0.1:" .. PORT

local function q(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end
local function sleep(s) os.execute("sleep " .. s) end
local function health()
    return os.execute("curl --max-time 1 -sf " .. q(URL .. "/global/health") .. " >/dev/null 2>&1") == 0
end
local function has_session()
    return os.execute("tmux has-session -t " .. q(SESSION) .. " 2>/dev/null") == 0
end
local function has_window(name)
    local f = io.popen("tmux list-windows -t " .. q(SESSION) .. " -F '#{window_name}' 2>/dev/null")
    local s = f and f:read("*a") or ""
    if f then f:close() end
    return s:find(name, 1, true) ~= nil
end

local d, err = Xdo.new()
if not d then io.stderr:write("Xdo: " .. tostring(err) .. "\n"); os.exit(1) end

local function qterms()
    local out = {}
    for _, w in ipairs(d:find_class("qterminal")) do out[tonumber(w.id)] = w end
    return out
end

local function launch_terminal()
    local before = {}
    for id in pairs(qterms()) do before[id] = true end
    if os.execute("qterminal --workdir " .. q(WORKDIR) .. " >/dev/null 2>&1 &") ~= 0 then
        return nil, "qterminal 启动失败"
    end
    for _ = 1, 60 do
        sleep("0.2")
        for id, w in pairs(qterms()) do
            if not before[id] then
                sleep("1.2")
                return w
            end
        end
    end
    return nil, "未等到 qterminal 窗口"
end

-- 打字前切英文（libpinyin 会把 ASCII 转成中文），结束还原
local function ime_get()
    local f = io.popen("ibus engine 2>/dev/null")
    local s = f and f:read("*a") or ""
    if f then f:close() end
    return (s:gsub("%s+", ""))
end
local IME_SAVED = ime_get()
os.execute("ibus engine xkb:us::eng 2>/dev/null")
local function ime_restore()
    if IME_SAVED ~= "" and IME_SAVED ~= "xkb:us::eng" then
        os.execute("ibus engine " .. IME_SAVED .. " 2>/dev/null")
    end
end

local win, lerr = launch_terminal()
if not win then
    ime_restore(); io.stderr:write(tostring(lerr) .. "\n"); os.exit(1)
end

local function type_cmd(text)
    d:activate(win.id)
    sleep("0.25")
    d:type(win.id, text, 8000)
    sleep("0.15")
    d:key(win.id, "Return")
end

local function warn_and_exit(msg)
    ime_restore(); io.stderr:write(msg .. "\n"); os.exit(1)
end

if has_session() then
    if not health() then
        warn_and_exit("tmux 会话存在但 :" .. PORT .. " 不健康；先运行 ./stop.sh")
    end
    if not has_window("tui") then
        os.execute("tmux new-window -d -t " .. q(SESSION) .. " -n tui -c " .. q(WORKDIR) ..
            " " .. q("opencode attach " .. URL))
    end
else
    if health() then
        warn_and_exit("端口 " .. PORT .. " 已被其他进程占用")
    end
    type_cmd("tmux new-session -d -s " .. SESSION .. " -n serve -c " .. q(WORKDIR) ..
        " " .. q("opencode serve --port " .. PORT))
    for _ = 1, 50 do
        sleep("0.4")
        if health() then break end
    end
    if not health() then warn_and_exit("opencode serve 启动失败（端口 " .. PORT .. "）") end
    type_cmd("tmux new-window -d -t " .. SESSION .. " -n tui -c " .. q(WORKDIR) ..
        " " .. q("opencode attach " .. URL))
end

type_cmd("tmux attach -t " .. SESSION .. ":tui")
sleep("1.0")
-- 已 attach 后再设：关掉终端（最后一个 client 断开）即销毁会话，避免后台残留
os.execute("tmux set-option -t " .. q(SESSION) .. " destroy-unattached on 2>/dev/null")
ime_restore()
