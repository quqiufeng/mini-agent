# tools — 本地能力层

约定：

- 每个能力一个 `tools/<name>.sh`，头部写 `@desc`、`@usage`，可选 `@rule`。
- **本机能做的**：直接在脚本里实现（如时间、VLC 播放、ADB 切 HDMI、截图、NAS 访问）。
- **本机做不了的**：用 `tools/remote.sh <name> [args...]` 调用远程 `/opt/my-agent/operator/tools/<name>.sh`；需要传环境变量时用 `tools/remote.sh --env K=V <name> ...`。
- 大脑只调用 `tools/*.sh`，不要临时拼一长串命令。
- 依赖：`libcurl`、`libjson-c`、`libfftw3`、`ffmpeg`、`scrcpy`、`adb`、Chrome、`xdotool`、`scrot`、`parec`；本机已无 Python 脚本。

示例：

```bash
tools/lua.sh -e 'print(jit.version)'   # 优先用内嵌 LuaJIT 的 GUI 二进制，无需系统 luajit
tools/http.lua / jsonc.lua / ws.lua / util.lua   # 内部 FFI 模块：libcurl / libjson-c / WebSocket / URL/base64
tools/netscan.sh tcp 192.168.1 5555 400           # UDP 触发 ARP / TCP 扫描（netmap、phone_ip 内部用）
tools/doctor.sh               # 检查依赖/大脑/远程/手机/Chrome
tools/list.sh                 # 列出本地工具
tools/now.sh                  # 本机时间
tools/tts.sh "你好"            # 本地 Kokoro 合成（失败回退远程）→ 小音响
tools/asr.sh /tmp/x.wav       # 本地 SenseVoice.cpp 识别（失败回退远程）
tools/ocr.sh /tmp/x.png       # 本地 PP-OCRv4 识别（失败回退远程）
tools/alarm.sh in 10m "关火"   # 本地闹钟，到点语音提醒 5 遍；at 7:30 起床
tools/phone2.sh status         # 第二台 Redmi 手机：mDNS 自动连无线调试
tools/phone2.sh open wechat    # 打开微信；text 输入中文；shot 截图
tools/spectrum.sh 32 30       # USB 麦克风频谱流（JSON Lines，LuaJIT + FFTW3）
tools/record_mic.sh 5 /tmp/x.wav  # 录 USB 麦克风到 WAV
tools/test_say.sh "测试语音输出"   # 测试专用：不写 tts 播放锁，麦克风/语音入口不受影响
tools/chrome.sh open https://example.com
tools/chrome.sh dump https://example.com
tools/chrome.sh shot https://example.com /tmp/x.png
tools/chrome.sh cdp 9222
tools/google_search.sh "关键词"   # 本机 Chrome CDP 搜 Google
tools/deepseek_search.sh "关键词"              # DeepSeek 搜索
tools/deepseek_search.sh "关键词" --count 3 --content
tools/deepseek_search.sh fetch https://example.com  # 抓单页 Markdown
tools/tv_play.sh 寒战         # 电视 VLC 直连 NAS 播放（LuaJIT FFI，本机只做遥控）
tools/tv_play.sh --find 寒战  # 只搜路径不播放
tools/tv_play.sh stop         # 停止电视播放
tools/tv_on.sh                 # 唤醒电视并切到 Android 首页
tools/tv_on.sh --input hdmi3   # 切回 HDMI3
tools/media.sh play 周杰伦     # NAS 搜索歌曲/美剧/电影 → 本机 VLC → USB 小音箱
tools/media.sh play 硅谷 --fullscreen  # 视频全屏到电视
tools/media.sh stop            # 停止播放
tools/volume.sh up / down      # 调 USB 小音箱 + 电视音量
tools/volume.sh mute           # 静音切换
tools/appshot.sh               # 抓当前应用截图给 GUI 右侧预览
tools/tencent.sh 寒战         # 电视腾讯视频按首字母搜索（默认只搜不播）
tools/tencent.sh 寒战 --play  # 搜索并播放第一集
tools/tencent.sh 伟大的长征 --expect 伟大的长征  # 逐字母 OCR 校验 + 详情页标题校验
tools/kws_keywords.sh "你好星期五,程序员,退出程序员"  # 生成 KWS 拼音关键词（ICU uconv，无 Python）
tools/setup_local_voice.sh    # 安装本地 KWS/Kokoro/SenseVoice
tools/setup_local_ocr.sh      # 安装本地 PP-OCRv4 + ONNX Runtime
tools/netmap.sh scan          # 扫描本机局域网，生成 NETWORK.local.md / devices.local.*
tools/netmap.sh show          # 查看上次拓扑
tools/netmap.sh sources       # 输出 NETMAP_*_IP 变量
tools/remote.sh netmap show   # 调远程 netmap.sh
```

新增：

```bash
cp tools/_template.sh tools/mytool.sh
# 写实现，然后 tools/list.sh 能看到 @desc
```

开发/测试闭环：实现 → 直接跑命令 → 真实界面用 `scrot`+`read` 或 `tools/ocr.sh` 回读 → 语音用 `tts.sh`/`record_mic.sh`/`asr.sh` 回环 → 更新 `AGENTS.md` 5.3/5.4 与 `tools/README.md` → 重启大脑复测。返回码 0 不算通过。

实现原则：不新增 Python；优先 LuaJIT FFI 直调系统 `.so`（`tools/http.lua` 用 libcurl，`tools/jsonc.lua` 用 libjson-c，`tools/xdo.lua` 用 X11/libxdo）；系统库也没有的硬核逻辑写 C，暴露 C ABI 给 FFI；`.sh` 只做薄入口。本机不保留 Python 脚本：拼音用 ICU uconv，构建期嵌入用 Lua。
