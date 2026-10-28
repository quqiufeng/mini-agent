#!/usr/bin/env luajit
-- @desc 测试专用语音输出：合成并从音响播放，不写 /tmp/myagent_tts.playing（语音入口仍能听到）
-- @usage tools/test_say.sh "文本" [--voice <KOKORO_SID>] [--keep]
local DIR = (arg[0] or ""):match("^(.*)/") or "."
local TTS = DIR .. "/tts.sh"

local function q(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function sh(cmd)
    return os.execute(cmd) == 0
end

local function has(bin)
    return os.execute("command -v " .. q(bin) .. " >/dev/null 2>&1") == 0
end

local text, voice, keep = {}, "", false
local i = 1
while i <= #arg do
    local a = arg[i]
    if a == "--voice" then
        voice = arg[i + 1] or ""
        i = i + 2
    elseif a == "--keep" then
        keep = true
        i = i + 1
    elseif a == "--help" or a == "-h" then
        print('用法: test_say.sh "文本" [--voice <KOKORO_SID>] [--keep]')
        print("  测试专用：直接播放合成语音，不写 tts 播放锁（麦克风/语音入口不受影响）")
        os.exit(0)
    else
        text[#text + 1] = a
        i = i + 1
    end
end
local s = table.concat(text, " ")
if s == "" then
    io.stderr:write('用法: test_say.sh "文本" [--voice <KOKORO_SID>] [--keep]\n')
    os.exit(2)
end

local wav = string.format("/tmp/myagent_test_say_%d_%d.wav", os.time(), math.random(1000, 9999))
local env = "TTS_NOPLAY=1 TTS_LOCAL_OUT=" .. q(wav)
if voice ~= "" then env = env .. " KOKORO_SID=" .. q(voice) end
if not sh(env .. " " .. q(TTS) .. " " .. q(s)) then
    io.stderr:write("[test_say] 合成失败\n")
    os.exit(1)
end

local f = io.open(wav, "rb")
local sz = f and (f:seek("end") or 0) or 0
if f then f:close() end
if sz == 0 then
    io.stderr:write("[test_say] 合成结果为空: " .. wav .. "\n")
    os.exit(1)
end

print("[test_say] " .. s)
local ok = false
if has("paplay") then ok = sh("paplay " .. q(wav)) end
if not ok and has("pw-play") then ok = sh("pw-play " .. q(wav)) end
if not ok and has("aplay") then ok = sh("aplay -q " .. q(wav)) end
if not ok then
    io.stderr:write("[test_say] 播放失败（需要 paplay/pw-play/aplay）\n")
    os.exit(1)
end

if keep then
    print("[test_say] wav=" .. wav)
else
    os.remove(wav)
end
