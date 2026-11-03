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
lib/http.lua / jsonc.lua / ws.lua / util.lua   # 内部 FFI 模块：libcurl / libjson-c / WebSocket / URL/base64
plugins/system/netscan.sh tcp 192.168.1 5555 400           # UDP 触发 ARP / TCP 扫描（netmap、phone_ip 内部用）
tools/devctl.sh status         # 统一设备操作入口（状态/媒体/手机/镜像/音量/摄像头）
tools/state.sh show            # 统一状态：~/.myagent/state
plugins/system/doctor.sh               # 检查依赖/大脑/远程/手机/Chrome
tools/list.sh                 # 列出本地工具
tools/now.sh                  # 本机时间
plugins/voice/tts.sh "你好"            # 本地 Kokoro 合成（失败回退远程）→ 小音响
plugins/voice/asr.sh /tmp/x.wav       # 本地 SenseVoice.cpp 识别（失败回退远程）
plugins/system/ocr.sh /tmp/x.png       # 本地 PP-OCRv4 识别（失败回退远程）
plugins/system/alarm.sh in 10m "关火"   # 本地闹钟，到点语音提醒 5 遍；at 7:30 起床
plugins/phone/phone2.sh status         # 第二台 Redmi 手机：mDNS 自动连无线调试
plugins/phone/phone2.sh open wechat    # 打开微信；text 输入中文；shot 截图
plugins/wechat/wechat.sh start    # 打开微信并镜像到 GUI“当前应用”预览（scrcpy）
plugins/voice/spectrum.sh 32 30       # USB 麦克风频谱流（JSON Lines，LuaJIT + FFTW3）
tools/record_mic.sh 5 /tmp/x.wav  # 录 USB 麦克风到 WAV
plugins/voice/test_say.sh "测试语音输出"   # 测试专用：不写 tts 播放锁；小音箱出声时监听仍按全局状态暂停
tools/speaker_watch.sh status # 小音箱常驻监视（busy/idle），语音入口据此自动暂停/恢复监听
plugins/system/chrome.sh open https://example.com
plugins/system/chrome.sh dump https://example.com
plugins/system/chrome.sh shot https://example.com /tmp/x.png
plugins/system/chrome.sh cdp 9222
plugins/system/google_search.sh "关键词"   # 本机 Chrome CDP 搜 Google
plugins/system/deepseek_search.sh "关键词"              # DeepSeek 搜索
plugins/system/deepseek_search.sh "关键词" --count 3 --content
plugins/system/deepseek_search.sh fetch https://example.com  # 抓单页 Markdown
plugins/tv/tv_play.sh 寒战         # 电视 VLC 直连 NAS 播放（LuaJIT FFI，本机只做遥控）
plugins/tv/tv_play.sh --find 寒战  # 只搜路径不播放
plugins/tv/tv_play.sh stop         # 停止电视播放
plugins/tv/tv_on.sh                 # 唤醒电视并切到 Android 首页
plugins/tv/tv_on.sh --input hdmi3   # 切回 HDMI3
plugins/media/media.sh play 周杰伦     # NAS 搜索歌曲/美剧/电影 → 本机 VLC → USB 小音箱（音频整列表顺序播放）
plugins/media/media.sh play 硅谷 --fullscreen  # 视频全屏到电视
plugins/media/media.sh pause / resume  # 暂停/继续（暂停时最小化 VLC）
plugins/media/media.sh next / prev     # 下一首/上一首（MPRIS）
plugins/media/media.sh stop            # 停止并退出 VLC
plugins/camera/camera_block.sh status   # 遮住摄像头暂停（播放时自动启动）
plugins/system/volume.sh up / down      # 调 USB 小音箱 + 电视音量
plugins/system/volume.sh mute           # 静音切换
plugins/system/appshot.sh               # 抓当前应用截图给 GUI 右侧预览
plugins/tv/tencent.sh 寒战         # 电视腾讯视频按首字母搜索（默认只搜不播）
plugins/tv/tencent.sh 寒战 --play  # 搜索并播放第一集
plugins/tv/tencent.sh 伟大的长征 --expect 伟大的长征  # 逐字母 OCR 校验 + 详情页标题校验
plugins/voice/kws_keywords.sh "你好星期五,程序员,退出程序员"  # 生成 KWS 拼音关键词（ICU uconv，无 Python）
tools/setup_local_voice.sh    # 安装本地 KWS/Kokoro/SenseVoice
tools/setup_local_ocr.sh      # 安装本地 PP-OCRv4 + ONNX Runtime
plugins/system/netmap.sh scan          # 扫描本机局域网，生成 NETWORK.local.md / devices.local.*
plugins/system/netmap.sh show          # 查看上次拓扑
plugins/system/netmap.sh sources       # 输出 NETMAP_*_IP 变量
tools/remote.sh netmap show   # 调远程 netmap.sh
```

新增：

```bash
cp tools/_template.sh tools/mytool.sh
# 写实现，然后 tools/list.sh 能看到 @desc
```

开发/测试闭环：实现 → 直接跑命令 → 真实界面用 `scrot`+`read` 或 `plugins/system/ocr.sh` 回读 → 语音用 `tts.sh`/`record_mic.sh`/`asr.sh` 回环 → 更新 `AGENTS.md` 5.3/5.4 与 `tools/README.md` → 重启大脑复测。返回码 0 不算通过。

实现原则：不新增 Python；优先 LuaJIT FFI 直调系统 `.so`（`lib/http.lua` 用 libcurl，`lib/jsonc.lua` 用 libjson-c，`tools/xdo.lua` 用 X11/libxdo）；系统库也没有的硬核逻辑写 C，暴露 C ABI 给 FFI；`.sh` 只做薄入口。本机不保留 Python 脚本：拼音用 ICU uconv，构建期嵌入用 Lua。
