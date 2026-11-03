# my-agent 本地版架构设计（v2）

> 状态：设计稿，待实施
> 范围：`/home/quqiufeng/my-agent`（客厅小机箱，最小大脑运行时）
> 原则：小内核、快切、不做长期兼容层；GUI 保持现有 C/SDL，不引入 Flutter/Web
> 参考：远程 `/opt/my-agent/design.md`，只取本地需要的最小闭包

---

## 1. 目标与非目标

### 1.1 目标

- 运行时零 Python。
- 代码只分三层：`lib/`（内核/设备/状态）、`plugins/`（场景能力）、`gui/sdl/`（C/SDL 界面）。
- 所有设备状态只有**一个来源**：`lib/state.lua`（落盘 `~/.myagent/state.json`）。
- 所有设备操作只有一个入口：`plugins/*/entry/*.sh`（薄入口）→ Lua 实现。
- `.sh` 只做参数透传 + 元数据，不写业务分支。
- 新 Lua 禁止 `os.execute` / `io.popen`；新 C 禁止 `system()` / `popen()`。
- 进程启动统一走 `lib/core.lua` 的 argv 接口。
- 每次动作尽量留下 evidence/trace，便于回放和回归。
- GUI 只读状态、调入口、展示证据，不承载业务。

### 1.2 非目标

- 不使用 Flutter/Web；继续用 `gui/sdl` C/SDL。
- 不实现 mmap KV、完整拓扑图、事件总线服务（先用 JSON + 文件事件日志）。
- 不重写 OpenCV/SenseVoice/Kokoro/scrcpy/VLC。
- 不为旧 `tools/*.sh` 保留长期兼容层；迁移完成即删业务脚本。
- 不把远程 `operator/`、`agentkit/` 全量搬来。

---

## 2. 目标目录

```text
lib/
  core.lua          # argv / fs / json / env / log / lock
  state.lua         # 单一状态源，原子写、TTL、watch
  device.lua        # 设备注册、lease、状态、provider
  events.lua        # 事件日志（文件）
  trace.lua         # trace 记录/回放
plugins/
  media/            # VLC 播放、暂停、切歌、列表
  phone/            # Redmi 汽水音乐、微信镜像
  camera/           # TP-Link 遮挡暂停
  voice/            # TTS/ASR/KWS/提醒
  wechat/           # 发送、截图、显示
  tv/               # Sony 开关、HDMI、腾讯视频、NAS 直连
  system/           # 音量、闹钟、netmap、搜索、Chrome、OCR
  _template/        # 新插件模板
gui/sdl/            # 现有 C/SDL，保留
tools/              # 只保留薄入口（迁移期），最终清空
operator/           # 大脑启动/端口/AGENTS（本地最小）
  start.sh stop.sh status.sh send.sh
  ports.env
  AGENTS.runtime.md
  AGENTS.plugins.md
AGENTS.md           # 根开发规范
design.md           # 本文
todolist.md         # 迁移任务清单
```

依赖方向只能向下：

```text
gui/sdl → plugins/entry → plugins/*.lua → lib/* → native/系统库
```

禁止：

- `lib` 引用 `plugins`
- `plugins` 直接操作 X11/ADB/HTTP（必须经 `lib`）
- `gui` 直接判断设备状态或拼接业务命令

---

## 3. lib/core.lua

统一原语，禁止 shell 拼接。

```lua
core.exec.argv(argv, opts)        -- 前台执行，无 shell
core.exec.spawn_argv(argv, log)   -- 后台启动，返回 pid
core.exec.which(bin)
core.fs.read/write/write_atomic/list/copy/move/rm/mkdirp/size
core.json.encode/decode/safe_decode
core.env.load/get/key/auth/redact
core.log.event(type, data)
core.lock.with(path, fn)
core.time.now/ms/sleep_ms
```

规则：

- 参数必须是数组，不允许拼字符串。
- 用户输入不进入 argv[0]；路径必须校验。
- 大文件/二进制写文件，不做文本编码。
- 错误统一返回 `nil, err`；入口脚本转换成退出码。

---

## 4. lib/state.lua

### 4.1 单一来源

- 目录：`~/.myagent/state/<key>`（每个 key 一个文件；值为 `state ts pid [extra...] @seq`）
- 原子写：临时文件 + `rename`
- TTL：带 `ts` 的状态超时视为失效
- 迁移：旧 `/tmp/myagent_state` 由 `lib/state_core.lua` 一次性导入
- JSON/KV 导出为后续项（kvcache 源码已放 `/opt/my_db_src`）

### 4.2 结构

```json
{
  "media.vlc":   {"state":"playing","ts":1790000000,"pid":1234,"title":"..."},
  "media.phone": {"state":"paused","ts":1790000001,"pid":5678,"serial":"192.168.1.59:5555"},
  "speaker":     {"state":"busy","ts":1790000002},
  "camera":      {"state":"clear","ts":1790000003},
  "display.wechat": {"state":"on","ts":1790000004,"pid":9012},
  "device.phone":   {"state":"ready","ts":1790000005,"serial":"..."},
  "device.tv":      {"state":"online","ts":1790000006,"serial":"..."}
}
```

### 4.3 API

```lua
state.set(key, value, extra)   -- 自动写 ts
state.get(key)                 -- 返回 table 或 nil
state.del(key)
state.show()                   -- 全量
state.active_media()           -- playing 优先，其次最新 paused
state.any_playing()            -- 所有 playing
state.tidy()                   -- 清理死 pid / 过期项
```

### 4.4 约束

- 禁止新增 `/tmp/*.pid`、`/tmp/*.playing`、`/tmp/*.state` 业务标记。
- 状态只由生产者在状态变化时写；消费者只读。
- 所有 pid 状态必须校验 `/proc/<pid>/cmdline` 与预期进程匹配。

---

## 5. lib/device.lua

轻量设备层，不做完整拓扑图。

### 5.1 设备模型

```lua
{
  id = "phone",
  type = "phone",              -- phone/tv/camera/audio/player/computer
  transport = "adb",           -- adb/rtsp/alsa/x11
  serial = "192.168.1.59:5555",
  capabilities = {"play","pause","next","mirror"},
  state = "ready",             -- online/ready/busy/idle/error/offline
  last_seen = 1790000000,
  lease = nil,
}
```

### 5.2 Provider

- `adb`：手机/电视
- `alsa`：USB 小音箱、麦克风
- `rtsp`：TP-Link 摄像头
- `x11`：VLC 窗口/当前应用
- `netmap`：网络设备基线

Provider 只负责发现/探测，不写业务。

### 5.3 Lease

```lua
local lease = device.acquire("phone", {purpose="phone_music", ttl=30})
lease:release()
```

- 同一资源默认独占：摄像头、麦克风、手机 ADB、电视 ADB。
- lease 带 TTL；进程崩溃自动过期。
- 冲突返回 `busy` + 当前 owner。
- 替代旧的 pid 文件。

### 5.4 状态

- `device.state(id)` 只读状态，UI/插件不自行 `adb devices`/`pactl`。
- 状态变化写 `state.set("device.<id>", ...)` 并记事件。

---

## 6. lib/events.lua / trace.lua

- 事件先写 `~/.myagent/events.log`（JSON Lines），不做常驻总线。
- 事件类型：`media.*`、`device.*`、`plugin.start/end/error`、`camera.blocked/clear`、`tts.*`。
- trace 记录：`trace_id`、plugin、action、before/after、result、duration。
- 用途：失败回放、回归金样本、后续训练数据；先保证可读，不追求完整。

---

## 7. 插件体系

### 7.1 目录

```text
plugins/media/
├─ plugin.json
├─ entry/play.sh
├─ entry/pause.sh
├─ entry/resume.sh
├─ entry/next.sh
├─ entry/prev.sh
├─ entry/stop.sh
├─ entry/status.sh
├─ media.lua
└─ test/media.lua
```

### 7.2 plugin.json（最小）

```json
{
  "id": "media",
  "version": "1.0.0",
  "apiVersion": "1",
  "type": "tool",
  "entry": "entry/",
  "capabilities": ["media", "vlc"],
  "permissions": ["audio", "x11", "process"],
  "dependencies": ["lib.core", "lib.state", "lib.device"]
}
```

### 7.3 entry/*.sh 规则

```sh
#!/usr/bin/env bash
# @desc 播放 NAS 媒体
# @usage entry/play.sh <关键词>
# @rule 只透传，不写业务
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec luajit "$DIR/../media.lua" play "$@"
```

禁止：

- 在 `.sh` 里判断设备/进程
- 拼接用户输入进 shell
- 直接 kill/spawn 业务进程

### 7.4 Host API（Lua 插件可用）

```lua
host.exec.argv / host.fs / host.json
host.state.get/set
host.device.acquire/release/state
host.events.publish
host.log
host.trace
```

插件不直接 `require("lib.ffi.*")`，不直接 `adb`/`pactl`/`ffmpeg`（统一走 lib 封装）。

---

## 8. 首批插件

| 插件 | 入口 | 说明 |
|---|---|---|
| media | play/pause/resume/next/prev/stop/status | VLC + NAS 搜索 + 播放列表 |
| phone | play/pause/resume/stop/wechat/mirror | Redmi 汽水音乐、微信镜像 |
| camera | start/stop/status | TP-Link 副码流遮挡 → 暂停当前媒体 |
| voice | say/listen/tts/asr/kws | 本地 TTS/ASR/KWS |
| wechat | send/shot/show | 手机微信发送/截图/镜像 |
| tv | on/off/input/play/tencent | Sony TV、HDMI、NAS 直连 |
| system | volume/alarm/netmap/search/chrome/ocr | 基础系统能力 |

每个插件必须有：

- `plugin.json`
- 至少 3 条 contract：成功、坏参数、进程/设备失败
- 一次真实 smoke 证据（日志/截图/OCR）

---

## 9. GUI（C/SDL，保留）

### 9.1 职责

- 语音入口：KWS → ASR → 调用 `operator/send.sh` 或本地快捷命令。
- 状态展示：读 `~/.myagent/state.json`，显示媒体、监听、设备。
- 当前应用：scrcpy 窗口由插件定位，GUI 只显示面板。
- 按钮：暂停/继续/切歌/音量 → 调 `plugins/*/entry/*.sh`，不自己做判断。

### 9.2 不做

- 不直接 `adb`/`pactl`/VLC MPRIS 判断。
- 不写业务分支（如“手机在播还是 VLC 在播”）。
- 不引入 Flutter/Web。

### 9.3 过渡

- 现有 `gui/sdl/main.c` 保留。
- 先把 `speaker_busy()` 改为读 `lib/state` 导出的状态文件。
- 再把媒体按钮改为调用插件入口。
- 最后删掉 C 里的 `system()` 和业务判断。

---

## 10. 大脑与 operator

- 单脑：`opencode serve --port $AGENT_PORT` + attach；端口写 `operator/ports.env`。
- 开发者 TUI：独立 server `$DEV_PORT`，默认 4098；不与大脑共用。
- `operator/AGENTS.runtime.md`：大脑每次加载的契约（工具选择、状态、证据、失败处理）。
- `operator/AGENTS.plugins.md`：插件开发规范（manifest、入口、权限、测试）。
- 根 `AGENTS.md`：只写开发/构建/迁移规则，不写每次运行细则。
- `TOOLS.md` 由插件 index 生成，不手写。

---

## 11. 迁移映射

| 旧 | 新 |
|---|---|
| `tools/state.sh` | `lib/state.lua` + 薄入口 |
| `tools/devctl.sh` | `plugins/*/entry` + `lib/device.lua` |
| `tools/media.sh` | `plugins/media` |
| `tools/phone_music.sh` / `phone_media.sh` | `plugins/phone` |
| `tools/wechat_show.sh` | `plugins/wechat` |
| `tools/camera_block.cpp/.sh` | `plugins/camera` + `lib/device` |
| `tools/speaker_watch.sh` | `lib/state` + `plugins/system` |
| `tools/tts.sh` / `asr.sh` / `speak_watch.sh` / `kws_keywords.sh` | `plugins/voice` |
| `tools/tv_play.sh` / `tencent.sh` / `tv_on.sh` | `plugins/tv` |
| `tools/netmap.sh` / `netscan.sh` | `plugins/system` + `lib/device/provider/netmap` |
| `tools/http.lua` / `ws.lua` / `jsonc.lua` | `lib/transport` / `lib/core` |
| `tools/xdo.lua` / `winctl.lua` | `lib/act/x11` |
| `gui/sdl` | 保留，接 host API |

旧脚本迁移完成后删除，不保留兼容层；git 历史可回滚。

---

## 12. 里程碑

### C0 基线

- git checkpoint；记录当前可用功能。
- 建 `lib/test/` 与 `todolist.md`。

### C1 内核 + 状态

- `lib/core.lua`、`lib/state.lua`。
- `state.sh` 变薄入口；`/tmp` 状态迁到 `~/.myagent/state.json`。
- 验收：原子写、TTL、死 pid 清理、GUI 读状态正常。

### C2 设备层

- `lib/device.lua`：注册 Redmi/Sony/TP-Link/USB 音箱/VLC。
- lease 替代 pid 文件。
- 验收：`device.state` 全部来自 device 层；停止后 lease 释放。

### C3 媒体/手机/摄像头插件

- `plugins/media`、`plugins/phone`、`plugins/camera`。
- 去掉 `camera_block.cpp` 的 `system/popen`，改为 argv/service。
- 验收：播放/暂停/切歌/遮挡暂停全走插件。

### C4 其余插件

- `voice/wechat/tv/system`；清掉 Lua 里的 `os.execute/io.popen`。
- 验收：每个插件 entry + contract test。

### C5 GUI 收口

- GUI 只读 state、调 entry；删旧业务分支和 `system()`。
- 验收：按钮/语音/状态与 CLI 一致。

### 实施进度（当前）

- C0 已完成：checkpoint tag、state/device/contract 测试。
- C1 已完成：`lib/core.lua`、`lib/state_core.lua`、`state.sh` 薄入口、状态迁到 `~/.myagent/state/`。
- C2 已完成：`lib/device.lua`、adb/alsa/rtsp/x11 provider、media/phone/wechat/camera 的 lease。
- C3 已完成（结构）：media/phone/wechat/camera 实现移入 `plugins/`，`tools/` 为薄入口。
- C4：voice/tv/system 实现已迁到 plugins（system 含 volume/alarm/netmap/search/chrome/ocr/win_resize）；spectrum 例外。
- C5 完成：GUI 读新 state，媒体/音量走 entry；C 代码已去掉 `system()`。
- 开发者 TUI 已切到独立 server（DEV_PORT=4098，tmux serve+tui），并优先恢复该目录上次 session。
- 自主开发插件：`tools/plugin.sh new/validate/list/index/test`（远程 operator/plugin.sh 的本地实现）。
- C6 进行中：AGENTS 三层文件/opencode.json 已接入；TOOLS/e2e 已有；共享 FFI 模块移入 lib；剩 spectrum 与硬件 e2e/trace。
- 可选：`lib/ffi/kv.lua` 绑定 `/opt/my_db_src/include/cache.h`。

### C6 清理

- 删除旧 `tools/*` 业务脚本、`/tmp` 标记、重复 pid 文件。
- 依赖收敛：`libcurl/json-c/OpenCV/ALSA/PipeWire/ffmpeg`。
- 验收：全量 smoke + trace 回放通过。

---

## 12A. 会话模式

- `lib/session.lua`：会话上下文（plugin/init/context/since/until/source），TTL 默认 1800s。
- 后端：`lib/ffi/kv.lua` → `cache_open/set/get/del`，数据在 `~/.myagent/kv/`（`cache.bin`）。
- 构建：`lib/native/build.sh` 从 `/opt/my_db_src` 生成 `lib/native/libmydb.so`。
- 入口：`tools/session.sh enter|get|touch|exit|route`。
- 路由：`#plugin@args` 优先；当前会话 `session_commands` 其次；再按 manifest `intents` 匹配。
- 约束：单脑、单 active context；ID 仅 `[A-Za-z0-9_:.%%/-]`，≤128；TTL 过期即删。

---

## 13. 验收标准

- 运行时无 Python。
- 新 Lua 无 `os.execute/io.popen`；新 C 无 `system/popen`。
- `.sh` 只透传，有 `@desc/@usage/@rule`。
- 设备状态只从 `lib/state`/`lib/device` 读取。
- 没有 `/tmp` 业务状态；没有自建 pid 文件。
- 每个插件有 manifest、entry、test。
- 播放/暂停/切歌/音量/遮挡暂停在 GUI、语音、CLI 三处结果一致。
- 失败有日志/证据可查。

---

## 14. 最终形态

```text
lib       = 原语 + 状态 + 设备
plugins   = 场景能力
gui/sdl   = 语音入口 + 状态展示
operator  = 大脑启动 + 契约
```

一句话：**lib 提供能力，plugins 提供场景，GUI 只做入口和展示。**
