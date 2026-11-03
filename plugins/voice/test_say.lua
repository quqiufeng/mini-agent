#!/usr/bin/env luajit
-- @desc 测试专用语音输出：合成并从音响播放，不写 /tmp/myagent_tts.playing
-- @usage plugins/voice/test_say.sh "文本" [--voice <KOKORO_SID>] [--keep]
local DIR = (arg[0] or ""):match("^(.*)/") or "."
local ROOT = DIR .. "/../.."
package.path = ROOT .. "/lib/?.lua;" .. package.path
local core = require("core")
local TTS = DIR .. "/tts.sh"

local function run(argv, timeout)
    local _, _, rc = core.exec_argv(argv, { timeout = timeout or 120 })
    return rc == 0
end
local function has(bin) return core.which(bin) ~= nil end

local text, voice, keep = {}, "", false
local i = 1
while i <= #arg do
    local a = arg[i]
    if a == "--voice" then voice = arg[i + 1] or ""; i = i + 2
    elseif a == "--keep" then keep = true; i = i + 1
    elseif a == "--help" or a == "-h" then
        print('用法: test_say.sh "文本" [--voice <KOKORO_SID>] [--keep]'); os.exit(0)
    else text[#text + 1] = a; i = i + 1 end
end
local s = table.concat(text, " ")
if s == "" then io.stderr:write('用法: test_say.sh "文本" [--voice <KOKORO_SID>] [--keep]\n'); os.exit(2) end
local wav = string.format("/tmp/myagent_test_say_%d_%d.wav", os.time(), math.random(1000, 9999))
local env = { "/usr/bin/env", "TTS_NOPLAY=1", "TTS_LOCAL_OUT=" .. wav }
if voice ~= "" then env[#env + 1] = "KOKORO_SID=" .. voice end
env[#env + 1] = TTS; env[#env + 1] = s
if not run(env) then io.stderr:write("[test_say] 合成失败\n"); os.exit(1) end
local sz = core.read(wav) and #(core.read(wav)) or 0
if sz == 0 then io.stderr:write("[test_say] 合成结果为空: " .. wav .. "\n"); os.exit(1) end
print("[test_say] " .. s)
local ok = false
for _, bin in ipairs({ "paplay", "pw-play", "aplay" }) do
    if has(bin) then
        local argv = { bin }
        if bin == "aplay" then argv[#argv + 1] = "-q" end
        argv[#argv + 1] = wav
        if run(argv) then ok = true; break end
    end
end
if not ok then io.stderr:write("[test_say] 播放失败（需要 paplay/pw-play/aplay）\n"); os.exit(1) end
if keep then print("[test_say] wav=" .. wav) else os.remove(wav) end
