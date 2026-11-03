#!/usr/bin/env luajit
-- tools/start_gui.lua — 启动大脑：tmux(serve+tui) + 一个专用 qterminal 窗口显示 TUI
local DIR = (arg[0] or ""):match("^(.*)/") or "."
local ROOT = DIR .. "/.."
package.path = ROOT .. "/lib/?.lua;" .. package.path
package.path = DIR .. "/?.lua;" .. package.path
local core = require("core")
local SESSION = os.getenv("AGENT_SESSION") or "local-my-agent"
local PORT = os.getenv("AGENT_PORT") or "4097"
local WORKDIR = os.getenv("AGENT_WORKDIR") or (DIR:match("^(.*)/tools$") or DIR)
local BRAIN_ENV = "AGENT_BRAIN=1 OPENCODE_CONFIG=" .. WORKDIR .. "/opencode.json"
local URL = "http://127.0.0.1:" .. PORT

local function run(argv, timeout)
    local out, _, rc = core.exec_argv(argv, { timeout = timeout or 10 })
    return rc == 0, out
end
local function health() return run({ "/usr/bin/curl", "--max-time", "1", "-sf", URL .. "/global/health" }, 3) end
local function has_session() return run({ "tmux", "has-session", "-t", SESSION }, 3) end
local function has_client()
    local ok, out = run({ "tmux", "list-clients", "-t", SESSION }, 3)
    return ok and out and #out > 0
end
local function open_window()
    core.spawn_argv({ "/usr/bin/env", "-u", "TMUX", "qterminal", "--workdir", WORKDIR,
                      "-e", "tmux attach -t " .. SESSION .. ":tui" },
                    { log = "/tmp/myagent-start-gui.log" })
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
    run({ "tmux", "new-session", "-d", "-s", SESSION, "-n", "serve", "-c", WORKDIR,
          "env " .. BRAIN_ENV .. " opencode serve --port " .. PORT }, 10)
    local ok = false
    for _ = 1, 50 do
        core.sleep(0.4)
        if health() then ok = true; break end
    end
    if not ok then
        io.stderr:write("opencode serve 启动失败（端口 " .. PORT .. "）\n")
        os.exit(1)
    end
    run({ "tmux", "new-window", "-d", "-t", SESSION, "-n", "tui", "-c", WORKDIR,
          "opencode attach " .. URL }, 10)
end

if not has_client() then
    open_window()
    core.sleep(2)
end

if has_client() then
    run({ "tmux", "set-option", "-t", SESSION, "destroy-unattached", "on" })
    run({ "tmux", "set-option", "-t", SESSION, "set-titles", "on" })
    run({ "tmux", "set-option", "-t", SESSION, "set-titles-string", "BRAIN TUI" })
end

-- 大脑窗口不要最大化：开成 1000x650 的小窗
do
    local ok, out = run({ "xdotool", "search", "--name", "BRAIN TUI" }, 3)
    local id = ok and out and out:match("([0-9]+)%s*$") or nil
    if id then
        local okx, Xdo = pcall(require, "xdo")
        if okx then
            local d = Xdo.new(os.getenv("DISPLAY"))
            local w = tonumber(id)
            if d and w then
                local sw = d:display_size()
                local left = math.floor((sw - 480 - 970) / 2)
                d:unmaximize_resize(w, left + 480, 61, 970, 894)
                d:set_above(w, false)
            end
        end
    end
end

-- 统一语音回复：默认开启；VOICE_SPEAK_REPLY=0 关闭
if (os.getenv("VOICE_SPEAK_REPLY") or "1") ~= "0" then
    core.spawn_argv({ WORKDIR .. "/plugins/voice/speak_watch.sh" }, { log = "/tmp/myagent-speak-watch.log" })
end
