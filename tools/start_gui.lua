#!/usr/bin/env luajit
-- tools/start_gui.lua — 启动大脑：tmux(serve+tui) + 一个专用 qterminal 窗口显示 TUI
-- 已有客户端时装在原生窗口里就不再重复开窗；关窗即销毁会话。
local DIR = (arg[0] or ""):match("^(.*)/") or "."
local SESSION = os.getenv("AGENT_SESSION") or "local-my-agent"
local PORT = os.getenv("AGENT_PORT") or "4097"
local WORKDIR = os.getenv("AGENT_WORKDIR") or (DIR:match("^(.*)/tools$") or DIR)
local URL = "http://127.0.0.1:" .. PORT

local function q(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end
local function sh(cmd) return os.execute(cmd) == 0 end
local function sleep(s) os.execute("sleep " .. s) end
local function health() return sh("curl --max-time 1 -sf " .. q(URL .. "/global/health") .. " >/dev/null 2>&1") end
local function has_session() return sh("tmux has-session -t " .. q(SESSION) .. " 2>/dev/null") end
local function has_client()
    local f = io.popen("tmux list-clients -t " .. q(SESSION) .. " 2>/dev/null")
    local s = f and f:read("*a") or ""
    if f then f:close() end
    return #s > 0
end

local function open_window()
    return sh("env -u TMUX qterminal --workdir " .. q(WORKDIR) ..
        " -e " .. q("tmux attach -t " .. SESSION .. ":tui") .. " >/dev/null 2>&1 &")
end

if has_session() then
    if not health() then
        io.stderr:write("tmux 会话存在但 :" .. PORT .. " 不健康；先运行 ./stop.sh\n")
        os.exit(1)
    end
else
    if health() then
        io.stderr:write("端口 " .. PORT .. " 已被其他进程占用\n")
        os.exit(1)
    end
    sh("tmux new-session -d -s " .. SESSION .. " -n serve -c " .. q(WORKDIR) ..
        " " .. q("opencode serve --port " .. PORT))
    local ok = false
    for _ = 1, 50 do
        sleep("0.4")
        if health() then ok = true; break end
    end
    if not ok then
        io.stderr:write("opencode serve 启动失败（端口 " .. PORT .. "）\n")
        os.exit(1)
    end
    sh("tmux new-window -d -t " .. SESSION .. " -n tui -c " .. q(WORKDIR) ..
        " " .. q("opencode attach " .. URL))
end

if not has_client() then
    open_window()
    sleep("2")
end

if has_client() then
    sh("tmux set-option -t " .. SESSION .. " destroy-unattached on 2>/dev/null")
    sh("tmux set-option -t " .. SESSION .. " set-titles on 2>/dev/null")
    sh("tmux set-option -t " .. SESSION .. " set-titles-string 'BRAIN TUI' 2>/dev/null")
end

-- 大脑窗口不要最大化：开成 1000x650 的小窗
sh("ID=$(DISPLAY=${DISPLAY:-:0} xdotool search --name 'BRAIN TUI' 2>/dev/null | tail -1); " ..
   "if [ -n \"$ID\" ]; then DISPLAY=${DISPLAY:-:0} " ..
   q(WORKDIR .. "/tools/win_resize.sh") .. " \"$ID\" 1000 650 460 200 >/dev/null 2>&1; fi")

-- 统一语音回复：默认开启（只念第一句）；VOICE_SPEAK_REPLY=0 关闭
if sh("test \"${VOICE_SPEAK_REPLY:-1}\" != 0") == true then
    sh("setsid nohup " .. q(WORKDIR .. "/tools/speak_watch.sh") ..
        " >>/tmp/myagent-speak-watch.log 2>&1 </dev/null &")
end
