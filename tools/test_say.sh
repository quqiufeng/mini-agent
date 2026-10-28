#!/usr/bin/env bash
# @desc 测试专用语音输出：合成并播放指定文本；不写 tts 播放锁，不影响麦克风/语音入口
# @usage tools/test_say.sh "文本" [--voice <KOKORO_SID>] [--keep]
# @rule 仅用于自主语音闭环测试（音响说、语音入口自己听）；普通回复仍用 speak_watch/tts.sh。
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/lua.sh" "$DIR/test_say.lua" "$@"
