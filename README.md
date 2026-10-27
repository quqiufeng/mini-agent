# my-agent（本地最小子集）

本地版的 tmux + opencode 大脑，只保留 remote `/opt/my-agent` 的最核心结构：

```
tmux session: local-my-agent
├─ window "serve": opencode serve --port 4097
└─ window "tui":   opencode attach http://127.0.0.1:4097
```

`opencode` 的工作目录固定为 `~/my-agent`，启动时会自动读取 `~/my-agent/AGENTS.md`，因此它知道本机/远程的能力和调用方式。

## 用法

```bash
cd ~/my-agent

./start.sh            # 启动并 attach
./start.sh --bg       # 只后台启动
./status.sh           # 查看 session / 窗口 / 4097 健康状态
./send.sh "现在几点"   # 通过 /tui 接口向大脑提交一条消息
./tools/doctor.sh     # 检查依赖、大脑、远程、手机、Chrome
./tools/list.sh       # 列出本地工具
./stop.sh             # 停止
```

端口可用 `AGENT_PORT` 覆盖，session 名可用 `AGENT_SESSION` 覆盖。

## 依赖

- `tmux`、`opencode`、`curl`、`python3`
- Python：`requests`、`numpy`、`websocket-client`
- Chrome / Chromium、`adb`、`scrcpy`、`xdotool`、`scrot`
- 到远程 `quqiufeng@192.168.1.10` 的免密 SSH
- 远程 `/opt/my-agent` 的白名单工具（TTS/ASR、微信、媒体、手机等）
- 构建语音 GUI：`libluajit-5.1-dev`、`libsdl2-dev`、`libsdl2-ttf-dev`、`libsdl2-image-dev`
- 运行时 `libxdo.so.3` 已随仓库放在 `gui/lib/`，不要求目标系统安装 `libxdo3`

Ubuntu 可参考：

```bash
sudo apt-get install -y tmux python3 python3-requests python3-numpy \
  python3-websocket scrcpy adb xdotool scrot \
  libluajit-5.1-dev libsdl2-dev libsdl2-ttf-dev libsdl2-image-dev
```

语音 GUI 把 LuaJIT 与 `tools/winctl.lua`、`tools/xdo.lua` 内嵌进二进制：

```bash
make -C gui/sdl          # 静态链 LuaJIT + SDL，运行时不依赖系统 luajit
```

构建后 `tools/lua.sh` 会优先用 `gui/sdl/myagent-voice --lua` 执行脚本，没有二进制时才退回系统 `luajit`。
二进制通过 `RUNPATH=$ORIGIN/../lib` 优先加载 `gui/lib/libxdo.so.3`。

## 文件

| 文件 | 用途 |
|---|---|
| `start.sh` | 幂等启动 serve + tui，可选 attach |
| `stop.sh` | 停止 tmux session |
| `status.sh` | 查看运行状态和健康检查 |
| `send.sh` | POST `/tui/append-prompt` + `/tui/submit-prompt` |
| `tools/` | 本地能力层；每个能力一个 `*.sh`，头部有 `@desc`/`@usage` |
| `tools/doctor.sh` | 只读检查依赖、本地大脑、远程、手机、Chrome CDP |

## 与 remote my-agent 的差异

- 这是**最小大脑运行时**，不包含 remote 的 `operator/tools` 白名单、`guard.js`、语音/微信入口和心跳。
- 本地 opencode 的权限由 `~/.config/opencode/opencode.json` 决定，默认比 remote 宽；真正的重活仍应调用 `AGENTS.md` 里记录的远程能力。
- 不要把 `~/.env`、Cookie、API Key、日志或临时 PID 提交进仓库。

仓库：`git@github.com:quqiufeng/mini-agent.git`
