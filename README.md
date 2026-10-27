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
- 本地语音：`tools/setup_local_voice.sh`（sherpa-onnx KWS/Kokoro + SenseVoice.cpp CPU）
- 运行时 `libxdo.so.3` 已随仓库放在 `gui/lib/`，不要求目标系统安装 `libxdo3`

Ubuntu 可参考：

```bash
sudo apt-get install -y tmux python3 python3-requests python3-numpy \
  python3-websocket scrcpy adb xdotool scrot \
  libluajit-5.1-dev libsdl2-dev libsdl2-ttf-dev libsdl2-image-dev
```

语音 GUI 把 LuaJIT 与 `tools/winctl.lua`、`tools/xdo.lua` 内嵌进二进制：

```bash
make -C gui/sdl          # 静态链 LuaJIT + SDL，KWS 链 /opt/sherpa-onnx；KWS=0 可关闭
```

构建后 `tools/lua.sh` 会优先用 `gui/sdl/myagent-voice --lua` 执行脚本，没有二进制时才退回系统 `luajit`。
语音识别/合成优先本地：`tools/asr.sh` 用 SenseVoice.cpp，`tools/tts.sh` 用 Kokoro；不可用时自动回退远程。
二进制通过 `RUNPATH=$ORIGIN/../lib` 优先加载 `gui/lib/libxdo.so.3`。

## 本地语音模型（KWS / ASR / TTS）

语音 GUI 默认全本地运行，模型不放进 git 仓库，统一安装在 `/opt`：

| 用途 | 运行时 | 模型/数据 | 默认路径 | 约 |
|---|---|---|---|---|
| 唤醒词 | sherpa-onnx KWS | `sherpa-onnx-kws-zipformer-wenetspeech-3.3M-2024-01-01` | `/opt/sherpa-onnx/models/…` | 35 MB |
| 文本转语音 | sherpa-onnx + Kokoro | `kokoro-multi-lang-v1_0` | `/opt/sherpa-onnx/models/…` | 352 MB |
| 语音转文本 | SenseVoice.cpp（CPU） | `sense-voice-small-q4_k.gguf` | `/opt/SenseVoice.cpp/models/…` | 174 MB |
| 运行时 | sherpa-onnx | `bin/lib/include` | `/opt/sherpa-onnx/` | 85 MB |
| 运行时 | SenseVoice.cpp | 本地编译的 CPU 版 | `/opt/SenseVoice.cpp/{bin,lib}` | 2 MB |

### 一键安装（本局域网，从 192.168.1.10 复制）

```bash
tools/setup_local_voice.sh
```

脚本会：复制 sherpa-onnx 运行时；下载中文 KWS 模型；从主电脑复制 Kokoro 模型；克隆并编译 SenseVoice.cpp（CPU）；复制 SenseVoice GGUF 模型；安装 `python3-pypinyin`。需要到主电脑的免密 SSH、`sudo`、`git/cmake/g++/python3`。

### 手动下载（没有主电脑时）

1) sherpa-onnx 运行时（版本与构建保持一致，当前 1.13.8）：

```bash
curl -L -o /tmp/sherpa.tar.bz2 \
  https://github.com/k2-fsa/sherpa-onnx/releases/download/v1.13.8/sherpa-onnx-v1.13.8-linux-x64-shared.tar.bz2
tar xjf /tmp/sherpa.tar.bz2 -C /tmp
sudo mkdir -p /opt/sherpa-onnx
sudo cp -a /tmp/sherpa-onnx-v1.13.8-linux-x64-shared/{bin,lib,include} /opt/sherpa-onnx/
```

如果使用其他版本，重新构建并指向该目录：`make -C gui/sdl SHERPA_DIR=/opt/sherpa-onnx`。

2) 中文 KWS 唤醒词模型：

```bash
curl -L -o /tmp/kws.tar.bz2 \
  https://github.com/k2-fsa/sherpa-onnx/releases/download/kws-models/sherpa-onnx-kws-zipformer-wenetspeech-3.3M-2024-01-01.tar.bz2
tar xjf /tmp/kws.tar.bz2 -C /tmp
sudo mkdir -p /opt/sherpa-onnx/models
sudo cp -a /tmp/sherpa-onnx-kws-zipformer-wenetspeech-3.3M-2024-01-01 /opt/sherpa-onnx/models/
```

3) Kokoro TTS 模型：

```bash
curl -L -o /tmp/kokoro.tar.bz2 \
  https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-multi-lang-v1_0.tar.bz2
tar xjf /tmp/kokoro.tar.bz2 -C /tmp
sudo mkdir -p /opt/sherpa-onnx/models
sudo cp -a /tmp/kokoro-multi-lang-v1_0 /opt/sherpa-onnx/models/
```

4) SenseVoice.cpp CPU ASR：

```bash
sudo apt-get install -y git cmake g++ python3-pypinyin
git clone --recursive --depth 1 https://github.com/lovemefan/SenseVoice.cpp.git /tmp/SenseVoice.cpp
sudo mv /tmp/SenseVoice.cpp /opt/SenseVoice.cpp
sudo chown -R "$USER" /opt/SenseVoice.cpp
cmake -S /opt/SenseVoice.cpp -B /opt/SenseVoice.cpp/build-cpu \
  -DCMAKE_BUILD_TYPE=Release -DGGML_CUDA=OFF
cmake --build /opt/SenseVoice.cpp/build-cpu -j"$(nproc)"
mkdir -p /opt/SenseVoice.cpp/{bin,lib,models}
cp /opt/SenseVoice.cpp/build-cpu/bin/sense-voice-main /opt/SenseVoice.cpp/bin/
cp -a /opt/SenseVoice.cpp/build-cpu/lib/libggml*.so* /opt/SenseVoice.cpp/lib/
curl -L -o /opt/SenseVoice.cpp/models/sense-voice-small-q4_k.gguf \
  https://huggingface.co/lovemefan/sense-voice-gguf/resolve/main/sense-voice-small-q4_k.gguf
```

5) 生成唤醒词文件（修改唤醒词后需重新生成）：

```bash
tools/kws_keywords.py "你好星期五,星期五,开发者,开发者模式,退出开发者" > gui/kws/keywords.txt
```

6) 构建并验证：

```bash
make -C gui/sdl
tools/asr.sh /tmp/test.wav                      # 本地 SenseVoice
TTS_NOPLAY=1 tools/tts.sh "你好"                 # 本地 Kokoro
gui/launch.sh                                    # 说唤醒词测试 KWS
```

### 可覆盖的配置

| 变量 | 默认 | 用途 |
|---|---|---|
| `KWS_MODEL_DIR` | `/opt/sherpa-onnx/models/sherpa-onnx-kws-…` | KWS 模型目录 |
| `KWS_KEYWORDS` | `gui/kws/keywords.txt` | 唤醒词文件 |
| `KWS_THRESHOLD` / `KWS_SCORE` | `0.25` / `1.0` | 唤醒灵敏度 |
| `KOKORO_DIR` | `/opt/sherpa-onnx/models/kokoro-multi-lang-v1_0` | TTS 模型 |
| `KOKORO_SID` / `TTS_THREADS` | `47` / `4` | 音色 / 线程 |
| `SENSEVOICE_BIN` / `SENSEVOICE_MODEL` | `/opt/SenseVoice.cpp/…` | ASR 二进制 / GGUF |
| `SENSEVOICE_DIR` / `SENSEVOICE_THREADS` | `/opt/SenseVoice.cpp` / `4` | ASR 工作目录 / 线程 |
| `ASR_LOCAL=0` / `TTS_LOCAL=0` | 自动 | 强制回退远程 |
| `make KWS=0` | 开启 | 关闭本地 KWS，退回文本唤醒 |

说明：模型合计约 600 MB；SenseVoice 首次运行会在其工作目录写 `fbank_lfr_cmvn_feature.json`（已加入 `.gitignore`）；本机 i5-2400 上 ASR 约 1–2 秒，Kokoro 短句约 6–8 秒，唤醒应答会在后台预合成。

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
