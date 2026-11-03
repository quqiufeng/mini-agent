#!/usr/bin/env luajit
-- @desc 用 ICU uconv 生成 sherpa-onnx 拼音 KWS 关键词（无需 Python/pypinyin）
-- @usage plugins/voice/kws_keywords.sh "你好星期五,程序员,退出程序员"
local DIR = (arg[0] or ""):match("^(.*)/") or "."
local ROOT = DIR .. "/../.."
package.path = ROOT .. "/lib/?.lua;" .. package.path
local core = require("core")

local INITIALS = { "zh", "ch", "sh", "b", "p", "m", "f", "d", "t", "n", "l",
                   "g", "k", "h", "j", "q", "x", "r", "z", "c", "s", "y", "w" }

local function split_syllable(syl)
    for _, ini in ipairs(INITIALS) do
        if #syl > #ini and syl:sub(1, #ini) == ini then
            return { ini, syl:sub(#ini + 1) }
        end
    end
    return { syl }
end

local function pinyin(text)
    local tmp = string.format("/tmp/myagent_kws_%d_%d.txt", os.time(), math.random(1000, 9999))
    if not core.write_atomic(tmp, text) then return nil end
    local out, _, rc = core.exec_argv({ "uconv", "-x", "Han-Latin", tmp }, { timeout = 10 })
    os.remove(tmp)
    if rc ~= 0 or not out then return nil end
    local s = out:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if s == "" then return nil end
    return s
end

local text = table.concat(arg, " ")
if text == "" then text = os.getenv("VOICE_WAKE") or "你好星期五,程序员,退出程序员" end
local seen = {}
for word in text:gsub("，", ","):gmatch("[^,]+") do
    word = word:gsub("^%s+", ""):gsub("%s+$", "")
    if word ~= "" and not seen[word] then
        seen[word] = true
        local py = pinyin(word)
        if py then
            local toks = {}
            for syl in py:gmatch("%S+") do
                for _, t in ipairs(split_syllable(syl)) do toks[#toks + 1] = t end
            end
            print(table.concat(toks, " ") .. " @" .. word)
        end
    end
end
