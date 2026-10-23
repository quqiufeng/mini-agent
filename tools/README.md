# tools — 本地能力层

约定：

- 每个能力一个 `tools/<name>.sh`，头部写 `@desc`、`@usage`，可选 `@rule`。
- **本机能做的**：直接在脚本里实现（如时间、VLC 播放、ADB 切 HDMI、截图、NAS 访问）。
- **本机做不了的**：用 `tools/remote.sh <name> [args...]` 调用远程 `/opt/my-agent/operator/tools/<name>.sh`；需要传环境变量时用 `tools/remote.sh --env K=V <name> ...`。
- 大脑只调用 `tools/*.sh`，不要临时拼一长串命令。
- 依赖：`python3-requests`、`python3-numpy`、`python3-websocket`、`scrcpy`、`adb`、Chrome、`xdotool`、`scrot`。

示例：

```bash
tools/doctor.sh               # 检查依赖/大脑/远程/手机/Chrome
tools/list.sh                 # 列出本地工具
tools/now.sh                  # 本机时间
tools/tts.sh "你好"            # 远程合成、scp 到本机、PipeWire 小音响播放
tools/asr.sh /tmp/x.wav       # 调远程 voice/listen.sh 识别
tools/spectrum.sh 32 30       # USB 麦克风频谱流（JSON Lines）
tools/record_mic.sh 5 /tmp/x.wav  # 录 USB 麦克风到 WAV
tools/chrome.sh open https://example.com
tools/chrome.sh dump https://example.com
tools/chrome.sh shot https://example.com /tmp/x.png
tools/chrome.sh cdp 9222
tools/google_search.sh "关键词"   # 本机 Chrome CDP 搜 Google
tools/deepseek_search.sh "关键词" # DeepSeek Search API
tools/phone_music.sh play     # 手机汽水音乐 → 小音响
tools/phone_audio.sh status   # 手机音频转发状态
tools/tv_play.sh 寒战         # 电视 VLC 直连 NAS 播放（本机只做遥控）
tools/tv_play.sh --find 寒战  # 只搜路径不播放
tools/tv_play.sh stop         # 停止电视播放
tools/tencent.sh 寒战         # 电视腾讯视频按首字母搜索（默认只搜不播）
tools/tencent.sh 寒战 --play  # 搜索并播放第一集
tools/tencent.sh 伟大的长征 --expect 伟大的长征  # 逐字母 OCR 校验 + 详情页标题校验
tools/remote.sh now           # 调远程 now.sh
```

新增：

```bash
cp tools/_template.sh tools/mytool.sh
# 写实现，然后 tools/list.sh 能看到 @desc
```
