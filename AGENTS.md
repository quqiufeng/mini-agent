# AGENTS.md

本文件记录本机/远程环境的常用工作技巧。

核心原则：**本机能做的用本地 `~/my-agent/tools/*.sh` 实现；本机做不了的，用本地脚本调用远程 `192.168.1.10` 的 `/opt/my-agent`。** 使用脚本前先读脚本头部注释。

## 1. 长任务监控：sleep 轮询

适用场景：模型训练、长时间构建等需要持续盯着的任务。

- 每隔固定时间执行一次 `sleep`，间隔按任务情况调整（例如 10 分钟）。
- `sleep` 结束后检查任务是否正常。
- 有问题就解决；没问题就继续 `sleep`，如此往复。

典型提示词：

> 每隔 10 分钟执行一次 sleep，sleep 完成后检查任务是否正常；有问题就解决，没有问题就继续 sleep，如此往复。

## 2. 远程机器：截图与窗口操作

### 2.1 用截图“看见”远程机器

适用场景：需要了解远程机器上正在做什么，例如终端里运行的任务、打开的标签页。

1. `ssh` 连接到目标机器。
2. 用截屏工具抓取画面并保存为文件。
3. 用 `scp` 把截图传到本地 `/tmp`。
4. 用 `read` 工具读取图片，理解远程当前状态。
5. 可多次截图确认，拿到确定信息。

### 2.2 用 xdotool 切换窗口和标签页

适用场景：远程桌面有终端或其他 GUI 应用，需要查看各标签页/窗口里的任务。

1. 从目标进程的 `/proc/<pid>/environ` 获取 `DISPLAY` 和 `XAUTHORITY`。
2. 用 `wmctrl -l` 或 `xdotool search --name/--class` 找到窗口。
3. 用 `xdotool windowactivate` 聚焦窗口，用 `xdotool key`（如 `ctrl+Next`、`ctrl+Prior`）或点击坐标切换标签页。
4. 每切换一次就截图并用 `read` 查看。
5. 检查完切回原标签页，避免打扰远程用户。

注意：xdotool 只用于窗口聚焦和标签切换，不用于操作页面内容；页面内容走远程 Chrome/CDP。

### 2.4 本机硬件（客厅小机箱）

- 小音箱：**USB DTC 480**（USB DAC），默认输出 sink：`alsa_output.usb-DUNU_DTC_480_DTC_480-00.analog-stereo`；`wpctl set-default 58` 固定。
- USB 麦克风：`card 1: Comica_EJoy Uni`。
- HDMI：`HDMI-1` 输出 1920×1080，接 Sony 电视 HDMI3；电视显示区域设为“全像素”。
- 已安装 `adb`（1.0.41 / 34.0.4）。电视 `192.168.1.110:5555` 已授权：
  `Sony BRAVIA 4K GB`（`BRAVIA_ATV2_CN`），Android 8.0.0。

### 2.5 用 ADB 控制 Sony 电视

连接与常用命令：

```bash
adb connect 192.168.1.110:5555
adb devices -l
adb -s 192.168.1.110:5555 shell '...'
```

- 唤醒：`input keyevent 224`
- 切 HDMI2 / HDMI3：`input keyevent 244` / `245`
- 查看当前输入：`dumpsys tv_input | grep -E 'mainSessionToken|hdmi_port'`
  （`HW4 + hdmi_port=3` 表示当前在 HDMI3）
- 待机/假关机：`input keyevent 26`；**严禁真实断电/重启**
- 应用：`pm list packages`、`am start -n <包>/<Activity>`、`input keyevent 3`（Home）、`4`（Back）
- 点击/输入：`input tap X Y`、`input text "..."`、`input keyevent <KEYCODE>`
- TV UI 自动化：`uiautomator dump /sdcard/ui.xml` + `adb pull`，解析 `text`/`bounds` 后 `input tap`
- 截图：`screencap -p /sdcard/tv.png` 再 `adb pull`；仅能抓 TV 主页/设置等 Android UI
- 限制：切到 HDMI 输入后 `screencap` 返回 0 字节，`screenrecord` 无有效帧，无法用 adb 抓 HDMI 画面

显示设置路径：设置 → 显示 → 屏幕设定（16:9、自动显示区域、显示区域=全像素）。

### 2.5.1 电视直连 NAS 播放（首选）

电视已装 VLC 3.7.1（`org.videolan.vlc`），并改为有线（`192.168.1.110`）。看电影优先让**电视自己拉 NAS 流**，本机只拼直链 + adb 唤起，不转码不中继：

```bash
tools/tv_play.sh 寒战          # 在 NAS 媒体库搜索并播放（多个取最大）
tools/tv_play.sh --find 寒战   # 只搜不播
tools/tv_play.sh stop          # 停止（返回键）
tools/tv_play.sh "寒站1994/寒战...mkv"   # 直接给相对路径
```

- 直链形如 `http://用户:密码@192.168.1.53:5005/sata11-18072858035/...`，Basic 认证写在 URL 里；局域网内可接受。
- 实测 4K HEVC（3.25GB、约 4Mbps）电视直连流畅，VLC 硬解，CPU 约 11%。
- 搜索用 WebDAV PROPFIND 分层并发（约 5 秒）；`find` 不能直接用 `dav://`，需用 GVFS 挂载路径，且全库 find 很慢。
- 截图验证：`adb -s 192.168.1.110:5555 exec-out screencap -p > /tmp/tv.png`。

### 2.5.2 电视腾讯视频（云视听极光）

`tools/tencent.sh <关键词>`：中文转拼音首字母，用 app 内置 T9 键盘搜索（默认不播放）：

```bash
tools/tencent.sh 寒战          # 搜“hz”，结果截图 /tmp/tencent_search.png
tools/tencent.sh 寒战 --play   # 搜索后按 OK 播放第一集
tools/tencent.sh 庆余年 --full # 用全拼而不是首字母
tools/tencent.sh 伟大的长征 --expect 伟大的长征   # 搜索并用 OCR 校验详情页标题
```

- 屏幕固定 1920×1080；T9 网格坐标由 OCR 实测：列 x=(330 409 488 568 648 729)，行 y=(384 463 543 623 703 783)，不要按截图目测。
- 点击语义：单击只聚焦，聚焦后再点一次才输入；脚本逐字母输入，**每点一次都截图 + OCR 核对输入框**，多退少补（退格 (531,275)；输入框区域 x 335-720、y 160-215），不用盲目的双击。
- 多音字：uconv 默认把「长」读成 zhǎng；脚本先用词表纠正（长征→chang zheng），所以 伟大的长征 → wddcz。
- 输入 2 个字母（如 wd）时联想列表已出现「伟大的长征」；完整输入后走：点「清空」→ 右移 3 次 → OK 进详情；`--play` 再按一次 OK 播放。
- `--expect <标题>` 对详情页做 OCR 校验，不匹配返回 3；输入核对失败返回 4，不会盲选。
- 播放页在同一个 `HomeSingleTaskActivity` 内，`am start` 退不出播放，脚本用 `am force-stop` 冷启动保证回到首页（约 20-30 秒）。
- 截图：搜索 `/tmp/tencent_search.png`，结果 `/tmp/tencent_result.png`，播放 `/tmp/tencent_play.png`。

### 2.6 NAS（WebDAV）

- 地址：`dav://192.168.1.53:5005/sata11-18072858035`
- 本机已通过 GVFS 挂载，可直接访问：
  `/run/user/1000/gvfs/dav:host=192.168.1.53,port=5005,ssl=false/sata11-18072858035`
- HTTP 端点：`http://192.168.1.53:5005/sata11-18072858035/`，需要 Basic 认证；GVFS 已缓存登录态。
- 本地凭据：`~/.env` 中的 `WEBDAV_URL`、`WEBDAV_USER`、`WEBDAV_PASS`、`WEBDAV_MUSIC`（权限 600）；脚本用 `set -a; . ~/.env; set +a` 加载。不要读取或导出密码。
- 内容：影视、无损音乐、电子书、手机备份等。
- 音乐目录：`dav://192.168.1.53:5005/sata11-18072858035/mp3/无损`
  （本地：`/run/user/1000/gvfs/dav:host=192.168.1.53,port=5005,ssl=false/sata11-18072858035/mp3/无损`）
  含 FLAC/APE/WMA；本机可用 VLC 播放。
- 远程 `/opt/my-agent` 的 `find_file.sh`、`music.sh`、`tv.sh` 已接入 WebDAV；媒体类优先调用远程工具。

### 2.7 本机 VLC 播放（默认普通窗口）

适用场景：在电视上看 NAS 电影 / 听音乐。

优先用 2.5.1 的 `tools/tv_play.sh`（电视直连 NAS，不占本机资源）；只有需要在**本机桌面**播放或做音频/背景音乐时才用下面的本机 VLC。

原则：**默认用 `vlc` 正常窗口打开**，不占满桌面，用户可继续使用桌面；只有用户明确要求全屏时才加 `--fullscreen`。不要用 `cvlc -I dummy` 做日常播放。

1. 确认电视在 HDMI3：
   `adb -s 192.168.1.110:5555 shell input keyevent 245`
2. 在 NAS 上模糊找片：目录名可能有错字（如“寒站1994”里放“寒战1994...”）；
   `find -iname '*中文*'` 在 GVFS 上可能匹配不到中文，优先用 `ls` / `gio list` 或远程 `find_file.sh`。
3. 普通窗口播放（音乐/背景）：

```bash
ROOT="/run/user/1000/gvfs/dav:host=192.168.1.53,port=5005,ssl=false/sata11-18072858035"
FILE="$ROOT/寒站1994/寒战1994.Cold.War.1994.2026.2160p.WEB-DL.H265.DTS-QuickIO.mkv"
export DISPLAY=:0 XAUTHORITY=/tmp/xauth_keOOxL
setsid nohup vlc --play-and-exit --no-video-title-show "$FILE" >/tmp/opencode/vlc.log 2>&1 &
echo $! > /tmp/opencode/vlc.pid
```

- 音乐可加 `--no-video`，视频默认窗口播放，可最小化。
- 仅当用户要求全屏电影时，把命令改为 `vlc --fullscreen ...`。
- 音频默认走 USB 小音箱（DTC 480）；确认未静音：
  `pactl set-sink-mute alsa_output.usb-DUNU_DTC_480_DTC_480-00.analog-stereo 0`
- 如果 VLC 记住最大化/全屏几何导致遮挡桌面：备份并删除
  `~/.config/vlc/vlc-qt-interface.conf`，再启动即恢复默认小窗。
- 停止：`kill $(cat /tmp/opencode/vlc.pid)`；不要用 `pkill -f 'vlc.*中文'`，容易误伤当前 shell。
- 本机 i5-2400 无 VA-API，4K HEVC 是软件解码（约 120% CPU）；卡顿就改用远程 `tv.sh`（电视硬解）或 1080p 版本。

已验证：`夜曲` 以正常窗口播放，桌面可继续使用；`寒战1994` 可全屏播放，画面到电视 HDMI3，音频到 3.5mm 小音响。

## 3. 远程主机能力（/opt/my-agent）

### 3.1 定位

- 远程 `192.168.1.10`（主电脑）是能力主机；本机 `192.168.1.68`（客厅小机箱）只做控制。
- my-agent 架构：语音/微信 → 单脑 `opencode`（tmux，端口 4097）→ 白名单工具 → 按来源回程。
- 三条铁律：入口只产文本、单脑、能力=白名单脚本。

### 3.2 插件体系

**operator：轻插件 + 白名单**

- 每个能力 = `operator/tools/<name>.sh`，头部写元数据：`@desc`、`@usage`、`@rule`、`@order`。
- `operator/plugin.sh new|list|index`：
  - `new` 生成工具模板；
  - `index` 扫描所有工具，自动生成 `operator/TOOLS.md`。
- `operator/opencode.json` 通过 `instructions` 加载 `TOOLS.md`、`CAPABILITIES.md`、`automation.md`。
- 权限默认 deny，只放行 `tools/*`；`opencode.json` 同时禁用 read/edit/glob/grep/list/task/webfetch。
- 兜底插件 `operator/.opencode/plugin/guard.js`：正则拦截 `&&`、`;`、`|`、重定向等拼接命令。
- 新增能力：`plugin.sh new` → 写实现 → `plugin.sh index` → `operator/start.sh` 重启（不热重载）。

**agentkit：LuaJIT + FFI 能力层**

- `ak.x11`：窗口定位/激活走 **libxdo FFI**（`operator/tools/xdo.lua`）；截屏、移动/点击/按键/打字、模板匹配、图像差分走 **`libagentkit.so` FFI**（`agentkit/cpp`，`make -C agentkit/cpp` 生成）；含 IBus 输入法切换。已不依赖 xdotool 命令，`luajit -e` 一行即可操作桌面。
- `ak.ocr`：PP-OCRv4，返回文本和坐标。
- `ak.voice`：ASR/TTS/录音（SenseVoice + Kokoro）。
- `ak.cdp`：CDP/DOM 精准操作；守护进程 `cdpd.js`（本机 9333），Chrome 只授权一次。
- `ak.map`：`maps/<app>.lua` 按窗口相对坐标固化控件；`ak.record`/`ak.batch` 录制和批处理。
- `adapters/`：generic、chrome、wechat、google、gemini、github、wordcard。
- 核心思路：探索一次 → 固化映射 → 生成 Lua 流程 → 回放并用 OCR/图像差分校验。
- 直接驱动示例（远程执行）：
  `luajit -e 'package.path="/opt/my-agent/?.lua;/opt/my-agent/?/init.lua;"..package.path; local ak=require("agentkit"); local w=ak.x11.window("标题",{exact=true}); w:activate(); w:click_text("导入",{0,0,180,720})'`
- 依赖：`libxdo3`、`agentkit/lib/libagentkit.so`；未设 `DISPLAY` 时自动从 `pcmanfm-qt` 会话读 `DISPLAY`/`XAUTHORITY`，可用 `AGENTKIT_LIB` 覆盖库路径。

### 3.3 调用方式

- 先看清单：`ssh quqiufeng@192.168.1.10 '/opt/my-agent/operator/plugin.sh list'`，或读 `operator/TOOLS.md`。
- 直接调用：`ssh quqiufeng@192.168.1.10 '/opt/my-agent/operator/tools/<name>.sh ...'`；参数和规则见工具头注释及 `TOOLS.md`。
- 浏览器：`tools/chrome_debug.sh` 起专用 Chrome（9222），再用 chrome-devtools MCP 或 `ak.cdp`；不要用本机 Puppeteer/headless 硬扛。
- 终端标签：`tools/termctl.sh tabs|shot [N]|send <N> "<指令>"`。
- 截图/OCR/GUI：`tools/screenshot.sh`、`agentkit`（`w:ocr()`、`w:click_text()`）、`tools/progress.sh`；精细操作直接 `luajit -e` 调 `ak.x11`（FFI），不要拼 xdotool 命令。
- 语音/微信：`tools/say.sh`、`tools/voices.sh`、`tools/wechat_send.sh`、`tools/wechat_send_file.sh`。
- 媒体/家居/手机/Kindle：`music.sh`、`tv.sh`、`camera.sh`、`photo.sh`、`phone.sh`、`ebook.sh`、`vacuum.sh`、`detect.sh`。
- 网络拓扑：远程用 `ssh quqiufeng@192.168.1.10 '/opt/my-agent/operator/tools/netmap.sh scan'`（生成 `operator/devices.json`、`NETWORK.md`、`devices.env`）；本机用 `tools/netmap.sh scan`。
- 手机音频：`phone_music.sh play|stop`（汽水音乐）、`phone_audio.sh start|stop|status`（scrcpy 转发到小音响）。
- 内容/数据/搜索：`image.sh`、`img_video.sh`、`video_dub.sh`、`lora.sh`、`stock.sh`、`dash.sh`、`google_search.sh`、`git_trending.sh`、`weibo_*.sh`、`douyin.sh`。
- 集群/会话：`remote.sh`；启动大脑：`operator/start.sh`（通常已在跑，不要随意重启）。

### 3.4 硬件与模型

- 远程：Ryzen 5 3500X（6C/6T）、24GB RAM、RTX 3080 20GB、914G 根盘 + 234G `/data`。
- 模型/运行时：`/data/models`、ONNX Runtime GPU、SenseVoice、Kokoro、CosyVoice。
- 核心链路以 C/C++/LuaJIT 为主，尽量不新增 Python 运行时依赖。
- 系统层没有 docker/ollama/nvcc 不代表没有能力；能力在 my-agent 自己的原生栈里。

### 3.5 关键文档

- `/opt/my-agent/README.md`：总览
- `/opt/my-agent/AGENTS.md`：开发/维护约定
- `/opt/my-agent/operator/AGENTS.md`：运行时契约
- `/opt/my-agent/operator/TOOLS.md`：白名单全表 + 规则
- `/opt/my-agent/operator/CAPABILITIES.md`：能力清单
- `/opt/my-agent/agentkit/README.md`：Lua 能力层
- `/opt/my-agent/automation.md`：全自动开发闭环

### 3.6 安全

- 只调用白名单 `tools/*`；不要绕过 guard 拼任意 shell。
- 不读取/导出 `~/.env`、Cookie、密码、API Key。
- 登录、验证码、支付、关机/重启等敏感操作先向用户确认。

## 4. 备用：DeepSeek Search / Fetch API

本地搜索优先 `tools/google_search.sh` / `tools/deepseek_search.sh`；需要远程登录态抓取时用 `fetch.sh`。

- Search：`POST https://api.deepseek.com/v1/tools/search`，字段 `query`、`count`、`need_content`。
- Fetch：`POST https://api.deepseek.com/v1/tools/fetch`，字段 `url`。
- Key 位置：`~/.local/share/opencode/auth.json` 的 `deepseek.key`，运行时读取，不要写进文档或脚本。

## 5. 本地 my-agent（最小子集）

### 5.1 运行

- 目录：`~/my-agent`
- 启动：`./start.sh` —— 用 LuaJIT FFI（libxdo）打开**一个** qterminal 标签并键入 tmux 命令：
  - tmux 窗口 `0:serve` → `opencode serve --port 4097`
  - tmux 窗口 `1:tui` → `opencode attach http://127.0.0.1:4097`（TUI，默认停在这里）
- tmux 窗口就是标签（状态栏 `0:serve 1:tui`），`Ctrl+B n/p` 切换；会话设了 `destroy-unattached`，关掉终端即销毁，不留后台。
- 打字前脚本自动把 IBus 切到英文（否则 libpinyin 会把 ASCII 转成中文），结束后还原。
- 工作目录固定为 `~/my-agent`，因此 opencode 会自动读取 `~/my-agent/AGENTS.md`。
- 发送消息：`./send.sh "现在几点"`（POST `/tui/append-prompt` + `/tui/submit-prompt`）
- 状态/停止：`./status.sh`（health + 进程）/ `./stop.sh`

### 5.1.1 语音 GUI（SDL2，本机）

- `gui/sdl/`：C + SDL2/SDL2_ttf 小窗口；**常驻采集** USB 麦克风（默认 Comica），静音切句 → `tools/asr.sh`（远程 SenseVoice）→ 文本唤醒词门控 → `tools/send.sh` 转发本地大脑（与远程 GUI 一样走 `/tui/append-prompt` + `/tui/submit-prompt`）。
- 唤醒词与远程一致：`VOICE_WAKE` 默认 `你好星期五,星期五`；唤醒后 10 秒内的话直接当指令（不需要再说唤醒词）；VAD 阈值可用 `VOICE_RMS` 调。
- 构建：`make -C gui/sdl`；运行：`gui/launch.sh`；桌面项 `~/.local/share/applications/myagent-voice.desktop`（`Terminal=false`）。
- 依赖：`libsdl2-dev`、`libsdl2-ttf-dev`、Noto CJK 字体。
- GUI 有「暂停监听」「换麦」和文本输入；大脑忙时自动重试 3 次；回复显示在 TUI。

### 5.2 本地能力边界

**本地直接做：**

- 时间/简单 shell、文件与 NAS/GVFS 访问
- VLC 音频/视频播放、3.5mm 输出、OS/ALSA 音量控制
- USB 麦克风录音（`record_mic.sh`）、音频频谱（`spectrum.sh`）
- USB 手机音频经 scrcpy 转发到 3.5mm 小音响（`phone_audio.sh`）
- TTS/ASR 的本地入口（`tts.sh`/`asr.sh`；实际模型计算在远程）
- 本地搜索（`google_search.sh` 本机 Chrome CDP；`deepseek_search.sh` DeepSeek Search API）
- Chrome 156 + CDP/headless（网页打开、DOM/截图、CDP 9222；`tools/chrome.sh`）
- ADB 控制电视、HDMI 切换、截图、xdotool 窗口操作
- 局域网扫描/拓扑：`tools/netmap.sh scan|show|sources`（UDP 触发 ARP + 端口探测，约 4 秒）
- 本地 tmux + opencode 大脑

**本地做不了，走远程：**

- GPU/模型推理、SenseVoice/Kokoro 的实际 TTS/ASR 计算、微信 OCR/发送
- 需要远程登录态/专用 Chrome MCP 的浏览器任务、媒体转码、手机/Kindle/摄像头/家居设备
- 出图/动画/字幕/配音/LoRA、登录态搜索/内容抓取等

### 5.3 本地工具层约定

- 每个能力一个 `~/my-agent/tools/<name>.sh`，头部写 `@desc`、`@usage`。
- **本机能做的**：直接在脚本里实现。
- **本机做不了的**：用 `tools/remote.sh <name> [args...]` 调用远程
  `/opt/my-agent/operator/tools/<name>.sh`。
- `tools/list.sh` 列出本地工具；`tools/now.sh` 是本地示例；
  `tools/remote.sh now` 是远程示例。
- `tools/tts.sh "文本"`：只调远程 `operator/tools/living_audio.sh say`；远程合成后自己 scp 到本机 `/tmp/living-audio-say.wav` 并播放，本地不做额外处理。
- `tools/asr.sh <本地音频>`：本地音频 scp 到远程，调 `voice/listen.sh --file` 识别并返回文本。
- 注意：远程 `voice/say.sh` 默认播放到远程自己的 sink；要让全屋小音响发声，用 `operator/tools/living_audio.sh`。
- `tools/spectrum.sh [bands] [fps]`：抓 **USB 麦克风**音频频谱，输出 JSON Lines（`ts/rms/peak/bands`）；默认自动选 Comica，可用 `SPECTRUM_SOURCE` 覆盖。要抓播放频谱时传播放 sink 的 `.monitor`。
- `tools/record_mic.sh [seconds] [out.wav]`：录制 USB 麦克风到 WAV，默认自动选 Comica。
- `tools/chrome.sh open <url>` / `dump <url>` / `shot <url> <out.png>` / `cdp [port]`：本地 Chrome 网页、headless DOM/截图、CDP（默认 9222，profile `~/.chrome-debug`）。已验证 Chrome 156 + CDP 可用。
- `tools/google_search.sh "关键词" [count]`：本机 Chrome CDP 打开 Google，输出结果正文和外部链接；headless 会被 CAPTCHA，必须 headful。
- `tools/deepseek_search.sh "关键词" [count]`：调 DeepSeek Search API，输出标题/链接/摘要。
- `tools/phone_music.sh play|stop`：手机汽水音乐；`tools/phone_audio.sh start|stop|status`：手机音频经 scrcpy 转发到 3.5mm 小音响。
- `tools/netmap.sh scan|show|sources`：本机扫 192.168.1.0/24，输出 `NETWORK.local.md`、`devices.local.json`、`devices.local.env`（`NETMAP_*_IP`）。
- `tools/doctor.sh`：只读检查依赖、本地大脑、远程、手机、Chrome CDP。
- 回环测试：`tts.sh` → 小音响 → `record_mic.sh` → `asr.sh` 已验证可行。音量有三层：音响物理旋钮、本机 OS 音量（PipeWire/Pulse）、ALSA PCM。`tts.sh` 默认用 `SMALLPC_AOUT=pulse`，因此 OS 音量可调；100% + 麦克风增益最大容易削波，回环时建议适当降低。短句识别准确，长句可能有误差。
- 大脑只调用 `tools/*.sh`，不要临时拼一长串命令。

这是最小大脑运行时，不含远程的 `operator/tools` 白名单、`guard.js`、语音/微信入口；重活仍走远程。
